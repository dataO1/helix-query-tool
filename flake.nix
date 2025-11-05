{
  description = "HelixDB Auto-Indexing System with Real HelixDB Service and Smart Chunking";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix-db-src = {
      url = "github:HelixDB/helix-db";
      flake = false;
    };
    helix-py-src = {
      url = "github:HelixDB/helix-py";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, home-manager, helix-db-src, helix-py-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # ============================================================
        # HelixDB Python Package - uses hatchling build backend
        # ============================================================
        helix-py-pkg = pkgs.python3.pkgs.buildPythonPackage {
          pname = "helix-py";
          version = "0.2.30";
          src = helix-py-src;

          pyproject = true;
          build-system = [ pkgs.python3.pkgs.hatchling ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
            requests
            pydantic
            httpx
            tqdm
            python-dotenv
          ];

          doCheck = false;
          dontCheckRuntimeDeps = true;
          dontUsePythonImportsCheck = true;

          meta = with pkgs.lib; {
            description = "HelixDB Python client library";
            homepage = "https://github.com/HelixDB/helix-py";
            license = licenses.asl20;
          };
        };

        # Python environment with HelixDB dependencies
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pyinotify
          requests
          pyyaml
          watchdog
          helix-py-pkg
        ]);

        # ============================================================
        # Real HelixDB Rust Package from source
        # FIX: Do NOT use --release flag with buildRustPackage
        # Nix handles release/debug mode automatically via cargoTestType
        # ============================================================
        helixdb = pkgs.rustPlatform.buildRustPackage rec {
          pname = "helix-db";
          version = "2.0.5";

          src = helix-db-src;

          cargoLock = {
            lockFile = "${helix-db-src}/Cargo.lock";
          };

          nativeBuildInputs = with pkgs; [
            pkg-config
          ];

          buildInputs = with pkgs; [
            openssl
          ];

          # REMOVED: cargoBuildFlags = [ "--release" ];
          # buildRustPackage already builds in release mode by default
          doCheck = false;

          postInstall = ''
            mkdir -p $out/bin
            if [ -f target/release/helix-db ]; then
              cp target/release/helix-db $out/bin/
            elif [ -f target/release/helix_db ]; then
              cp target/release/helix_db $out/bin/helix-db
            fi
          '';

          meta = with pkgs.lib; {
            description = "HelixDB - Open-source Graph-Vector Database";
            homepage = "https://github.com/HelixDB/helix-db";
            license = licenses.asl20;
            platforms = platforms.unix;
          };
        };

        # ============================================================
        # HelixDB Indexer Service Script (Uses built-in chunking)
        # ============================================================
        helixIndexerScript = pkgs.writeScriptBin "helix-file-indexer" ''
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_indexer.py}
        '';

        # ============================================================
        # CLI Search Tool (Real backend connection)
        # ============================================================
        helixSearchTool = pkgs.writeScriptBin "helix-search" ''
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_search.py}
        '';

        # ============================================================
        # MCP Server Script
        # ============================================================
        helixMcpServer = pkgs.writeScriptBin "helix-mcp-server" ''
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_mcp_server.py}
        '';

      in {
        # ============================================================
        # Packages
        # ============================================================
        packages = {
          helixdb = helixdb;
          helix-indexer = helixIndexerScript;
          helix-search = helixSearchTool;
          helix-mcp-server = helixMcpServer;
          helix-py = helix-py-pkg;
          default = helixSearchTool;
        };

        # ============================================================
        # Development Shell
        # ============================================================
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pythonEnv
            helixIndexerScript
            helixSearchTool
            helixMcpServer
            pkgs.rust-bin.stable.latest.default
            cargo
            pkg-config
            openssl
          ];

          shellHook = ''
            export RUST_LOG=info
          '';
        };

        # ============================================================
        # Home-Manager Module
        # ============================================================
        homeManagerModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.services.helix-search;
          in {
            options.services.helix-search = {
              enable = lib.mkEnableOption "HelixDB search CLI integration";

              searchPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "$HOME" ];
                description = "Paths to suggest for indexing (user-level only)";
              };

              aliases = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = {
                  "hs" = "helix-search";
                  "hsf" = "helix-search --files";
                  "hsc" = "helix-search --code-only";
                };
                description = "Shell aliases for search commands";
              };
            };

            config = lib.mkIf cfg.enable {
              home.packages = [ self.packages.${system}.helix-search ];

              programs.bash.shellAliases = cfg.aliases;
              programs.zsh.shellAliases = cfg.aliases;
              programs.fish.shellAliases = cfg.aliases;

              xdg.configFile."helix-search/config.yaml".text = ''
                helix_db:
                  host: "localhost"
                  port: 6969
                  timeout: 30
                cli:
                  default_limit: 15
                  highlight_results: true
                  show_snippets: true
              '';
            };
          };

        # ============================================================
        # NixOS Module
        # ============================================================
        nixosModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.services.helix-indexer;
            helixdbCfg = config.services.helixdb;
          in {
            # ========================================================
            # HelixDB Service Module
            # ========================================================
            options.services.helixdb = {
              enable = lib.mkEnableOption "HelixDB vector-graph database service";

              host = lib.mkOption {
                type = lib.types.str;
                default = "127.0.0.1";
                description = "Bind address for HelixDB";
              };

              port = lib.mkOption {
                type = lib.types.port;
                default = 6969;
                description = "Port for HelixDB";
              };

              dataDir = lib.mkOption {
                type = lib.types.path;
                default = "/var/lib/helix-db";
                description = "Data directory for HelixDB persistence";
              };

              logLevel = lib.mkOption {
                type = lib.types.enum [ "debug" "info" "warn" "error" ];
                default = "info";
                description = "Log level for HelixDB";
              };

              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Open firewall port for HelixDB";
              };
            };

            # ========================================================
            # File Indexer Service Module
            # ========================================================
            options.services.helix-indexer = {
              enable = lib.mkEnableOption "HelixDB automatic file indexing service";

              watchPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "/home" "/etc/nixos" ];
                description = "Paths to monitor for file changes";
              };

              excludePatterns = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  "*.swp" "*.tmp" "*~" ".git/*"
                  "node_modules/*" ".nix-*"
                ];
                description = "File patterns to exclude from indexing";
              };

              mcpServer = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Enable MCP server for AI agent integration";
                };

                port = lib.mkOption {
                  type = lib.types.port;
                  default = 8000;
                  description = "MCP server port";
                };
              };
            };

            # ========================================================
            # Configuration Implementation
            # ========================================================
            config = lib.mkMerge [
              # ====== HelixDB Service ======
              (lib.mkIf helixdbCfg.enable {
                environment.systemPackages = [ self.packages.${system}.helixdb ];

                users.users.helixdb = {
                  description = "HelixDB service user";
                  isSystemUser = true;
                  group = "helixdb";
                  home = helixdbCfg.dataDir;
                };

                users.groups.helixdb = {};

                systemd.services.helixdb = {
                  description = "HelixDB Graph-Vector Database";
                  after = [ "network.target" ];
                  wantedBy = [ "multi-user.target" ];

                  serviceConfig = {
                    Type = "simple";
                    User = "helixdb";
                    Group = "helixdb";

                    ExecStart = ''
                      ${self.packages.${system}.helixdb}/bin/helix-db \
                        --host ${helixdbCfg.host} \
                        --port ${toString helixdbCfg.port} \
                        --data ${helixdbCfg.dataDir} \
                        --log-level ${helixdbCfg.logLevel}
                    '';

                    Restart = "always";
                    RestartSec = "10s";
                    StartLimitIntervalSec = 60;
                    StartLimitBurst = 5;

                    StateDirectory = "helix-db";
                    StateDirectoryMode = "0700";
                    WorkingDirectory = helixdbCfg.dataDir;

                    ProtectSystem = "strict";
                    ProtectHome = true;
                    NoNewPrivileges = true;
                    PrivateTmp = true;
                    ProtectClock = true;
                    ProtectHostname = true;
                    ProtectKernelLogs = true;
                    ProtectKernelTunables = true;
                    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
                    RestrictNamespaces = true;
                    RestrictRealtime = true;
                    LockPersonality = true;

                    LimitNOFILE = 65536;
                    LimitNPROC = 512;
                  };

                  preStart = ''
                    mkdir -p ${helixdbCfg.dataDir}
                    chown helixdb:helixdb ${helixdbCfg.dataDir}
                    chmod 700 ${helixdbCfg.dataDir}
                  '';
                };

                networking.firewall.allowedTCPPorts =
                  lib.optionals helixdbCfg.openFirewall [ helixdbCfg.port ];
              })

              # ====== File Indexer Service ======
              (lib.mkIf cfg.enable {
                environment.systemPackages = [ self.packages.${system}.helix-search ];

                users.users.helix-indexer = {
                  description = "HelixDB File Indexer user";
                  isSystemUser = true;
                  group = "helix-indexer";
                  home = "/var/lib/helix-indexer";
                };

                users.groups.helix-indexer = {};

                boot.kernel.sysctl = {
                  "fs.inotify.max_user_watches" = 524288;
                  "fs.inotify.max_queued_events" = 32768;
                  "fs.inotify.max_user_instances" = 1024;
                };

                systemd.services.helix-indexer = {
                  description = "HelixDB Automatic File Indexer";
                  after = [ "network.target" ] ++ lib.optional helixdbCfg.enable "helixdb.service";
                  wants = lib.optional helixdbCfg.enable "helixdb.service";
                  wantedBy = [ "multi-user.target" ];

                  serviceConfig = {
                    Type = "simple";
                    User = "helix-indexer";
                    Group = "helix-indexer";

                    ExecStart = "${self.packages.${system}.helix-indexer}/bin/helix-file-indexer";

                    Restart = "on-failure";
                    RestartSec = "10s";
                    StartLimitIntervalSec = 60;
                    StartLimitBurst = 3;

                    StateDirectory = "helix-indexer";
                    StateDirectoryMode = "0700";
                    WorkingDirectory = "/var/lib/helix-indexer";

                    ProtectSystem = "strict";
                    ProtectHome = true;
                    NoNewPrivileges = true;
                    PrivateTmp = true;
                    ProtectClock = true;
                    ProtectHostname = true;
                    ProtectKernelLogs = true;
                    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
                    RestrictNamespaces = true;
                    RestrictRealtime = true;
                    LockPersonality = true;

                    LimitNOFILE = 65536;
                  };

                  environment = {
                    HELIX_DB_HOST = helixdbCfg.host;
                    HELIX_DB_PORT = toString helixdbCfg.port;
                    WATCH_PATHS = lib.concatStringsSep ":" cfg.watchPaths;
                    EXCLUDE_PATTERNS = lib.concatStringsSep ":" cfg.excludePatterns;
                    LOG_LEVEL = "INFO";
                  };
                };
              })

              # ====== MCP Server Service ======
              (lib.mkIf (cfg.enable && cfg.mcpServer.enable) {
                systemd.services.helix-mcp-server = {
                  description = "HelixDB MCP Server for AI Agents";
                  after = [ "network.target" ] ++ lib.optional helixdbCfg.enable "helixdb.service";
                  wants = lib.optional helixdbCfg.enable "helixdb.service";
                  wantedBy = [ "multi-user.target" ];

                  serviceConfig = {
                    Type = "simple";
                    User = "helix-indexer";
                    Group = "helix-indexer";

                    ExecStart = "${self.packages.${system}.helix-mcp-server}/bin/helix-mcp-server";

                    Restart = "always";
                    RestartSec = "5s";

                    ProtectSystem = "strict";
                    ProtectHome = true;
                    NoNewPrivileges = true;
                    PrivateTmp = true;
                    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
                  };

                  environment = {
                    HELIX_DB_HOST = helixdbCfg.host;
                    HELIX_DB_PORT = toString helixdbCfg.port;
                    MCP_PORT = toString cfg.mcpServer.port;
                  };
                };
              })

              {
                environment.systemPackages = lib.optionals cfg.enable
                  [ self.packages.${system}.helix-search ];
              }
            ];
          };

      }
    ) // {
      # homeManagerModules.default = self.homeManagerModules.x86_64-linux.default;
      # nixosModules.default = self.nixosModules.x86_64-linux.default;
    };
}

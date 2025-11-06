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
    google-genai-src = {
      url = "github:googleapis/python-genai";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, home-manager, helix-db-src, helix-py-src, google-genai-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        lib = pkgs.lib;

        # ============================================================
        # Build voyageai from PyPI (not available in nixpkgs)
        # Required by helix-py for semantic chunking
        # ============================================================
        voyageai-pkg = pkgs.python3.pkgs.buildPythonPackage {
          pname = "voyageai";
          version = "0.3.5";
          format = "pyproject";
          src = pkgs.fetchPypi {
            pname = "voyageai";
            version = "0.3.5";
            sha256 = "sha256-lj4NcWEa9Sn6DkltsjKk9mC19zvOevGrKIp/Wd91Eto=";
          };

          nativeBuildInputs = with pkgs.python3.pkgs; [
            setuptools
            wheel
            poetry-core
            aiohttp
            aiolimiter
            langchain-text-splitters
            numpy
            pillow
            pydantic
            requests
            tenacity
            tokenizers
          ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
          ];

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Voyage AI provides cutting-edge embedding and rerankers.";
            homepage = "https://pypi.org/project/voyageai/";
            license = licenses.mit;
          };
        };

        # ============================================================
        # Build chonkie from PyPI (not available in nixpkgs)
        # Required by helix-py for semantic chunking
        # ============================================================
        chonkie-pkg = pkgs.python3.pkgs.buildPythonPackage {
          pname = "chonkie";
          version = "1.4.1";
          format = "pyproject";
          src = pkgs.fetchPypi {
            pname = "chonkie";
            version = "1.4.1";
            sha256 = "sha256-u+1+p2cByo9i7xn0NO4DrFb73uM5nwakpPL8mgrhJp0=";
          };

          nativeBuildInputs = with pkgs.python3.pkgs; [
            setuptools
            wheel
            tokenizers
            cython
            numpy
            loguru
          ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
            regex
            tiktoken
            nltk
          ];

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Chonkie - Fast semantic chunking for text";
            homepage = "https://pypi.org/project/chonkie/";
            license = licenses.mit;
          };
        };

        # ============================================================
        # Build google-genai from GitHub using hatchling backend
        # For Gemini embeddings and generative AI features
        # ============================================================
        google-genai-pkg = pkgs.python3.pkgs.buildPythonPackage {
          pname = "google-genai";
          version = "1.13.0";
          format = "pyproject";
          src = google-genai-src;

          nativeBuildInputs = with pkgs.python3.pkgs; [
            hatchling
            hatch-fancy-pypi-readme
            setuptools
            pkginfo
            twine
            tenacity
            websockets
          ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
            httpx
            google-api-core
            google-auth
            pydantic
            typing-extensions
          ];

          doCheck = false;
          dontUsePythonImportsCheck = true;

          meta = with pkgs.lib; {
            description = "Google Gen AI Python SDK - Official replacement for google-generativeai";
            homepage = "https://github.com/googleapis/python-genai";
            license = licenses.asl20;
          };
        };

        # ============================================================
        # Build helix-py properly from source
        # Using hatchling backend as specified in pyproject.toml
        # ============================================================
        helix-py-pkg = pkgs.python3.pkgs.buildPythonPackage {
          pname = "helix-py";
          version = "0.2.30";
          src = helix-py-src;
          pyproject = true;

          nativeBuildInputs = with pkgs.python3.pkgs; [
            hatchling
          ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
            # Core dependencies
            requests
            pydantic
            httpx
            tqdm
            python-dotenv
            # Optional dependencies for enhanced functionality
            numpy
            pyarrow
            chonkie-pkg
            google-genai-pkg
          ];

          dontCheckRuntimeDeps = true;
          doCheck = false;

          meta = with pkgs.lib; {
            description = "HelixDB Python client library";
            homepage = "https://github.com/HelixDB/helix-py";
            license = licenses.asl20;
          };
        };

        # ============================================================
        # Python environment with helix-py and all dependencies
        # ============================================================
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          helix-py-pkg
          pyinotify
          requests
          pyyaml
          watchdog
          tqdm
          python-dotenv
          numpy
          pyarrow
          chonkie-pkg
          loguru
          markitdown
          tokenizers
          fastmcp
          google-genai-pkg
          google-api-core
          google-auth
          tenacity
          voyageai-pkg
          langchain-text-splitters
          aiohttp
          aiolimiter
          langchain-text-splitters
          numpy
          pillow
          pydantic
          requests
          tenacity
          tokenizers
        ]);

        # ============================================================
        # Helix Indexer Package - bundles src/helix_indexer.py
        # ============================================================
        helix-indexer-pkg = pkgs.runCommand "helix-indexer" {} ''
          mkdir -p $out/bin
          cat > $out/bin/helix-file-indexer << 'EOF'
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_indexer.py}
          EOF
          chmod +x $out/bin/helix-file-indexer
        '';

        # ============================================================
        # Helix MCP Server Package - bundles src/helix_mcp_server.py
        # ============================================================
        helix-mcp-server-pkg = pkgs.runCommand "helix-mcp-server" {} ''
          mkdir -p $out/bin
          cat > $out/bin/helix-mcp-server << 'EOF'
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_mcp_server.py}
          EOF
          chmod +x $out/bin/helix-mcp-server
        '';

        # ============================================================
        # Helix Search Tool Package - bundles src/helix_search.py
        # ============================================================
        helix-search-tool-pkg = pkgs.runCommand "helix-search-tool" {} ''
          mkdir -p $out/bin
          cat > $out/bin/helix-search << 'EOF'
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_search.py}
          EOF
          chmod +x $out/bin/helix-search
          '';

        # Base queries file within the repo
        baseQueries = ./queries.hx;

        # Optional extra queries file from NixOS config
        extraQueriesFile = let
          file = self.nixosModules.${system}.default.config.services.helixdb.extraQueriesFile;
        in
          if file == null then null
          else if lib.pathExists file then file else null;

        combinedQueries = pkgs.runCommand "combined-queries.hx" {
          buildInputs = [ pkgs.coreutils ];
        } ''
          if [ -f ${baseQueries} ]; then
            cat ${baseQueries} > $out
          else
            touch $out
          fi
          if [ -n "${extraQueriesFile}" ] && [ -f "${extraQueriesFile}" ]; then
            cat "${extraQueriesFile}" >> $out
          fi
        '';

        # ============================================================
        # Real HelixDB Rust Package from source
        # Build helix-container which is the actual database server
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

          doCheck = false;

          cargoBuildFlags = [ "--bin" "helix-container" "-p" "helix-container" ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin

            TARGET_DIR="target/x86_64-unknown-linux-gnu/release"
            if [ ! -d "$TARGET_DIR" ]; then
              TARGET_DIR="target/release"
            fi

            BIN_PATH="$TARGET_DIR/helix-container"

            if [ -f "$BIN_PATH" ]; then
              echo "Installing helix-container binary from $BIN_PATH..."
              cp "$BIN_PATH" "$out/bin/helix-db"
              chmod +x "$out/bin/helix-db"
              echo "✓ Binary installed successfully"
            else
              echo "ERROR: helix-container binary not found at $BIN_PATH"
              exit 1
              fi

            # Copy combined queries as static file in package
            mkdir -p $out/etc/helix-db
            cp ${combinedQueries} $out/etc/helix-db/queries.hx

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "HelixDB - Open-source Graph-Vector Database";
            homepage = "https://github.com/HelixDB/helix-db";
            license = licenses.asl20;
            platforms = platforms.unix;
          };
        };

      in {
        # ============================================================
        # Packages
        # ============================================================
        packages = {
          helixdb = helixdb;
          helix-py = helix-py-pkg;
          chonkie = chonkie-pkg;
          voyageai = voyageai-pkg;
          google-genai = google-genai-pkg;
          python-env = pythonEnv;
          helix-indexer = helix-indexer-pkg;
          helix-mcp-server = helix-mcp-server-pkg;
          helix-search = helix-search-tool-pkg;
          default = helixdb;
        };

        # ============================================================
        # Development Shell
        # ============================================================
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pythonEnv
            pkgs.rust-bin.stable.latest.default
            cargo
            pkg-config
            openssl
            helix-mcp-server-pkg
            helix-indexer-pkg
            helix-search-tool-pkg
            ffmpeg
          ];

          shellHook = ''
            export RUST_LOG=info
            export RUSTUP_TOOLCHAIN=stable
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
              home.packages = [ self.packages.${system}.helix-search pkgs.ffmpeg ];
              programs.bash.shellAliases = cfg.aliases;
              programs.zsh.shellAliases = cfg.aliases;
              programs.fish.shellAliases = cfg.aliases;
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

              extraQueriesFile = lib.mkOption {
                type = lib.types.nullOrFile;
                default = null;
                description = "Optional extra HelixQL queries file to merge at build time";
              };
            };

            options.services.helix-indexer = {
              enable = lib.mkEnableOption "HelixDB automatic file indexing service";

              watchPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "/home" "/etc/nixos" ];
                description = "Paths to monitor for file changes";
              };

              excludePatterns = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "*.swp" "*.tmp" "*~" ".git/*" "node_modules/*" ".nix-*" ];
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

            config = lib.mkMerge [
              (lib.mkIf helixdbCfg.enable {
                environment.systemPackages = [ self.packages.${system}.helixdb ];

                users.users.helixdb = {
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
                        --log-level ${helixdbCfg.logLevel} \
                        --queries ${self.packages.${system}.helixdb}/etc/helix-db/queries.hx
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

              (lib.mkIf cfg.enable {
                environment.systemPackages = [
                  self.packages.${system}.helix-indexer
                  self.packages.${system}.helix-search
                ];

                users.users.helix-indexer = {
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

                    # Critical: Set PYTHONPATH so Python can find all packages
                    Environment = [
                      "PYTHONPATH=${pkgs.lib.makeBinPath [ self.packages.${system}.python-env ]}"
                      "PATH=${self.packages.${system}.python-env}/bin:${pkgs.lib.makeBinPath [ pkgs.coreutils ]}"
                    ];

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

              (lib.mkIf (cfg.enable && cfg.mcpServer.enable) {
                environment.systemPackages = [ self.packages.${system}.helix-mcp-server ];

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

                    StateDirectory = "helix-indexer";
                    StateDirectoryMode = "0700";
                    WorkingDirectory = "/var/lib/helix-indexer";

                    # Critical: Set PYTHONPATH so Python can find all packages
                    Environment = [
                      "PYTHONPATH=${pkgs.lib.makeBinPath [ self.packages.${system}.python-env ]}"
                      "PATH=${self.packages.${system}.python-env}/bin:${pkgs.lib.makeBinPath [ pkgs.coreutils ]}"
                    ];

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
            ];
          };

      }
    );
}

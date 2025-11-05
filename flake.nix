{
  description = "HelixDB Auto-Indexing System with Semantic Search";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, home-manager }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Python environment with dependencies
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pyinotify
          requests
          pyyaml
          watchdog
        ]);

        # HelixDB indexer service script
        helixIndexerScript = pkgs.writeScriptBin "helix-file-indexer" ''
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_indexer.py}
        '';

        # CLI search tool
        helixSearchTool = pkgs.writeScriptBin "helix-search" ''
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_search.py}
        '';

        # MCP server script
        helixMcpServer = pkgs.writeScriptBin "helix-mcp-server" ''
          #!${pythonEnv}/bin/python3
          ${builtins.readFile ./src/helix_mcp_server.py}
        '';

      in {
        # Packages
        packages = {
          helix-indexer = helixIndexerScript;
          helix-search = helixSearchTool;
          helix-mcp-server = helixMcpServer;
          default = helixSearchTool;
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pythonEnv
            helixIndexerScript
            helixSearchTool
            helixMcpServer
          ];
        };

        # Home-Manager module
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

              # User configuration file
              xdg.configFile."helix-search/config.yaml".text = ''
                search_paths: ${builtins.toJSON cfg.searchPaths}
                helix_db:
                  host: "localhost"
                  port: 6969
                cli:
                  default_limit: 10
                  highlight_results: true
              '';
            };
          };

        # NixOS module
        nixosModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.services.helix-indexer;
          in {
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
              
              helixDb = {
                host = lib.mkOption {
                  type = lib.types.str;
                  default = "localhost";
                  description = "HelixDB host";
                };
                
                port = lib.mkOption {
                  type = lib.types.port;
                  default = 6969;
                  description = "HelixDB port";
                };
                
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Enable built-in HelixDB service";
                };
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

            config = lib.mkIf cfg.enable {
              # Increase inotify limits
              boot.kernel.sysctl = {
                "fs.inotify.max_user_watches" = 524288;
                "fs.inotify.max_queued_events" = 32768;
                "fs.inotify.max_user_instances" = 1024;
              };

              # HelixDB service (placeholder - would need actual HelixDB package)
              systemd.services.helix-db = lib.mkIf cfg.helixDb.enable {
                description = "HelixDB Graph-Vector Database";
                after = [ "network.target" ];
                wantedBy = [ "multi-user.target" ];
                
                serviceConfig = {
                  # Note: This would need the actual HelixDB binary
                  ExecStart = "${pkgs.helix-db or pkgs.writeScriptBin "helix-db-stub" "echo 'HelixDB stub - install actual package'"}/bin/helix-db --host ${cfg.helixDb.host} --port ${toString cfg.helixDb.port}";
                  Restart = "always";
                  RestartSec = "10s";
                  
                  # Security
                  DynamicUser = true;
                  StateDirectory = "helix-db";
                  PrivateTmp = true;
                  NoNewPrivileges = true;
                };
              };

              # File indexing service
              systemd.services.helix-indexer = {
                description = "HelixDB Automatic File Indexer";
                after = [ "network.target" ] ++ lib.optional cfg.helixDb.enable "helix-db.service";
                wants = lib.optional cfg.helixDb.enable "helix-db.service";
                wantedBy = [ "multi-user.target" ];
                
                serviceConfig = {
                  ExecStart = "${self.packages.${system}.helix-indexer}/bin/helix-file-indexer";
                  Restart = "on-failure";
                  RestartSec = "10s";
                  
                  # Security hardening
                  DynamicUser = true;
                  StateDirectory = "helix-indexer";
                  ReadOnlyPaths = [ "/" ];
                  ReadWritePaths = [ "/var/lib/helix-indexer" ];
                  PrivateTmp = true;
                  NoNewPrivileges = true;
                };
                
                environment = {
                  HELIX_DB_HOST = cfg.helixDb.host;
                  HELIX_DB_PORT = toString cfg.helixDb.port;
                  WATCH_PATHS = builtins.concatStringsSep ":" cfg.watchPaths;
                  EXCLUDE_PATTERNS = builtins.concatStringsSep ":" cfg.excludePatterns;
                };
              };

              # MCP server service
              systemd.services.helix-mcp-server = lib.mkIf cfg.mcpServer.enable {
                description = "HelixDB MCP Server for AI Agents";
                after = [ "helix-db.service" ];
                wants = [ "helix-db.service" ];
                wantedBy = [ "multi-user.target" ];
                
                serviceConfig = {
                  ExecStart = "${self.packages.${system}.helix-mcp-server}/bin/helix-mcp-server";
                  Restart = "always";
                  DynamicUser = true;
                  StateDirectory = "helix-mcp";
                };
                
                environment = {
                  HELIX_DB_HOST = cfg.helixDb.host;
                  HELIX_DB_PORT = toString cfg.helixDb.port;
                  MCP_PORT = toString cfg.mcpServer.port;
                  # OPENAI_API_KEY would be set via systemd credentials/secrets
                };
              };

              # Make CLI tool available system-wide
              environment.systemPackages = [ self.packages.${system}.helix-search ];
            };
          };
      }
    ) // {
      # Multi-system outputs
      homeManagerModules.default = self.homeManagerModules.x86_64-linux.default;
      nixosModules.default = self.nixosModules.x86_64-linux.default;
    };
}
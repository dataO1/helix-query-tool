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
      url = "github:HelixDB/helix-db/v2.1.0";
      flake = false;
    };
    helix-py-src = {
      url = "github:HelixDB/helix-py/v0.2.30";
      flake = false;
    };
    google-genai-src = {
      url = "github:googleapis/python-genai/v1.49.0";
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
        # Build chonkie from PyPI
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
            setuptools wheel tokenizers cython numpy loguru
          ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
            regex tiktoken nltk
          ];

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Chonkie - Fast semantic chunking for text";
            homepage = "https://pypi.org/project/chonkie/";
            license = licenses.mit;
          };
        };

        # ============================================================
        # Build google-genai from GitHub
        # ============================================================
        google-genai-pkg = pkgs.python3.pkgs.buildPythonPackage {
          pname = "google-genai";
          version = "1.13.0";
          format = "pyproject";
          src = google-genai-src;

          nativeBuildInputs = with pkgs.python3.pkgs; [
            hatchling hatch-fancy-pypi-readme setuptools pkginfo tenacity
            websockets twine
          ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
            httpx google-api-core google-auth pydantic typing-extensions setuptools
          ];

          doCheck = false;
          dontUsePythonImportsCheck = true;

          meta = with pkgs.lib; {
            description = "Google Gen AI Python SDK";
            homepage = "https://github.com/googleapis/python-genai";
            license = licenses.asl20;
          };
        };

        # ============================================================
        # Build helix-py from source
        # ============================================================
        helix-py-pkg = pkgs.python3.pkgs.buildPythonPackage {
          pname = "helix-py";
          version = "0.2.30";
          src = helix-py-src;
          pyproject = true;

          nativeBuildInputs = with pkgs.python3.pkgs; [ hatchling setuptools ];

          propagatedBuildInputs = with pkgs.python3.pkgs; [
            requests pydantic httpx tqdm python-dotenv numpy pyarrow
            chonkie-pkg google-genai-pkg setuptools
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
        # Python environment for tools
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
          ollama
        ]);

        helix-indexer-pkg = pkgs.writeShellScriptBin "helix-file-indexer" ''
          export PYTHONPATH="${pythonEnv}/${pythonEnv.python.sitePackages}:$PYTHONPATH"
          exec ${pythonEnv}/bin/python3 ${./src/helix_indexer.py} "$@"
        '';

        helix-search-tool-pkg = pkgs.writeShellScriptBin "helix-search" ''
          export PYTHONPATH="${pythonEnv}/${pythonEnv.python.sitePackages}:$PYTHONPATH"
          exec ${pythonEnv}/bin/python3 ${./src/helix_search.py} "$@"
        '';

        helix-mcp-server-pkg = pkgs.writeShellScriptBin "helix-mcp-server" ''
          export PYTHONPATH="${pythonEnv}/${pythonEnv.python.sitePackages}:$PYTHONPATH"
          exec ${pythonEnv}/bin/python3 ${./src/helix_mcp_server.py} "$@"
        '';

        # ============================================================
        # Build Helix CLI from source
        # ============================================================
        helix-cli = pkgs.rustPlatform.buildRustPackage rec {
          pname = "helix-cli";
          version = "2.0.5";

          src = helix-db-src;

          cargoLock = {
            lockFile = "${helix-db-src}/Cargo.lock";
          };

          nativeBuildInputs = with pkgs; [ pkg-config git ];
          buildInputs = with pkgs; [ openssl git ];

          doCheck = false;

          # Build the helix CLI binary (not helix-container)
          cargoBuildFlags = [ "--bin" "helix" "-p" "helix-cli" ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin

            TARGET_DIR="target/x86_64-unknown-linux-gnu/release"
            if [ ! -d "$TARGET_DIR" ]; then
              TARGET_DIR="target/release"
            fi

            BIN_PATH="$TARGET_DIR/helix"

            if [ -f "$BIN_PATH" ]; then
              echo "Installing helix CLI binary..."
              cp "$BIN_PATH" "$out/bin/helix"
              chmod +x "$out/bin/helix"
              echo "✓ Helix CLI installed successfully"
            else
              echo "ERROR: helix CLI binary not found at $BIN_PATH"
              exit 1
            fi

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "HelixDB CLI tool for project management";
            homepage = "https://github.com/HelixDB/helix-db";
            license = licenses.asl20;
            platforms = platforms.unix;
          };
        };

        # ============================================================
        # HelixDB Runtime Binary (helix-container)
        # ============================================================
        helixdb-runtime = pkgs.rustPlatform.buildRustPackage rec {
          pname = "helix-db-runtime";
          version = "2.0.5";

          src = helix-db-src;

          cargoLock = {
            lockFile = "${helix-db-src}/Cargo.lock";
          };

          nativeBuildInputs = with pkgs; [ pkg-config git ];
          buildInputs = with pkgs; [ openssl  git];

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
              cp "$BIN_PATH" "$out/bin/helix-container"
              chmod +x "$out/bin/helix-container"
              echo "✓ HelixDB runtime installed"
            else  export PYTHONPATH="${pythonEnv}/${pythonEnv.python.sitePackages}:$PYTHONPATH"
              echo "ERROR: helix-container not found"
              exit 1
            fi

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "HelixDB runtime container";
            homepage = "https://github.com/HelixDB/helix-db";
            license = licenses.asl20;
            platforms = platforms.unix;
          };
        };

        # # ============================================================
        # # Initialize HelixDB Data Directory
        # # Run helix build to prepare the instance
        # # ============================================================
        # helixdb-initialized = pkgs.runCommand "helixdb-initialized" {
        #   buildInputs = [ helix-cli pkgs.docker pkgs.coreutils ];
        #   preferLocalBuild = true;
        #   allowSubstitutes = false;
        # } ''
        #   mkdir -p $out/data
        #   cd ${helixdb-project}/project
        #
        #   echo "Building HelixDB instance..."
        #   ${helix-cli}/bin/helix build prod --output-dir $out/data
        #
        #   echo "✓ HelixDB instance built at $out/data"
        # '';

      in {
        # ============================================================
        # Packages
        # ============================================================
        packages = {
          helix-cli = helix-cli;
          helixdb-runtime = helixdb-runtime;
          # helixdb-project = helixdb-project;
          helix-py = helix-py-pkg;
          chonkie = chonkie-pkg;
          google-genai = google-genai-pkg;
          python-env = pythonEnv;
          helix-indexer = helix-indexer-pkg;
          helix-mcp-server = helix-mcp-server-pkg;
          helix-search = helix-search-tool-pkg;
          default = helix-cli;
        };

        # ============================================================
        # Development Shell
        # ============================================================
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pythonEnv rust-bin.stable.latest.default cargo pkg-config openssl
            helix-cli docker helix-mcp-server-pkg helix-indexer-pkg helix-search-tool-pkg
          ];

          shellHook = ''
            export RUST_LOG=info
            export RUSTUP_TOOLCHAIN=stable
          '';
        };

        # ============================================================
        # NixOS Module
        # ============================================================
        nixosModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.services.helixdb;
            indexerCfg = config.services.helix-indexer;

          in {
            options.services.helixdb = {
              enable = lib.mkEnableOption "HelixDB with CLI management";

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

              openFirewall = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Open firewall port for HelixDB";
              };

              gpuAcceleration = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Open firewall port for HelixDB";
              };
            };

            options.services.helix-indexer = {
              enable = lib.mkEnableOption "HelixDB file indexer service";

              watchPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "/home" "/etc/nixos" ];
                description = "Paths to monitor";
              };

              excludePatterns = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "*.swp" "*.tmp" "*~" ".git/*" "node_modules/*" ];
                description = "Patterns to exclude";
              };
            };

            config = lib.mkMerge [
              (lib.mkIf cfg.enable {
                environment.systemPackages = [
                  self.packages.${system}.helix-cli
                  self.packages.${system}.helixdb-runtime
                ];

                # users.users.helixdb = {
                #   isSystemUser = true;
                #   group = "helixdb";
                #   home = cfg.dataDir;
                # };
                # users.groups.helixdb = {};

                services.ollama = {
                  enable = true;
                  acceleration = cfg.gpuAcceleration;
                };

                  # host = cfg.ollamaHost;
                  # port = cfg.ollamaPort;
                  # loadModels = lib.attrValues cfg.models;

                systemd.services.helixdb = {
                  description = "HelixDB via CLI (prod instance)";
                  after = [ "network.target" ];
                  wantedBy = [ "multi-user.target" ];

                  script = ''
                    # Disable telemetry to avoid permission issues in sandbox
                    export HELIX_TELEMETRY=off
                    export HELIX_METRICS=off

                    cd ${cfg.dataDir}

                    # Create helix.toml configuration
                    # Initiating project
                    echo "Initiating HelixDB project..."
                    ${self.packages.${system}.helix-cli}/bin/helix init local --name prod > /dev/null 2>&1 || true

                    cat > helix.toml << 'TOML'
                    ${builtins.readFile ./helix.toml}
                    TOML
                    # chown helixdb:helixdb helix.toml

                    # Create schema.hx (minimal schema for flexible indexing)
                    cat > db/schema.hx << 'HX'
                    ${builtins.readFile ./schema.hx}
                    HX

                    # Create combined queries file
                    cat > db/queries.hx << 'HX'
                    ${builtins.readFile ./queries.hx}

                    ${lib.optionalString (builtins.pathExists ./extra-queries.hx) ''
                      ${builtins.readFile ./extra-queries.hx}
                    ''}
                    HX

                    # chown -R helixdb:helixdb db

                    # # Validate project
                    echo "Building and deploying HelixDB project..."
                    ${self.packages.${system}.helix-cli}/bin/helix check prod && \
                    # Building project
                    ${self.packages.${system}.helix-cli}/bin/helix build prod && \
                    # Pushing project
                    ${self.packages.${system}.helix-cli}/bin/helix push prod && \
                    # Starting project
                    ${self.packages.${system}.helix-cli}/bin/helix start prod && \
                    echo "✓ HelixDB project initialized at $out/project"
                  '';

                  serviceConfig = {
                    Type = "simple";
                    # User = "helixdb";
                    # Group = "helixdb";

                    # ExecStart = ''
                    # '';

                    Restart = "always";
                    RestartSec = "10s";
                    StartLimitInterval = 60;
                    StartLimitBurst = 5;

                    StateDirectory = "helix-db";
                    StateDirectoryMode = "0700";
                    WorkingDirectory = cfg.dataDir;
                    PermissionsStartOnly = true; # Allows the initial start command to run as root if needed
                    # ProtectSystem = "strict";
                    # ProtectHome = true;
                    # NoNewPrivileges = true;
                    LimitNOFILE = 65536;
                  };

                  preStart = ''
                    mkdir -p ${cfg.dataDir}
                    # chown helixdb:helixdb ${cfg.dataDir}
                    chmod 700 ${cfg.dataDir}
                  '';
                };

                networking.firewall.allowedTCPPorts =
                  lib.optionals cfg.openFirewall [ cfg.port ];
              })

              (lib.mkIf indexerCfg.enable {
                environment.systemPackages = [ self.packages.${system}.helix-indexer ];

                # users.users.helix-indexer = {
                #   isSystemUser = true;
                #   group = "helix-indexer";
                #   home = "/var/lib/helix-indexer";
                # };
                # users.groups.helix-indexer = {};

                systemd.services.helix-indexer = {
                  description = "HelixDB File Indexer";
                  after = [ "network.target" ] ++ lib.optional cfg.enable "helixdb.service";
                  wants = lib.optional cfg.enable "helixdb.service";
                  wantedBy = [ "multi-user.target" ];

                  serviceConfig = {
                    Type = "simple";
                    # User = "helix-indexer";
                    # Group = "helix-indexer";

                    ExecStart = "${self.packages.${system}.helix-indexer}/bin/helix-file-indexer";

                    Restart = "on-failure";
                    RestartSec = "10s";

                    StateDirectory = "helix-indexer";
                    StateDirectoryMode = "0700";
                    WorkingDirectory = "/var/lib/helix-indexer";

                    LimitNOFILE = 65536;
                  };

                  environment = {
                    HELIX_DB_HOST = cfg.host;
                    HELIX_DB_PORT = toString cfg.port;
                    WATCH_PATHS = lib.concatStringsSep ":" indexerCfg.watchPaths;
                    EXCLUDE_PATTERNS = lib.concatStringsSep ":" indexerCfg.excludePatterns;
                  };
                };
              })
            ];
          };
      }
    );
}

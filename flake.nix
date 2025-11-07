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
            hatchling hatch-fancy-pypi-readme setuptools pkginfo tenacity websockets twine
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
        # Build HelixDB Container Runtime Binary
        # ============================================================
        helixdb-runtime = pkgs.rustPlatform.buildRustPackage rec {
          pname = "helix-container";
          version = "2.1.0";

          src = helix-db-src;

          cargoLock = {
            lockFile = "${helix-db-src}/Cargo.lock";
          };

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ openssl ];

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
              echo "✓ HelixDB container runtime installed"
            else
              echo "ERROR: helix-container binary not found at $BIN_PATH"
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

        # ============================================================
        # Minimal Dockerfile using pre-built binary
        # Bakes in helix config files for reproducibility
        # ============================================================
        helixdb-dockerfile = pkgs.writeTextFile {
          name = "Dockerfile";
          text = ''
            FROM debian:bookworm-slim

            WORKDIR /app

            # Install runtime dependencies only
            RUN apt-get update && apt-get install -y --no-install-recommends \
                ca-certificates \
                && rm -rf /var/lib/apt/lists/*

            # Copy pre-built helix-container binary from Nix store
            COPY ${helixdb-runtime}/bin/helix-container /usr/local/bin/helix-container
            RUN chmod +x /usr/local/bin/helix-container

            # Copy helix configuration files (baked into image for reproducibility)
            # COPY ${./helix.toml} /app/helix.toml
            # COPY ${./schema.hx} /app/schema.hx
            # COPY ${./queries.hx} /app/queries.hx

            # # Create data directory for persistence
            # RUN mkdir -p data

            EXPOSE 6969

            CMD ["helix-container"]
          '';
        };

        # Create entrypoint script for HelixDB initialization
        helixdb-entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
          #!/usr/bin/env sh
          echo "Starting HelixDB..."
          echo "HELIX_DATA_DIR: $HELIX_DATA_DIR"
          # mkdir -p "$HELIX_DATA_DIR/user"
          # Create application directory structure
          mkdir -p /app/db
          # mkdir -p app/data/user  # HelixDB needs this

          # Copy configs to /app
          cp ${./helix.toml} /app/helix.toml
          cp ${./schema.hx} /app/db/schema.hx
          cp ${./queries.hx} /app/db/queries.hx

          # Copy binary
          mkdir -p usr/local/bin
          cp ${helixdb-runtime}/bin/helix-container usr/local/bin/helix-container
          chmod +x usr/local/bin/helix-container
          exec usr/local/bin/helix-container
        '';

        helixdb-docker-image = pkgs.dockerTools.buildLayeredImage {
          name = "helix-dev";
          tag = "latest";

          contents = [
            pkgs.coreutils
            pkgs.curl
            helixdb-runtime
          ];

          config = {
            Entrypoint = [ "${helixdb-entrypoint}" ];
            Env = [
              "HELIX_DATA_DIR=/app"  # Changed from /data to /app
              "HELIX_PORT=6969"
              "HELIX_TELEMETRY=off"
            ];
            # WorkingDir = "/app";
            Volumes = {
              "/app" = {};
            };
            ExposedPorts = {
              "6969/tcp" = {};
            };
          };

        #   extraCommands = ''
        #     # Create application directory structure
        #     # mkdir -p app/db
        #     # mkdir -p app/data/user  # HelixDB needs this
        #
        #     # Copy configs to /app
        #     cp ${./helix.toml} app/helix.toml
        #     cp ${./schema.hx} app/db/schema.hx
        #     cp ${./queries.hx} app/db/queries.hx
        #
        #     # Copy binary
        #     mkdir -p usr/local/bin
        #     cp ${helixdb-runtime}/bin/helix-container usr/local/bin/helix-container
        #     chmod +x usr/local/bin/helix-container
        #   '';
        };

      in {
        # ============================================================
        # Packages
        # ============================================================
        packages = {
          helixdb-runtime = helixdb-runtime;
          helixdb-docker-image = helixdb-docker-image;
          helix-py = helix-py-pkg;
          chonkie = chonkie-pkg;
          google-genai = google-genai-pkg;
          python-env = pythonEnv;
          helix-indexer = helix-indexer-pkg;
          helix-mcp-server = helix-mcp-server-pkg;
          helix-search = helix-search-tool-pkg;
          default = helixdb-runtime;
        };

        # ============================================================
        # Development Shell
        # ============================================================
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            pythonEnv rust-bin.stable.latest.default cargo pkg-config openssl
            docker helix-mcp-server-pkg helix-indexer-pkg helix-search-tool-pkg
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
              enable = lib.mkEnableOption "HelixDB with pre-built binary";

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
            };

            options.services.helix-indexer = {
              enable = lib.mkEnableOption "HelixDB file indexer service";

              watchPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "/home" "/etc/nixos" ];
                description = "Paths to monitor for indexing";
              };

              excludePatterns = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ "*.swp" "*.tmp" "*~" ".git/*" "node_modules/*" ];
                description = "Patterns to exclude from indexing";
              };
            };

            config = lib.mkMerge [
              (lib.mkIf cfg.enable {
                # Enable Docker/Podman
                virtualisation.docker.enable = true;
                environment.systemPackages = with pkgs; [ffmpeg];

                # Declaratively run the container
                virtualisation.oci-containers = {
                  backend = "docker";
                  containers.helixdb = {
                    autoStart = true;

                    image = "helix-dev:latest";
                    imageFile = self.packages.${system}.helixdb-docker-image;

                    ports = [ "${cfg.host}:${toString cfg.port}:6969" ];

                    volumes = [
                      "${cfg.dataDir}/data:/app"
                    ];

                    environment = {
                      HELIX_DATA_DIR = "/app";
                      HELIX_PORT = "6969";
                    };
                    autoRemoveOnStop = false;

                    # Restart policy
                    extraOptions = [
                      "--restart=unless-stopped"
                    ];
                  };
                };
                # Create and initialize data directory
                # Initialize data directory with proper permissions
                system.activationScripts.helixdb-init = lib.stringAfter [ "users" ] ''
                  mkdir -p ${cfg.dataDir}

                  # Make it writable by docker container
                  # Option A: If using user namespacing (recommended)
                  chmod 777 ${cfg.dataDir}

                  # Option B: If running with explicit uid (less common)
                  # chown 0:0 ${cfg.dataDir}
                  # chmod 755 ${cfg.dataDir}
                '';

                networking.firewall.allowedTCPPorts =
                  lib.optionals cfg.openFirewall [ cfg.port ];
              })

              (lib.mkIf indexerCfg.enable {
                environment.systemPackages = [ self.packages.${system}.helix-indexer ];

                systemd.services.helix-indexer = {
                  description = "HelixDB File Indexer";
                  after = [ "network.target" ] ++ lib.optional cfg.enable "helixdb.service";
                  wants = lib.optional cfg.enable "helixdb.service";
                  wantedBy = [ "multi-user.target" ];

                  serviceConfig = {
                    Type = "simple";
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

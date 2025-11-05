# Example NixOS Configuration
{ config, lib, pkgs, helix-indexer, ... }:

{
  imports = [
    # Include the HelixDB indexer module
    helix-indexer.nixosModules.default
  ];

  # Enable HelixDB automatic file indexing
  services.helix-indexer = {
    enable = true;
    
    # Paths to monitor for changes
    watchPaths = [ 
      "/home"           # All user files
      "/etc/nixos"      # System configuration
      "/var/lib/myapp"  # Application data
    ];
    
    # File patterns to ignore
    excludePatterns = [ 
      "*.swp" "*.tmp" "*~"        # Editor temporary files
      ".git/*" ".svn/*"           # Version control
      "node_modules/*"            # Dependencies
      "target/*" "build/*"        # Build artifacts
      ".nix-*"                    # Nix temporary files
    ];
    
    # HelixDB configuration
    helixDb = {
      host = "localhost";
      port = 6969;
      enable = true;  # Auto-start HelixDB service
    };
    
    # Enable MCP server for AI agent integration
    mcpServer = {
      enable = true;
      port = 8000;
    };
  };

  # Make search tool available system-wide
  environment.systemPackages = with pkgs; [
    helix-indexer.packages.${system}.helix-search
  ];

  # Optional: Custom shell aliases for all users
  environment.shellAliases = {
    "search" = "helix-search";
    "find-code" = "helix-search --code-only";
    "find-config" = "helix-search --filetype yaml --filetype toml --filetype nix";
  };

  # Ensure sufficient inotify watchers (automatically configured by the module)
  # boot.kernel.sysctl."fs.inotify.max_user_watches" = 524288;  # Done automatically

  # Optional: Backup HelixDB data
  services.restic.backups.helix-db = {
    paths = [ "/var/lib/helix-db" ];
    repository = "/backup/helix-db";
    passwordFile = "/etc/nixos/secrets/restic-password";
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Optional: Nginx proxy for MCP server (if exposing externally)
  services.nginx = {
    enable = true;
    virtualHosts."search.example.com" = {
      locations."/mcp/" = {
        proxyPass = "http://localhost:8000/";
        proxyWebsockets = true;
      };
    };
  };
}
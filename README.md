HelixDB Flake - Quick Start
Installation

Add to your NixOS configuration:

text
{
  services.helixdb.enable = true;
  services.helix-indexer.enable = true;  # optional
}

Rebuild and activate:

bash
sudo nixos-rebuild switch --flake .

That's it! Everything starts automatically.
Most Important Commands
Check Service Status

bash
systemctl status systemd-docker-helixdb
journalctl -u systemd-docker-helixdb -f

Control Service

bash
systemctl restart systemd-docker-helixdb
systemctl stop systemd-docker-helixdb
systemctl start systemd-docker-helixdb

Query HelixDB

bash
curl http://127.0.0.1:6969/health
helix-search "your search query"

Access Data

bash
ls -la /var/lib/helix-db/data

Configuration Changes

Edit schema.hx, queries.hx, or helix.toml:

bash
vim ./schema.hx
vim ./queries.hx
vim ./helix.toml

Rebuild and restart:

bash
sudo nixos-rebuild switch --flake .

Options

text
services.helixdb = {
  host = "127.0.0.1";      # Bind address
  port = 6969;              # Port
  dataDir = "/var/lib/helix-db";
  openFirewall = false;     # Allow external access
};

Troubleshooting

View full logs:

bash
nix log $(nix build --print-out-paths .#helixdb-docker-image 2>/dev/null)

Data persists at: /var/lib/helix-db/data

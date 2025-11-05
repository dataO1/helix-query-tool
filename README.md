# HelixDB Auto-Indexing System

A complete NixOS flake for automatic file indexing and semantic search using HelixDB with Tree-sitter integration.

## Directory Structure

```
helix-indexing-system/
├── flake.nix                 # Main flake with modules and packages
├── src/
│   ├── helix_indexer.py      # File monitoring and indexing service
│   ├── helix_search.py       # CLI search tool
│   └── helix_mcp_server.py   # MCP server for AI agents
├── README.md                 # This file
└── examples/
    ├── configuration.nix     # NixOS system config example  
    └── home.nix             # Home-manager config example
```

## Features

### 🔍 **Automatic File Indexing**
- Real-time file monitoring with inotify
- Semantic chunking using Tree-sitter patterns
- Language-aware code parsing (Nix, Python, Rust, etc.)
- Batch processing for efficiency
- Configurable watch paths and exclusion patterns

### 🎯 **Intelligent Search**  
- Vector similarity search for semantic queries
- Exact line number and chunk location results
- File type and directory filtering
- CLI tool with colored output and aliases

### 🤖 **AI Agent Integration**
- Built-in MCP (Model Context Protocol) server
- Tools for vector search, keyword search, and file retrieval
- Compatible with Claude Desktop, Cursor, Cline, etc.

## Quick Start

### 1. Add to your NixOS flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    helix-indexer.url = "github:yourusername/helix-indexing-system";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, helix-indexer, home-manager, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      modules = [
        helix-indexer.nixosModules.default
        home-manager.nixosModules.home-manager
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Enable in configuration.nix

```nix
{
  # Enable HelixDB indexing service
  services.helix-indexer = {
    enable = true;
    watchPaths = [ "/home" "/etc/nixos" "/var/lib/myapp" ];
    excludePatterns = [ "*.swp" "*.tmp" ".git/*" "node_modules/*" ];
    
    # Enable MCP server for AI agents
    mcpServer.enable = true;
  };
  
  # Increase inotify limits (automatically configured)
  # boot.kernel.sysctl."fs.inotify.max_user_watches" = 524288;
}
```

### 3. Enable home-manager integration

```nix
{
  services.helix-search = {
    enable = true;
    searchPaths = [ "$HOME/Documents" "$HOME/Projects" ];
    aliases = {
      "hs" = "helix-search";
      "hsf" = "helix-search --files";
      "hsc" = "helix-search --code-only";
    };
  };
}
```

### 4. Rebuild and search

```bash
# Rebuild system
sudo nixos-rebuild switch

# Search your files
helix-search "chromadb service configuration"
helix-search "function definition" --filetype py
helix-search --files "flake.nix"
helix-search --list
helix-search --stats
```

## Usage Examples

### CLI Search Commands

```bash
# Semantic search
helix-search "where is my chromadb configured"

# Code-specific search  
helix-search "error handling" --filetype py --directory /home/user/projects

# File name search
helix-search --files "config.yaml"

# List indexed files
helix-search --list

# Show statistics
helix-search --stats
```

### Expected Output

```
🔍 Searching for: 'chromadb service configuration'

🎯 Found 2 result(s):

1. /etc/nixos/flake.nix (lines 42-44)
   📁 Type: nix  📊 Score: 0.942
   │ chromadb.enabled = true;
   │   chromadb.dataDir = "/var/lib/chromadb";

2. /home/user/.config/chromadb/config.yaml (lines 1-10)  
   📁 Type: yaml  📊 Score: 0.887
   │ service:
   │   name: chromadb
   │   port: 8000
   │   data_path: /var/lib/chromadb
```

## Configuration Options

### NixOS Module Options

```nix
services.helix-indexer = {
  enable = true;                                    # Enable the service
  watchPaths = [ "/home" "/etc/nixos" ];           # Paths to monitor
  excludePatterns = [ "*.swp" ".git/*" ];          # Files to ignore
  
  helixDb = {
    host = "localhost";                            # HelixDB host
    port = 6969;                                   # HelixDB port  
    enable = true;                                 # Auto-start HelixDB
  };
  
  mcpServer = {
    enable = false;                                # MCP server for AI agents
    port = 8000;                                   # MCP server port
  };
};
```

### Home Manager Options

```nix
services.helix-search = {
  enable = true;                                   # Enable CLI integration
  searchPaths = [ "$HOME" ];                       # Suggest paths for indexing
  aliases = {                                      # Shell aliases
    "hs" = "helix-search";
    "hsf" = "helix-search --files"; 
  };
};
```

## Architecture Details

### System vs User Services

**System Level (NixOS Module):**
- HelixDB database service
- File monitoring with inotify (requires root for system paths)
- Kernel parameter tuning (inotify limits)
- MCP server for AI agents

**User Level (Home Manager):**
- CLI search tool and aliases
- User-specific configuration
- Shell integration

### File Monitoring Flow

```
File Change → inotify Event → Batch Processing → Tree-sitter Chunking → HelixDB Indexing
     ↓              ↓              ↓                    ↓                    ↓
System Files   Real-time     Efficient         Semantic Blocks      Vector Storage
User Files     Detection     Processing        Language-aware       + Metadata
```

### Search Flow

```
User Query → Vector Embedding → Similarity Search → Metadata Filtering → Ranked Results
     ↓              ↓                   ↓                 ↓                  ↓
"chromadb"    Dense Vector      Cosine Distance    File Type/Path     Precise Lines
              [0.23, -0.15...]      Ranking           Filtering         + Scores
```

## Dependencies

- **Python**: pyinotify, watchdog, pyyaml, requests
- **NixOS**: inotify support, systemd services
- **HelixDB**: Graph-vector database (included as service)
- **Tree-sitter**: Language parsing (simulated, ready for real integration)

## Limitations & Notes

1. **HelixDB Package**: This flake assumes HelixDB is available as `pkgs.helix-db`. You may need to package it separately or use the stub service.

2. **Tree-sitter Integration**: Currently simulated with heuristic chunking. Real Tree-sitter integration would require language grammars and bindings.

3. **Permissions**: System-wide monitoring requires the service to run with appropriate privileges.

4. **Storage**: Indexed data persists in `/var/lib/helix-db`. Consider backup strategies.

## Extending the System

### Adding Language Support

Add new file extensions to the chunking logic in `src/helix_indexer.py`:

```python
# In HelixClient._chunk_content()
elif file_ext in ['.hs', '.elm', '.clj']:  # Add languages
    return self._chunk_functional(content, file_ext)
```

### Custom Filters

Extend search filters in `src/helix_search.py`:

```python
# Add new filter options
parser.add_argument('--author', help='Filter by git author')
parser.add_argument('--modified-since', help='Filter by modification date')
```

### AI Agent Tools

Add new MCP tools in `src/helix_mcp_server.py`:

```python
# New tool for code analysis
async def analyze_code_quality(self, filepath: str) -> Dict[str, Any]:
    # Implement code quality analysis
    pass
```

## Troubleshooting

### No Results Found
```bash
# Check service status
systemctl status helix-indexer
systemctl status helix-db

# Check logs
journalctl -u helix-indexer -f
```

### inotify Limits
```bash
# Check current limits
cat /proc/sys/fs/inotify/max_user_watches

# The flake automatically increases limits, but you can verify:
sysctl fs.inotify.max_user_watches
```

### Search Not Working
```bash
# Test connection to HelixDB
curl http://localhost:6969/health

# Check configuration  
helix-search --stats
```

## Contributing

1. Fork the repository
2. Add new features or fix bugs
3. Test with `nix flake check`
4. Submit a pull request

## License

MIT License - See LICENSE file for details.
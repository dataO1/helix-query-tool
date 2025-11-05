#!/usr/bin/env python3
"""
HelixDB Search CLI Tool
Simple command-line interface for semantic search across indexed files
"""

import os
import sys
import json
import yaml
import argparse
from pathlib import Path
from typing import List, Dict, Any, Optional
from dataclasses import dataclass


@dataclass
class SearchConfig:
    """Configuration for search tool"""
    helix_host: str = "localhost"
    helix_port: int = 6969
    default_limit: int = 10
    highlight_results: bool = True
    config_path: str = "~/.config/helix-search/config.yaml"


class HelixSearchClient:
    """Client for searching HelixDB"""
    
    def __init__(self, host: str = "localhost", port: int = 6969):
        self.host = host
        self.port = port
        self.base_url = f"http://{host}:{port}"
    
    def search(self, query: str, limit: int = 10, filters: Dict[str, Any] = None) -> List[Dict[str, Any]]:
        """Search for documents matching the query"""
        try:
            # Simulate HelixDB search - replace with actual client
            print(f"🔍 Searching for: '{query}'")
            
            # Mock results for demonstration
            mock_results = [
                {
                    "filepath": "/etc/nixos/flake.nix",
                    "filetype": "nix",
                    "content": "chromadb.enabled = true;\n  chromadb.dataDir = \"/var/lib/chromadb\";",
                    "score": 0.942,
                    "line_start": 42,
                    "line_end": 44,
                    "chunk_index": 0,
                    "directory": "/etc/nixos"
                },
                {
                    "filepath": "/home/user/.config/chromadb/config.yaml",
                    "filetype": "yaml", 
                    "content": "service:\n  name: chromadb\n  port: 8000\n  data_path: /var/lib/chromadb",
                    "score": 0.887,
                    "line_start": 1,
                    "line_end": 10,
                    "chunk_index": 0,
                    "directory": "/home/user/.config/chromadb"
                },
                {
                    "filepath": "/etc/nixos/services.nix",
                    "filetype": "nix",
                    "content": "# ChromaDB service configuration\nservices.chromadb = {\n  enable = true;\n  host = \"0.0.0.0\";\n};",
                    "score": 0.834,
                    "line_start": 15,
                    "line_end": 20,
                    "chunk_index": 1,
                    "directory": "/etc/nixos"
                }
            ]
            
            # Apply filters
            if filters:
                if "filetype" in filters:
                    mock_results = [r for r in mock_results if r["filetype"] == filters["filetype"]]
                if "directory" in filters:
                    mock_results = [r for r in mock_results if filters["directory"] in r["directory"]]
            
            return mock_results[:limit]
            
        except Exception as e:
            print(f"❌ Search failed: {e}")
            return []
    
    def search_files(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Search for files by name/path"""
        # This would use a different HelixDB query focused on file metadata
        return self.search(query, limit, {"search_type": "filename"})


def load_config() -> SearchConfig:
    """Load configuration from config file and environment"""
    config = SearchConfig()
    
    # Try to load from config file
    config_path = Path(config.config_path).expanduser()
    if config_path.exists():
        try:
            with open(config_path, 'r') as f:
                file_config = yaml.safe_load(f)
                
            if 'helix_db' in file_config:
                config.helix_host = file_config['helix_db'].get('host', config.helix_host)
                config.helix_port = file_config['helix_db'].get('port', config.helix_port)
            
            if 'cli' in file_config:
                config.default_limit = file_config['cli'].get('default_limit', config.default_limit)
                config.highlight_results = file_config['cli'].get('highlight_results', config.highlight_results)
                
        except Exception as e:
            print(f"⚠️  Failed to load config from {config_path}: {e}")
    
    # Environment overrides
    config.helix_host = os.getenv("HELIX_DB_HOST", config.helix_host)
    config.helix_port = int(os.getenv("HELIX_DB_PORT", config.helix_port))
    
    return config


def format_result(result: Dict[str, Any], index: int, highlight: bool = True) -> str:
    """Format a search result for display"""
    filepath = result.get("filepath", "Unknown")
    score = result.get("score", 0.0)
    content = result.get("content", "")
    filetype = result.get("filetype", "unknown")
    line_start = result.get("line_start")
    line_end = result.get("line_end")
    
    # Format header
    header = f"\n{index}. {filepath}"
    if line_start and line_end:
        if line_start == line_end:
            header += f" (line {line_start})"
        else:
            header += f" (lines {line_start}-{line_end})"
    
    # Format metadata
    metadata = f"   📁 Type: {filetype}  📊 Score: {score:.3f}"
    
    # Format content preview
    preview_lines = content.split('\n')[:4]  # Show first 4 lines
    preview = '\n'.join(f"   │ {line}" for line in preview_lines)
    
    if len(content.split('\n')) > 4:
        preview += "\n   │ ..."
    
    # Add color highlighting if supported
    if highlight and hasattr(sys.stdout, 'isatty') and sys.stdout.isatty():
        try:
            # Simple ANSI color codes
            header = f"\033[94m{header}\033[0m"  # Blue
            metadata = f"\033[90m{metadata}\033[0m"  # Gray
            preview = f"\033[92m{preview}\033[0m"  # Green
        except:
            pass  # Fall back to no colors
    
    return f"{header}\n{metadata}\n{preview}"


def search_command(args, config: SearchConfig):
    """Execute search command"""
    client = HelixSearchClient(config.helix_host, config.helix_port)
    
    query = ' '.join(args.query)
    limit = args.limit or config.default_limit
    
    # Build filters
    filters = {}
    if args.filetype:
        filters["filetype"] = args.filetype
    if args.directory:
        filters["directory"] = args.directory
    
    # Execute search
    if args.files:
        results = client.search_files(query, limit)
    else:
        results = client.search(query, limit, filters)
    
    # Display results
    if not results:
        print("❌ No results found.")
        return
    
    print(f"\n🎯 Found {len(results)} result(s):")
    
    for i, result in enumerate(results, 1):
        formatted = format_result(result, i, config.highlight_results and not args.no_color)
        print(formatted)
    
    print()  # Empty line at end


def list_command(args, config: SearchConfig):
    """List indexed files"""
    client = HelixSearchClient(config.helix_host, config.helix_port)
    
    # This would be a special query to list all indexed files
    print("📂 Indexed files:")
    
    # Mock listing - replace with actual HelixDB query
    mock_files = [
        "/etc/nixos/flake.nix",
        "/etc/nixos/configuration.nix", 
        "/etc/nixos/services.nix",
        "/home/user/.config/chromadb/config.yaml",
        "/home/user/Documents/notes.md",
        "/home/user/projects/myapp/main.py"
    ]
    
    for filepath in mock_files:
        print(f"  {filepath}")


def stats_command(args, config: SearchConfig):
    """Show indexing statistics"""
    print("📊 Indexing Statistics:")
    print(f"  • Total documents: 1,234")
    print(f"  • Total chunks: 5,678") 
    print(f"  • Index size: 45.6 MB")
    print(f"  • Last updated: 2 minutes ago")
    print(f"  • HelixDB: {config.helix_host}:{config.helix_port}")


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description="Search your indexed files with HelixDB",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  helix-search "chromadb service configuration"
  helix-search "function definition" --filetype py
  helix-search "nginx config" --directory /etc
  helix-search --files "flake.nix"
  helix-search --list
        """
    )
    
    # Subcommands
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Search command (default)
    search_parser = subparsers.add_parser('search', help='Search file contents')
    search_parser.add_argument('query', nargs='+', help='Search query')
    search_parser.add_argument('-l', '--limit', type=int, help='Maximum results to return')
    search_parser.add_argument('-t', '--filetype', help='Filter by file type (e.g., py, nix, yaml)')
    search_parser.add_argument('-d', '--directory', help='Filter by directory path')
    search_parser.add_argument('-f', '--files', action='store_true', help='Search file names instead of content')
    search_parser.add_argument('--no-color', action='store_true', help='Disable colored output')
    
    # List command
    list_parser = subparsers.add_parser('list', help='List indexed files')
    
    # Stats command  
    stats_parser = subparsers.add_parser('stats', help='Show indexing statistics')
    
    # Parse arguments
    args = parser.parse_args()
    
    # Load configuration
    config = load_config()
    
    # Handle commands
    if args.command == 'list':
        list_command(args, config)
    elif args.command == 'stats':
        stats_command(args, config)
    else:
        # Default to search, even if no subcommand specified
        if not hasattr(args, 'query'):
            # No subcommand and no query - treat remaining args as query
            if len(sys.argv) > 1:
                args.query = sys.argv[1:]
                args.limit = None
                args.filetype = None
                args.directory = None
                args.files = False
                args.no_color = False
            else:
                parser.print_help()
                return
        
        search_command(args, config)


if __name__ == "__main__":
    main()
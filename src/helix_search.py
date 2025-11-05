#!/usr/bin/env python3
"""
HelixDB Search CLI Tool
Real backend connection with actual semantic search against HelixDB.
"""

import os
import sys
import argparse
from pathlib import Path
from typing import List, Dict, Any, Optional
import yaml
from dataclasses import dataclass

try:
    from helix import Client
except ImportError:
    print("Error: helix-py is not installed. Install with: pip install helix-py")
    sys.exit(1)


@dataclass
class SearchConfig:
    """Configuration for search tool"""
    helix_host: str = "localhost"
    helix_port: int = 6969
    default_limit: int = 10
    highlight_results: bool = True
    config_path: str = "~/.config/helix-search/config.yaml"


class HelixSearchClient:
    """Client for searching HelixDB with real backend connection"""
    
    def __init__(self, host: str = "localhost", port: int = 6969):
        self.host = host
        self.port = port
        try:
            self.client = Client(host=host, port=port, local=False)
            self.client.is_connected()
        except Exception as e:
            print(f"❌ Failed to connect to HelixDB at {host}:{port}: {e}")
            raise
    
    def search(self, query: str, limit: int = 10, filters: Dict[str, Any] = None) -> List[Dict[str, Any]]:
        """
        Search HelixDB using vector similarity.
        Query is embedded and searched against indexed documents.
        """
        try:
            # Call HelixDB SearchWithText query
            # This uses the backend's built-in embedding and semantic search
            results = self.client.query(
                "SearchWithText",
                {
                    "query": query,
                    "limit": limit
                }
            )
            
            # Apply optional filters on results
            if filters:
                if "filetype" in filters:
                    results = [r for r in results if r.get("metadata", {}).get("filetype") == filters["filetype"]]
                if "directory" in filters:
                    results = [r for r in results if filters["directory"] in r.get("metadata", {}).get("filepath", "")]
            
            return results if results else []
            
        except Exception as e:
            print(f"❌ Search failed: {e}")
            return []
    
    def search_files(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Search for files by name/path using keyword search.
        """
        try:
            results = self.client.query(
                "SearchKeyword",
                {
                    "keywords": [query],
                    "limit": limit
                }
            )
            return results if results else []
            
        except Exception as e:
            print(f"❌ File search failed: {e}")
            return []
    
    def get_stats(self) -> Dict[str, Any]:
        """Get indexing statistics from HelixDB"""
        try:
            stats = self.client.query("GetIndexStats", {})
            return stats if stats else {}
        except Exception:
            return {}
    
    def list_indexed_files(self, limit: int = 100) -> List[Dict[str, Any]]:
        """List all indexed files"""
        try:
            files = self.client.query(
                "ListIndexedFiles",
                {"limit": limit}
            )
            return files if files else []
        except Exception:
            return []


def load_config() -> SearchConfig:
    """Load configuration from config file and environment"""
    config = SearchConfig()
    
    # Try to load from config file
    config_path = Path(config.config_path).expanduser()
    if config_path.exists():
        try:
            with open(config_path, 'r') as f:
                file_config = yaml.safe_load(f) or {}
                
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
    # Handle both direct result and metadata structure
    if "metadata" in result:
        metadata = result.get("metadata", {})
        filepath = metadata.get("filepath", "Unknown")
        filetype = metadata.get("filetype", "unknown")
        line_start = metadata.get("line_start")
        line_end = metadata.get("line_end")
    else:
        filepath = result.get("filepath", "Unknown")
        filetype = result.get("filetype", "unknown")
        line_start = result.get("line_start")
        line_end = result.get("line_end")
    
    score = result.get("score", 0.0)
    content = result.get("content", "")
    
    # Format header
    header = f"\n{index}. {filepath}"
    if line_start and line_end:
        if line_start == line_end:
            header += f" (line {line_start})"
        else:
            header += f" (lines {line_start}-{line_end})"
    
    # Format metadata
    metadata_str = f"   📁 Type: {filetype}  📊 Score: {score:.3f}"
    
    # Format content preview
    preview_lines = content.split('\n')[:4] if content else []
    preview = '\n'.join(f"   │ {line}" for line in preview_lines)
    
    if len((content or "").split('\n')) > 4:
        preview += "\n   │ ..."
    
    # Add color highlighting if supported
    if highlight and hasattr(sys.stdout, 'isatty') and sys.stdout.isatty():
        try:
            # ANSI color codes
            header = f"\033[94m{header}\033[0m"  # Blue
            metadata_str = f"\033[90m{metadata_str}\033[0m"  # Gray
            if preview:
                preview = f"\033[92m{preview}\033[0m"  # Green
        except:
            pass
    
    result_text = f"{header}\n{metadata_str}"
    if preview:
        result_text += f"\n{preview}"
    return result_text


def search_command(args, config: SearchConfig):
    """Execute search command"""
    try:
        client = HelixSearchClient(config.helix_host, config.helix_port)
    except Exception:
        print("❌ Cannot connect to HelixDB. Is it running?")
        sys.exit(1)
    
    query = ' '.join(args.query)
    limit = args.limit or config.default_limit
    
    # Build filters
    filters = {}
    if args.filetype:
        filters["filetype"] = args.filetype
    if args.directory:
        filters["directory"] = args.directory
    
    # Execute search
    print(f"🔍 Searching for: '{query}'")
    
    if args.files:
        results = client.search_files(query, limit)
    else:
        results = client.search(query, limit, filters)
    
    # Display results
    if not results:
        print("❌ No results found.")
        return
    
    print(f"\n🎯 Found {len(results)} result(s):\n")
    
    for i, result in enumerate(results, 1):
        formatted = format_result(result, i, config.highlight_results and not args.no_color)
        print(formatted)
    
    print()  # Empty line at end


def list_command(args, config: SearchConfig):
    """List indexed files"""
    try:
        client = HelixSearchClient(config.helix_host, config.helix_port)
    except Exception:
        print("❌ Cannot connect to HelixDB. Is it running?")
        sys.exit(1)
    
    print("📂 Indexed files:\n")
    
    files = client.list_indexed_files(limit=args.limit or 50)
    
    if not files:
        print("No files indexed yet.")
        return
    
    for filepath in files:
        if isinstance(filepath, dict):
            filepath = filepath.get("filepath", str(filepath))
        print(f"  ✓ {filepath}")
    
    print(f"\n Total: {len(files)} files")


def stats_command(args, config: SearchConfig):
    """Show indexing statistics"""
    try:
        client = HelixSearchClient(config.helix_host, config.helix_port)
    except Exception:
        print("❌ Cannot connect to HelixDB. Is it running?")
        sys.exit(1)
    
    print("📊 Indexing Statistics:\n")
    
    stats = client.get_stats()
    
    if stats:
        print(f"  • Total documents: {stats.get('total_documents', 'N/A')}")
        print(f"  • Total chunks: {stats.get('total_chunks', 'N/A')}")
        print(f"  • Index size: {stats.get('index_size', 'N/A')}")
        print(f"  • Last updated: {stats.get('last_updated', 'N/A')}")
    else:
        print("  Unable to retrieve statistics")
    
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
  helix-search --stats
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
    list_parser.add_argument('-l', '--limit', type=int, default=50, help='Number of files to list')
    
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
    elif args.command == 'search' or args.command is None:
        # Default to search if no subcommand or explicit search
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
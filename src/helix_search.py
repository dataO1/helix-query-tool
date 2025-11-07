#!/usr/bin/env python3

"""
HelixDB Search CLI Tool

Semantic/keyword search and stats via real HelixDB backend.
"""

import os
import sys
import argparse
from pathlib import Path
from typing import List, Dict, Any, Optional
import yaml
from dataclasses import dataclass

from helix.client import Client

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
            self.client = Client(local=True)
        except Exception as e:
            print(f"❌ Failed to connect to HelixDB at {host}:{port}: {e}")
            raise

    def search(self, query: str, limit: int = 10, filters: Dict[str, Any] = None) -> List[Dict[str, Any]]:
        """Semantic search via backend embeddings/semantic search"""
        try:
            # Use the official SearchWithText query (case-sensitive)
            payload = {"query": query, "limit": limit}
            results = self.client.query("search_with_text", payload)
            # Post-filter if needed
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
        """Filename/path keyword search"""
        try:
            payload = {"keywords": [query], "limit": limit}
            results = self.client.query("search_keyword", payload)
            return results if results else []
        except Exception as e:
            print(f"❌ File search failed: {e}")
            return []

    def get_stats(self) -> Dict[str, Any]:
        """Index statistics"""
        try:
            stats = self.client.query("get_index_stats", {})
            return stats if stats else {}
        except Exception:
            return {}

    def list_indexed_files(self, limit: int = 100) -> List[Dict[str, Any]]:
        """List all indexed files"""
        try:
            files = self.client.query("list_indexed_files", {"limit": limit})
            return files if files else []
        except Exception:
            return []

def load_config() -> SearchConfig:
    """Load configuration from config file and environment"""
    config = SearchConfig()
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
            print(f"⚠️ Failed to load config from {config_path}: {e}")
    config.helix_host = os.getenv("HELIX_DB_HOST", config.helix_host)
    config.helix_port = int(os.getenv("HELIX_DB_PORT", config.helix_port))
    return config

def format_result(result: Dict[str, Any], index: int, highlight: bool = True) -> str:
    """Format a search result for display"""
    metadata = result.get("metadata", result)
    filepath = metadata.get("filepath", "Unknown")
    filetype = metadata.get("filetype", "unknown")
    line_start = metadata.get("line_start")
    line_end = metadata.get("line_end")
    score = result.get("score", 0.0)
    content = result.get("content", "")
    header = f"\n{index}. {filepath}"
    if line_start and line_end:
        if line_start == line_end:
            header += f" (line {line_start})"
        else:
            header += f" (lines {line_start}-{line_end})"
    metadata_str = f" 📁 Type: {filetype} 📊 Score: {score:.3f}"
    preview_lines = content.split('\n')[:4] if content else []
    preview = '\n'.join(f" │ {line}" for line in preview_lines)
    if len((content or "").split('\n')) > 4:
        preview += "\n │ ..."
    if highlight and hasattr(sys.stdout, 'isatty') and sys.stdout.isatty():
        try:
            header = f"\033[94m{header}\033[0m"
            metadata_str = f"\033[90m{metadata_str}\033[0m"
            if preview:
                preview = f"\033[92m{preview}\033[0m"
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
    filters = {}
    if args.filetype:
        filters["filetype"] = args.filetype
    if args.directory:
        filters["directory"] = args.directory
    print(f"🔍 Searching for: '{query}'")
    if args.files:
        results = client.search_files(query, limit)
    else:
        results = client.search(query, limit, filters)
    if not results:
        print("❌ No results found.")
        return
    print(f"\n🎯 Found {len(results)} result(s):\n")
    for i, result in enumerate(results, 1):
        formatted = format_result(result, i, config.highlight_results and not args.no_color)
        print(formatted)
    print()

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
    for entry in files:
        filepath = entry.get("filepath", str(entry))
        print(f" ✓ {filepath}")
    print(f"\nTotal: {len(files)} files")

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
        print(f" • Total documents: {stats.get('total_documents', 'N/A')}")
        print(f" • Total chunks: {stats.get('total_chunks', 'N/A')}")
        print(f" • Index size: {stats.get('index_size', 'N/A')}")
        print(f" • Last updated: {stats.get('last_updated', 'N/A')}")
    else:
        print(" Unable to retrieve statistics")
    print(f" • HelixDB: {config.helix_host}:{config.helix_port}")

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
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    search_parser = subparsers.add_parser('search', help='Search file contents')
    search_parser.add_argument('query', nargs='+', help='Search query')
    search_parser.add_argument('-l', '--limit', type=int, help='Maximum results to return')
    search_parser.add_argument('-t', '--filetype', help='Filter by file type (e.g., py, nix, yaml)')
    search_parser.add_argument('-d', '--directory', help='Filter by directory path')
    search_parser.add_argument('-f', '--files', action='store_true', help='Search file names instead of content')
    search_parser.add_argument('--no-color', action='store_true', help='Disable colored output')
    list_parser = subparsers.add_parser('list', help='List indexed files')
    list_parser.add_argument('-l', '--limit', type=int, default=50, help='Number of files to list')
    stats_parser = subparsers.add_parser('stats', help='Show indexing statistics')
    args = parser.parse_args()
    config = load_config()
    if args.command == 'list':
        list_command(args, config)
    elif args.command == 'stats':
        stats_command(args, config)
    elif args.command == 'search' or args.command is None:
        # Default to search if no subcommand or explicit search
        if not hasattr(args, 'query'):
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

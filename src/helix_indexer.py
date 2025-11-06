#!/usr/bin/env python3

"""
HelixDB File Indexer Service

Auto-indexes file changes using inotify and HelixDB's built-in smart chunking.
Delegates chunking to HelixDB backend which automatically detects file types.
"""

import os
import sys
import time
import logging
from pathlib import Path
from typing import List, Dict, Any, Optional
import pyinotify
import fnmatch
from dataclasses import dataclass

try:
    import helix
    from helix.client import Client
except ImportError:
    print("Error: helix-py is not installed. Install with: pip install helix-py")
    sys.exit(1)

@dataclass
class IndexerConfig:
    """Configuration for the file indexer"""
    helix_host: str = "localhost"
    helix_port: int = 6969
    watch_paths: List[str] = None
    exclude_patterns: List[str] = None
    batch_size: int = 10
    log_level: str = "INFO"

    def __post_init__(self):
        if self.watch_paths is None:
            self.watch_paths = ["/home", "/etc/nixos"]
        if self.exclude_patterns is None:
            self.exclude_patterns = ["*.swp", "*.tmp", "*~", ".git/*", "node_modules/*"]

class HelixIndexer:
    """HelixDB client for indexing operations with built-in smart chunking"""

    def __init__(self, host: str = "localhost", port: int = 6969):
        try:
            # Connect to HelixDB instance
            self.client = Client(host=host, port=port, local=False, verbose=True)
            logging.info(f"✅ Connected to HelixDB at {host}:{port}")
        except Exception as e:
            logging.error(f"❌ Failed to connect to HelixDB: {e}")
            raise

    def index_document(self, filepath: str, content: str) -> bool:
        """
        Index a document in HelixDB using backend smart chunking.
        HelixDB automatically detects file type and applies appropriate chunking.
        """
        try:
            if not content.strip():
                logging.debug(f"Skipping empty file: {filepath}")
                return True

            path_obj = Path(filepath)
            file_ext = path_obj.suffix.lower()
            filetype = file_ext[1:] if file_ext else "unknown"

            # Metadata for the document
            metadata = {
                "filepath": filepath,
                "filename": path_obj.name,
                "filetype": filetype,
                "size": len(content),
                "indexed_at": int(time.time()),
                "directory": str(path_obj.parent)
            }

            # HelixDB's query for inserting indexed documents
            # The backend handles chunking automatically based on file type
            result = self.client.query(
                "AddDocument",
                {
                    "filepath": filepath,
                    "content": content,
                    "filetype": filetype,
                    "metadata": metadata
                }
            )

            logging.info(f"✓ Indexed: {filepath} ({len(content)} chars, type: {filetype})")
            return True
        except Exception as e:
            logging.error(f"Failed to index {filepath}: {e}")
            return False

    def health_check(self) -> bool:
        """Check if HelixDB is healthy"""
        try:
            # Test connection
            self.client.query("GetHealth", {})
            return True
        except Exception:
            return False

class FileChangeHandler(pyinotify.ProcessEvent):
    """Handle file system events for indexing"""

    def __init__(self, indexer: HelixIndexer, config: IndexerConfig):
        super().__init__()
        self.indexer = indexer
        self.config = config
        self.pending_files = set()
        self.last_batch_time = time.time()
        self.failed_files = {}

    def should_ignore_file(self, filepath: str) -> bool:
        """Check if file should be ignored based on patterns"""
        filename = os.path.basename(filepath)
        for pattern in self.config.exclude_patterns:
            if fnmatch.fnmatch(filename, pattern) or fnmatch.fnmatch(filepath, pattern):
                return True
        return False

    def process_default(self, event):
        """Process file system events"""
        if event.maskname not in ['IN_MODIFY', 'IN_CREATE', 'IN_MOVED_TO']:
            return

        filepath = event.pathname

        if self.should_ignore_file(filepath):
            logging.debug(f"Ignoring excluded file: {filepath}")
            return

        # Skip if file doesn't exist or can't be read
        if not os.path.isfile(filepath):
            return

        # Add to pending batch
        self.pending_files.add(filepath)

        # Process batch if enough files or enough time passed
        now = time.time()
        if (len(self.pending_files) >= self.config.batch_size or
                now - self.last_batch_time > 5):  # 5 second timeout
            self.process_batch()

    def process_batch(self):
        """Process accumulated file changes"""
        if not self.pending_files:
            return

        logging.info(f"📦 Processing batch of {len(self.pending_files)} files")

        for filepath in list(self.pending_files):
            try:
                self.index_file(filepath)
                self.pending_files.discard(filepath)

                # Reset retry count on success
                if filepath in self.failed_files:
                    del self.failed_files[filepath]

            except Exception as e:
                logging.error(f"Failed to process {filepath}: {e}")
                # Track failures for potential retry
                self.failed_files[filepath] = self.failed_files.get(filepath, 0) + 1

        self.last_batch_time = time.time()

    def index_file(self, filepath: str):
        """Index a single file"""
        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()

            # Use HelixDB's indexer with built-in smart chunking
            success = self.indexer.index_document(filepath, content)

            if not success:
                logging.warning(f"Indexing returned false for: {filepath}")

        except PermissionError:
            logging.debug(f"Permission denied reading: {filepath}")
        except Exception as e:
            logging.error(f"Error indexing {filepath}: {e}")

def load_config() -> IndexerConfig:
    """Load configuration from environment"""
    config = IndexerConfig()

    # Environment variables
    config.helix_host = os.getenv("HELIX_DB_HOST", config.helix_host)
    config.helix_port = int(os.getenv("HELIX_DB_PORT", config.helix_port))

    watch_paths_env = os.getenv("WATCH_PATHS")
    if watch_paths_env:
        config.watch_paths = [p.strip() for p in watch_paths_env.split(":") if p.strip()]

    exclude_patterns_env = os.getenv("EXCLUDE_PATTERNS")
    if exclude_patterns_env:
        config.exclude_patterns = [p.strip() for p in exclude_patterns_env.split(":") if p.strip()]

    config.log_level = os.getenv("LOG_LEVEL", config.log_level)

    return config

def setup_logging(level: str):
    """Setup logging configuration - logs to stdout and optionally to file if writable"""
    numeric_level = getattr(logging, level.upper(), logging.INFO)

    handlers = [logging.StreamHandler(sys.stdout)]

    # Try to add file handler if directory exists and is writable
    log_dir = "/var/lib/helix-indexer"
    if os.path.exists(log_dir) and os.access(log_dir, os.W_OK):
        try:
            handlers.append(logging.FileHandler(f"{log_dir}/indexer.log", mode='a'))
        except Exception as e:
            logging.warning(f"Could not create log file: {e}")

    logging.basicConfig(
        level=numeric_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=handlers
    )

def main():
    """Main entry point"""
    config = load_config()
    setup_logging(config.log_level)

    logging.info("🚀 Starting HelixDB File Indexer")
    logging.info(f"📂 Watching paths: {config.watch_paths}")
    logging.info(f"🚫 Exclude patterns: {config.exclude_patterns}")
    logging.info(f"🗄️ Batch size: {config.batch_size}")

    # Initialize HelixDB client
    try:
        indexer = HelixIndexer(config.helix_host, config.helix_port)
    except Exception as e:
        logging.error(f"💥 Failed to initialize HelixDB indexer: {e}")
        sys.exit(1)

    # Setup file monitoring
    wm = pyinotify.WatchManager()
    mask = pyinotify.IN_MODIFY | pyinotify.IN_CREATE | pyinotify.IN_MOVED_TO
    handler = FileChangeHandler(indexer, config)
    notifier = pyinotify.Notifier(wm, handler)

    # Add watches for all configured paths
    for watch_path in config.watch_paths:
        if os.path.exists(watch_path):
            logging.info(f"👀 Adding watch for: {watch_path}")
            try:
                wm.add_watch(watch_path, mask, rec=True, auto_add=True)
            except Exception as e:
                logging.error(f"Failed to add watch for {watch_path}: {e}")
        else:
            logging.warning(f"⚠️ Watch path does not exist: {watch_path}")

    try:
        logging.info("✨ File indexer started successfully. Monitoring for changes...")
        notifier.loop()
    except KeyboardInterrupt:
        logging.info("🛑 Shutting down file indexer")
        # Process any remaining files
        handler.process_batch()
    except Exception as e:
        logging.error(f"💥 Indexer crashed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
HelixDB File Indexer Service
Auto-indexes file changes using inotify and Tree-sitter semantic chunking
"""

import os
import sys
import time
import json
import logging
from pathlib import Path
from typing import List, Dict, Any, Optional
import pyinotify
import yaml
import fnmatch
from dataclasses import dataclass


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


class HelixClient:
    """Simple HelixDB client for indexing operations"""
    
    def __init__(self, host: str = "localhost", port: int = 6969):
        self.host = host
        self.port = port
        self.base_url = f"http://{host}:{port}"
    
    def index_document(self, filepath: str, content: str, metadata: Dict[str, Any]) -> bool:
        """Index a document in HelixDB"""
        try:
            # Simulate HelixDB indexing - replace with actual client
            logging.info(f"Indexing: {filepath} ({len(content)} chars)")
            
            # Chunk content based on file type
            chunks = self._chunk_content(content, filepath)
            
            for i, chunk in enumerate(chunks):
                chunk_metadata = {
                    **metadata,
                    "chunk_index": i,
                    "chunk_count": len(chunks)
                }
                # Here you would call actual HelixDB API
                # helix_client.add_document(text=chunk, metadata=chunk_metadata)
                
            return True
            
        except Exception as e:
            logging.error(f"Failed to index {filepath}: {e}")
            return False
    
    def _chunk_content(self, content: str, filepath: str) -> List[str]:
        """Chunk content based on file type using semantic strategies"""
        file_ext = Path(filepath).suffix.lower()
        
        # Code files - simulate Tree-sitter chunking
        if file_ext in ['.nix', '.py', '.rs', '.go', '.js', '.ts']:
            return self._chunk_code(content, file_ext)
        
        # Config files - chunk by sections
        elif file_ext in ['.yaml', '.yml', '.toml', '.json']:
            return self._chunk_config(content)
        
        # Default semantic chunking
        else:
            return self._chunk_semantic(content)
    
    def _chunk_code(self, content: str, ext: str) -> List[str]:
        """Simulate Tree-sitter code chunking"""
        lines = content.splitlines()
        chunks = []
        current_chunk = []
        indent_stack = []
        
        for line in lines:
            stripped = line.strip()
            if not stripped:
                current_chunk.append(line)
                continue
                
            # Simple heuristic for function/block boundaries
            if any(keyword in stripped for keyword in ['def ', 'class ', 'function ', '{']):
                if current_chunk:
                    chunks.append('\n'.join(current_chunk))
                    current_chunk = []
                current_chunk.append(line)
            else:
                current_chunk.append(line)
                
            # Chunk at reasonable size
            if len(current_chunk) > 50:
                chunks.append('\n'.join(current_chunk))
                current_chunk = []
        
        if current_chunk:
            chunks.append('\n'.join(current_chunk))
            
        return [chunk for chunk in chunks if chunk.strip()]
    
    def _chunk_config(self, content: str) -> List[str]:
        """Chunk configuration files by sections"""
        lines = content.splitlines()
        chunks = []
        current_chunk = []
        
        for line in lines:
            stripped = line.strip()
            # New section (starts at column 0, not empty, not comment)
            if stripped and not line.startswith(' ') and not line.startswith('#'):
                if current_chunk:
                    chunks.append('\n'.join(current_chunk))
                    current_chunk = []
            current_chunk.append(line)
            
        if current_chunk:
            chunks.append('\n'.join(current_chunk))
            
        return [chunk for chunk in chunks if chunk.strip()]
    
    def _chunk_semantic(self, content: str, max_size: int = 2000) -> List[str]:
        """Basic semantic chunking by paragraphs/sentences"""
        if len(content) <= max_size:
            return [content]
            
        # Split by double newlines (paragraphs)
        paragraphs = content.split('\n\n')
        chunks = []
        current_chunk = []
        current_size = 0
        
        for para in paragraphs:
            para_size = len(para)
            if current_size + para_size > max_size and current_chunk:
                chunks.append('\n\n'.join(current_chunk))
                current_chunk = []
                current_size = 0
            
            current_chunk.append(para)
            current_size += para_size
            
        if current_chunk:
            chunks.append('\n\n'.join(current_chunk))
            
        return chunks


class FileChangeHandler(pyinotify.ProcessEvent):
    """Handle file system events for indexing"""
    
    def __init__(self, helix_client: HelixClient, config: IndexerConfig):
        super().__init__()
        self.helix_client = helix_client
        self.config = config
        self.pending_files = set()
        self.last_batch_time = time.time()
    
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
            
        logging.info(f"Processing batch of {len(self.pending_files)} files")
        
        for filepath in list(self.pending_files):
            try:
                self.index_file(filepath)
                self.pending_files.discard(filepath)
            except Exception as e:
                logging.error(f"Failed to process {filepath}: {e}")
                
        self.last_batch_time = time.time()
    
    def index_file(self, filepath: str):
        """Index a single file"""
        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            if not content.strip():
                return  # Skip empty files
            
            # Extract metadata
            path_obj = Path(filepath)
            metadata = {
                "filepath": filepath,
                "filename": path_obj.name,
                "filetype": path_obj.suffix[1:] if path_obj.suffix else "unknown",
                "size": len(content),
                "indexed_at": int(time.time()),
                "directory": str(path_obj.parent)
            }
            
            # Index in HelixDB
            success = self.helix_client.index_document(filepath, content, metadata)
            if success:
                logging.debug(f"Successfully indexed: {filepath}")
            else:
                logging.warning(f"Failed to index: {filepath}")
                
        except Exception as e:
            logging.error(f"Error indexing {filepath}: {e}")


def load_config() -> IndexerConfig:
    """Load configuration from environment and config files"""
    config = IndexerConfig()
    
    # Environment variables
    config.helix_host = os.getenv("HELIX_DB_HOST", config.helix_host)
    config.helix_port = int(os.getenv("HELIX_DB_PORT", config.helix_port))
    
    watch_paths_env = os.getenv("WATCH_PATHS")
    if watch_paths_env:
        config.watch_paths = watch_paths_env.split(":")
    
    exclude_patterns_env = os.getenv("EXCLUDE_PATTERNS") 
    if exclude_patterns_env:
        config.exclude_patterns = exclude_patterns_env.split(":")
    
    config.log_level = os.getenv("LOG_LEVEL", config.log_level)
    
    return config


def setup_logging(level: str):
    """Setup logging configuration"""
    numeric_level = getattr(logging, level.upper(), logging.INFO)
    logging.basicConfig(
        level=numeric_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler('/var/lib/helix-indexer/indexer.log')
        ]
    )


def main():
    """Main entry point"""
    config = load_config()
    setup_logging(config.log_level)
    
    logging.info("Starting HelixDB File Indexer")
    logging.info(f"Watching paths: {config.watch_paths}")
    logging.info(f"Exclude patterns: {config.exclude_patterns}")
    
    # Initialize HelixDB client
    helix_client = HelixClient(config.helix_host, config.helix_port)
    
    # Setup file monitoring
    wm = pyinotify.WatchManager()
    mask = pyinotify.IN_MODIFY | pyinotify.IN_CREATE | pyinotify.IN_MOVED_TO
    
    handler = FileChangeHandler(helix_client, config)
    notifier = pyinotify.Notifier(wm, handler)
    
    # Add watches for all configured paths
    for watch_path in config.watch_paths:
        if os.path.exists(watch_path):
            logging.info(f"Adding watch for: {watch_path}")
            wm.add_watch(watch_path, mask, rec=True, auto_add=True)
        else:
            logging.warning(f"Watch path does not exist: {watch_path}")
    
    try:
        logging.info("File indexer started successfully")
        notifier.loop()
    except KeyboardInterrupt:
        logging.info("Shutting down file indexer")
        # Process any remaining files
        handler.process_batch()
    except Exception as e:
        logging.error(f"Indexer crashed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
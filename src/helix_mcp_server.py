#!/usr/bin/env python3
"""
HelixDB MCP Server
Model Context Protocol server for AI agent integration with real HelixDB backend.
"""

import os
import asyncio
from typing import Dict, Any, List
from dataclasses import dataclass

try:
    from helix import Client
except ImportError:
    print("Error: helix-py is not installed. Install with: pip install helix-py")
    exit(1)


@dataclass 
class MCPConfig:
    """Configuration for MCP server"""
    helix_host: str = "localhost"
    helix_port: int = 6969
    mcp_port: int = 8000


class HelixMCPServer:
    """MCP server for HelixDB with real backend connection"""
    
    def __init__(self, config: MCPConfig):
        self.config = config
        try:
            self.client = Client(host=config.helix_host, port=config.helix_port, local=False)
            self.client.is_connected()
            print(f"✅ Connected to HelixDB at {config.helix_host}:{config.helix_port}")
        except Exception as e:
            print(f"❌ Failed to connect to HelixDB: {e}")
            raise
    
    async def search_vector(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Vector search tool - semantic search against indexed documents"""
        try:
            results = self.client.query(
                "SearchWithText",
                {
                    "query": query,
                    "limit": limit
                }
            )
            return results if results else []
            
        except Exception as e:
            print(f"❌ Vector search failed: {e}")
            return []
    
    async def search_keyword(self, keywords: List[str], limit: int = 10) -> List[Dict[str, Any]]:
        """Keyword search tool"""
        try:
            results = self.client.query(
                "SearchKeyword",
                {
                    "keywords": keywords,
                    "limit": limit
                }
            )
            return results if results else []
            
        except Exception as e:
            print(f"❌ Keyword search failed: {e}")
            return []
    
    async def get_file_content(self, filepath: str) -> Dict[str, Any]:
        """Get full file content from indexed document"""
        try:
            # Query HelixDB for specific file
            result = self.client.query(
                "GetFileContent",
                {
                    "filepath": filepath
                }
            )
            
            if result:
                return result
            else:
                return {
                    "filepath": filepath,
                    "content": "",
                    "exists": False,
                    "error": "File not found in index"
                }
                
        except Exception as e:
            return {
                "filepath": filepath,
                "content": "",
                "exists": False,
                "error": str(e)
            }
    
    async def get_file_metadata(self, filepath: str) -> Dict[str, Any]:
        """Get metadata about an indexed file"""
        try:
            result = self.client.query(
                "GetFileMetadata",
                {
                    "filepath": filepath
                }
            )
            return result if result else {}
            
        except Exception as e:
            print(f"❌ Failed to get file metadata: {e}")
            return {}
    
    def get_tools_manifest(self) -> Dict[str, Any]:
        """Return MCP tools manifest"""
        return {
            "tools": [
                {
                    "name": "search_vector", 
                    "description": "Search indexed files using semantic vector similarity. Query is embedded and matched against document vectors.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Natural language search query"
                            },
                            "limit": {
                                "type": "integer", 
                                "description": "Maximum number of results",
                                "default": 10
                            }
                        },
                        "required": ["query"]
                    }
                },
                {
                    "name": "search_keyword",
                    "description": "Search indexed files using keyword matching. Useful for exact term searches.", 
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "keywords": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "List of keywords to search for"
                            },
                            "limit": {
                                "type": "integer",
                                "description": "Maximum number of results", 
                                "default": 10
                            }
                        },
                        "required": ["keywords"]
                    }
                },
                {
                    "name": "get_file_content",
                    "description": "Retrieve the full content of a specific indexed file",
                    "inputSchema": {
                        "type": "object", 
                        "properties": {
                            "filepath": {
                                "type": "string",
                                "description": "Full path to the file"
                            }
                        },
                        "required": ["filepath"]
                    }
                },
                {
                    "name": "get_file_metadata",
                    "description": "Retrieve metadata about an indexed file (size, type, modification time, etc.)",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "filepath": {
                                "type": "string",
                                "description": "Full path to the file"
                            }
                        },
                        "required": ["filepath"]
                    }
                }
            ]
        }
    
    async def handle_tool_call(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Handle MCP tool calls from AI agents"""
        try:
            if tool_name == "search_vector":
                results = await self.search_vector(
                    arguments["query"], 
                    arguments.get("limit", 10)
                )
                return {"results": results, "count": len(results)}
                
            elif tool_name == "search_keyword":
                results = await self.search_keyword(
                    arguments["keywords"],
                    arguments.get("limit", 10) 
                )
                return {"results": results, "count": len(results)}
                
            elif tool_name == "get_file_content":
                result = await self.get_file_content(arguments["filepath"])
                return result
                
            elif tool_name == "get_file_metadata":
                result = await self.get_file_metadata(arguments["filepath"])
                return result
                
            else:
                return {"error": f"Unknown tool: {tool_name}"}
                
        except Exception as e:
            return {"error": str(e)}


def load_config() -> MCPConfig:
    """Load MCP server configuration"""
    config = MCPConfig()
    
    # Environment variables
    config.helix_host = os.getenv("HELIX_DB_HOST", config.helix_host)
    config.helix_port = int(os.getenv("HELIX_DB_PORT", config.helix_port))
    config.mcp_port = int(os.getenv("MCP_PORT", config.mcp_port))
    
    return config


async def run_mcp_server():
    """Run the MCP server"""
    config = load_config()
    server = HelixMCPServer(config)
    
    print(f"🚀 Starting HelixDB MCP Server on port {config.mcp_port}")
    print(f"🔗 Connected to HelixDB at {config.helix_host}:{config.helix_port}")
    
    print("\n📋 Available MCP Tools:")
    manifest = server.get_tools_manifest()
    for tool in manifest["tools"]:
        print(f"  • {tool['name']}: {tool['description']}")
    
    print("\n✅ MCP Server is ready for AI agent connections")
    print("   (In production, this would serve HTTP/WebSocket connections)")
    print("   Configure your MCP client to connect to this service.")
    
    # Keep server running
    try:
        while True:
            await asyncio.sleep(1)
    except KeyboardInterrupt:
        print("\n🛑 Shutting down MCP server")


def main():
    """Main entry point"""
    try:
        asyncio.run(run_mcp_server())
    except KeyboardInterrupt:
        print("Server stopped")
    except Exception as e:
        print(f"❌ Server error: {e}")
        exit(1)


if __name__ == "__main__":
    main()
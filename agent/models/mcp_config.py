"""MCP Configuration validation models."""
from typing import Dict, List, Optional
from pydantic import BaseModel, field_validator, model_validator


class MCPServerConfig(BaseModel):
    """Configuration for a single MCP server."""
    command: str
    args: Optional[List[str]] = None
    env: Optional[Dict[str, str]] = None

    @field_validator('command')
    @classmethod
    def validate_command(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Command cannot be empty")
        # Allow common commands
        allowed_commands = ['npx', 'node', 'python', 'python3', 'uvx', 'cargo', 'bun']
        # If it's a path, do basic validation
        if v.startswith('/'):
            if '..' in v:
                raise ValueError("Path traversal not allowed in command")
        elif v not in allowed_commands and '/' in v:
            raise ValueError(f"Invalid command: {v}")
        return v


class MCPConfig(BaseModel):
    """Root MCP configuration containing multiple servers."""
    mcpServers: Dict[str, MCPServerConfig]

    @model_validator(mode='after')
    def validate_servers(self) -> 'MCPConfig':
        if not self.mcpServers:
            # Empty config is valid (clears all servers)
            return self
        for name in self.mcpServers:
            if not name or not name.strip():
                raise ValueError("Server name cannot be empty")
        return self

    def to_agent_format(self) -> dict:
        """Convert to the format expected by sync_mcp_servers."""
        result = {"mcpServers": {}}
        for name, server in self.mcpServers.items():
            server_config = {"command": server.command}
            if server.args:
                server_config["args"] = server.args
            if server.env:
                server_config["env"] = server.env
            result["mcpServers"][name] = server_config
        return result


def validate_mcp_config(data: dict) -> MCPConfig:
    """Validate and parse MCP config from dictionary.

    Args:
        data: Dictionary containing MCP config

    Returns:
        Validated MCPConfig object

    Raises:
        ValueError: If validation fails
    """
    try:
        return MCPConfig.model_validate(data)
    except Exception as e:
        raise ValueError(f"Invalid MCP config: {str(e)}")

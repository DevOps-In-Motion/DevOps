package mcp

import (
	"context"
	"fmt"
	"log"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// MCPServersConfig represents the configuration for MCP servers
// Expected JSON structure:
//
// {
//   "servers": {
//     "mariadb-mcp-server": {
//       "url": "http://mariadb-mcp:9001/sse",
//       "type": "sse"
//     }
//   }
// }

type MCPServersConfig struct {
	Servers map[string]MCPServerDetails `json:"servers"`
}

type MCPServerDetails struct {
	URL  string `json:"url"`
	Type string `json:"type"`
}

type ServerInitializeArgs struct {
	ServerName string           `json:"serverName" jsonschema:"required,description=Name of the MCP server to initialize"`
	Config     MCPServersConfig `json:"config" jsonschema:"required,description=MCP server configuration"`
}

type ServerInitializeOutput struct {
	ServerDetails MCPServerDetails `json:"serverDetails" jsonschema:"description=Configuration details for the server"`
	Status        string           `json:"status" jsonschema:"description=Initialization status"`
	Message       string           `json:"message" jsonschema:"description=Additional information"`
}

// handleServerInitialize handles the server_initialize tool
func handleServerInitialize(
	ctx context.Context,
	req *mcp.CallToolRequest,
	args ServerInitializeArgs,
) (*mcp.CallToolResult, ServerInitializeOutput, error) {
	log.Printf("Initializing server: %s", args.ServerName)

	serverDetails, exists := args.Config.Servers[args.ServerName]
	if !exists {
		return nil, ServerInitializeOutput{}, fmt.Errorf("server %s not found in configuration", args.ServerName)
	}

	if serverDetails.Type != "sse" {
		return nil, ServerInitializeOutput{}, fmt.Errorf("unsupported server type: %s", serverDetails.Type)
	}

	log.Printf("Server details: URL=%s Type=%s", serverDetails.URL, serverDetails.Type)

	// TODO: Add your actual MCP server initialization logic here
	// This might involve:
	// - Validating the server endpoint
	// - Establishing connections
	// - Loading configurations
	// - etc.

	output := ServerInitializeOutput{
		ServerDetails: serverDetails,
		Status:        "initialized",
		Message:       fmt.Sprintf("Successfully initialized %s at %s", args.ServerName, serverDetails.URL),
	}

	return nil, output, nil
}

// CreateMCPServer creates and configures an MCP server with tools
func CreateMCPServer() *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "automation-mcp-server",
		Version: "v1.0.0",
	}, nil)

	// Register the server_initialize tool
	mcp.AddTool(server, &mcp.Tool{
		Name:        "server_initialize",
		Description: "Initialize an MCP server configuration",
	}, handleServerInitialize)

	log.Println("MCP server created with server_initialize tool")
	return server
}

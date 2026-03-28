# Quickstart: Package Entry Points

## 1. Overview
The **Package Entry Points** module provides the high-level API for the `mcp_dart` package. It serves as the primary gateway for developers building Model Context Protocol (MCP) applications, exporting the essential classes for both client and server implementations.

This module is owned by the core **`mcp_dart`** package. It facilitates seamless integration with sub-packages like **`mcp_dart_cli`**, which provides command-line tools for scaffolding and inspecting MCP servers built using these entry points.

## 2. Import
To access the complete suite of MCP functionality, import the main entry point:

```dart
import 'package:mcp_dart/mcp_dart.dart';
```

## 3. Server Implementation
The `McpServer` class is the central hub for creating MCP servers. It handles the protocol handshake and provides a simplified registration API.

### Basic Setup
```dart
final serverInfo = Implementation(
  name: 'example-server',
  version: '1.0.0',
  description: 'An example MCP server',
);

final server = McpServer(
  serverInfo,
  options: const McpServerOptions(
    capabilities: ServerCapabilities(
      logging: {}, // Enable logging support
      prompts: ServerCapabilitiesPrompts(listChanged: true),
      resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
      tools: ServerCapabilitiesTools(listChanged: true),
    ),
  ),
);
```

### Registering Tools
Tools are executable functions that the server exposes to clients.

```dart
server.registerTool(
  'echo_message',
  title: 'Echo Tool',
  description: 'Repeats the input message back to the client',
  inputSchema: JsonObject(
    properties: {
      'message': JsonSchema.string(description: 'The message to echo'),
    },
    required: ['message'],
  ),
  callback: (args, extra) async {
    final String message = args['message'];
    return CallToolResult(
      content: [TextContent(text: 'Echo: $message')],
    );
  },
);
```

### Registering Resources
Resources represent data that can be read by clients, such as files, database records, or system state.

```dart
server.registerResource(
  'system_status',
  'system://status',
  (description: 'Current system status', mimeType: 'text/plain'),
  (uri, extra) async {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: 'System is healthy.',
          mimeType: 'text/plain',
        ),
      ],
    );
  },
);
```

### Registering Prompts
Prompts are reusable templates that help clients interact with LLMs.

```dart
server.registerPrompt(
  'creative_writer',
  title: 'Story Starter',
  description: 'Generates a creative writing prompt',
  argsSchema: {
    'genre': const PromptArgumentDefinition(
      description: 'The genre of the story',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final genre = args?['genre'] ?? 'fantasy';
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Write a $genre story opening.'),
        ),
      ],
    );
  },
);

// Notify clients when registration changes
server.sendPromptListChanged();
```

## 4. Client Implementation
The `McpClient` class manages the connection to an MCP server and provides methods to invoke server capabilities.

### Basic Setup and Connection
```dart
final clientInfo = Implementation(name: 'example-client', version: '1.0.0');
final client = McpClient(clientInfo);

// Use a transport (e.g., StdioClientTransport or StreamableHttpClientTransport)
// await client.connect(transport);
```

### Interacting with the Server
```dart
// List available tools
final toolsResult = await client.listTools();
print('Available tools: ${toolsResult.tools.map((t) => t.name)}');

// Call a tool
final callResult = await client.callTool(
  CallToolRequest(
    name: 'echo_message',
    arguments: {'message': 'Hello MCP!'},
  ),
);

if (!callResult.isError) {
  final content = callResult.content.first as TextContent;
  print(content.text);
}
```

## 5. Shared Utilities
The entry point provides access to cross-cutting concerns used by both clients and servers.

### Logging
The `Logger` class provides a consistent way to handle diagnostics.

```dart
final logger = Logger('MyComponent');
logger.info('Initializing component...');
logger.error('Unexpected state encountered');
```

### UUID Generation
Generate unique identifiers for tasks, sessions, or resources.

```dart
final String sessionId = generateUUID();
```

## 6. Integration with `mcp_dart_cli`
If you are developing a server using these entry points, you can use the `mcp_dart_cli` tool to verify your implementation:

1.  **Scaffolding**: Generate a new server project template.
2.  **Inspection**: Run `mcp_dart inspect` against your server binary to test protocol compliance.
3.  **Serving**: Use `mcp_dart serve` to expose your server over different transports (e.g., SSE).

Refer to the `packages/mcp_dart_cli` documentation for more details.

## 7. Module Architecture
The entry points aggregate functionality from the following internal modules:
- **`client`**: Handlers for connection management and outbound requests.
- **`server`**: Core logic for request routing and capability registration.
- **`shared`**: The JSON-RPC protocol implementation and JSON Schema validation.
- **`types`**: Type-safe data models for MCP messages and entities.
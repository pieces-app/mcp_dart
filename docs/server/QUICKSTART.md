# Server Module Quickstart

The **Server** module is the core of the `mcp_dart` package, providing the infrastructure to build Model Context Protocol (MCP) servers. It allows you to expose tools, resources, and prompts to MCP clients through various transport layers.

This module is owned by the `mcp_dart` package. For a CLI-driven workflow (creating, serving, and inspecting servers), refer to the [mcp_dart_cli](../../packages/mcp_dart_cli/README.md) package.

## 1. Setup

To create an MCP server, initialize an `McpServer` with implementation metadata and connect it to a transport.

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  // 1. Define server metadata
  final serverInfo = Implementation(
    name: 'my-custom-server',
    version: '1.0.0',
  );

  // 2. Initialize the server
  final server = McpServer(serverInfo);

  // 3. Register features (see below)
  
  // 4. Connect to a transport (e.g., Standard I/O)
  final transport = StdioServerTransport();
  await server.connect(transport);
}
```

## 2. Registering Features

### Tools
Tools are callable functions with defined input schemas.

```dart
server.registerTool(
  'calculate_sum',
  description: 'Calculates the sum of two numbers',
  inputSchema: const ToolInputSchema(
    properties: {
      'a': JsonSchema(type: 'number', description: 'First number'),
      'b': JsonSchema(type: 'number', description: 'Second number'),
    },
    required: ['a', 'b'],
  ),
  callback: (args, extra) async {
    final a = args['a'] as num;
    final b = args['b'] as num;
    
    return CallToolResult(
      content: [TextContent(text: 'Result: ${a + b}')],
    );
  },
);
```

### Resources
Resources provide read-only data (text or binary) accessible via URIs.

#### Fixed Resources
```dart
server.registerResource(
  'Application Config',
  'file:///config.json',
  (description: 'Static app configuration', mimeType: 'application/json'),
  (uri, extra) async {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: '{"theme": "dark", "notifications": true}',
        ),
      ],
    );
  },
);
```

#### Resource Templates
Templates allow dynamic URI matching with variables.

```dart
server.registerResourceTemplate(
  'Log Files',
  ResourceTemplateRegistration(
    'file:///logs/{date}.log',
    listCallback: (extra) async => ListResourcesResult(
      resources: [
        Resource(uri: 'file:///logs/2026-03-28.log', name: 'Today\'s Logs'),
      ],
    ),
  ),
  (description: 'Daily log files', mimeType: 'text/plain'),
  (uri, variables, extra) async {
    final date = variables['date'] as String;
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: 'Log entries for $date...',
        ),
      ],
    );
  },
);
```

### Prompts
Prompts are reusable templates for generating LLM messages.

```dart
server.registerPrompt(
  'greet_user',
  description: 'Generates a personalized greeting',
  argsSchema: {
    'name': const PromptArgumentDefinition(
      description: 'The user\'s name',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final name = args!['name'] as String;
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Hello $name, how can I assist you?'),
        ),
      ],
    );
  },
);
```

## 3. Transports

The server supports multiple transport layers depending on your deployment environment.

### Standard I/O (Stdio)
Best for servers invoked directly by a host (like an IDE or local LLM agent).

```dart
await server.connect(StdioServerTransport());
```

### Server-Sent Events (SSE)
Allows connecting via HTTP.

```dart
// Using the managed helper for multiple sessions
final sseServer = StreamableMcpServer(
  serverFactory: (sessionId) => McpServer(serverInfo)..registerTool(...),
  port: 8080,
);
await sseServer.start();
```

## 4. Advanced Usage

### Task Support (Experimental)
The server supports the experimental Tasks capability for long-running operations.

```dart
server.experimental.registerToolTask(
  'long_job',
  handler: MyTaskHandler(), // Implements ToolTaskHandler
);
```

### Error Handling
Use `McpError` and standard `ErrorCode` values to report issues to clients.

```dart
throw McpError(ErrorCode.invalidParams.value, 'Missing parameter X');
```

## 5. Integration with CLI

The `mcp_dart_cli` package provides powerful tools for developers:
- **`mcp_dart serve`**: Run your server project with auto-restart.
- **`mcp_dart inspect`**: Test your server by manually invoking its tools and resources.
- **`mcp_dart doctor`**: Verify server connectivity and configuration.

Refer to the [CLI README](../../packages/mcp_dart_cli/README.md) for full details.
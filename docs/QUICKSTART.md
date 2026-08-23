# Package Entry Points Quickstart

The **Package Entry Points** module is the primary interface for the **`mcp_dart`** package. It consolidates and exports the essential classes and utilities required to implement Model Context Protocol (MCP) clients and servers.

This module integrates with other packages like `mcp_dart_cli` to provide a robust environment for building MCP-compliant applications.

## 1. Import
```dart
import 'package:mcp_dart/mcp_dart.dart';
```

## 2. Setup
Instantiate an `McpServer` or an `McpClient` with the necessary `Implementation` details using the builder pattern for configuration.

```dart
import 'package:mcp_dart/mcp_dart.dart';

// Setup an MCP Server
final serverInfo = Implementation(
  name: 'my-mcp-server',
  version: '1.0.0',
);

final server = McpServer(
  serverInfo,
  options: const McpServerOptions(
    capabilities: ServerCapabilities(
      logging: {},
      prompts: ServerCapabilitiesPrompts(listChanged: true),
      resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
      tools: ServerCapabilitiesTools(listChanged: true),
    ),
    instructions: 'Follow these instructions to use the server.',
  ),
);

// Setup an MCP Client
final clientInfo = Implementation(
  name: 'my-mcp-client',
  version: '1.0.0',
);

final client = McpClient(
  clientInfo,
  options: const McpClientOptions(
    capabilities: ClientCapabilities(
      sampling: ClientCapabilitiesSampling(tools: ClientCapabilitiesSamplingTools()),
      roots: ClientCapabilitiesRoots(listChanged: true),
    ),
  ),
);
```

## 3. Server Operations

### Registering a Tool
Define and register a tool that connected clients can invoke. Tool names should follow the [SEP-986](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/986) specification.

```dart
server.registerTool(
  'greet',
  description: 'Greets a user',
  inputSchema: JsonObject(
    properties: {
      'name': JsonString(description: 'Name of the user'),
    },
    required: ['name'],
  ),
  callback: (args, extra) {
    final name = args['name'] as String;
    return CallToolResult(
      content: [TextContent(text: 'Hello, $name!')],
    );
  },
);
```

### Registering a Resource
Resources allow servers to expose data to clients.

```dart
server.registerResource(
  'Example Resource',
  'example://resource',
  (description: 'An example resource', mimeType: 'text/plain'),
  (uri, extra) {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: 'Resource content goes here.',
        ),
      ],
    );
  },
);
```

### Registering a Prompt
Prompts are templates that clients can use to generate LLM inputs.

```dart
server.registerPrompt(
  'summarize',
  description: 'Summarizes given text',
  argsSchema: {
    'text': const PromptArgumentDefinition(
      description: 'The text to summarize',
      required: true,
    ),
  },
  callback: (args, extra) {
    final text = args?['text'] ?? '';
    return GetPromptResult(
      description: 'Summary prompt',
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Please summarize: $text'),
        ),
      ],
    );
  },
);
```

## 4. Client Operations

### Connecting via Stdio
Start and connect an MCP client to a local server process over standard input/output.

```dart
Future<void> connectClient(McpClient client) async {
  final clientParams = StdioServerParameters(
    command: 'dart',
    args: ['run', 'bin/server.dart'],
  );

  final transport = StdioClientTransport(clientParams);
  await client.connect(transport);
}
```

### Calling a Tool
Invoke a registered tool from the client and process the result.

```dart
Future<void> callGreetTool(McpClient client) async {
  final result = await client.callTool(
    CallToolRequest(
      name: 'greet',
      arguments: {'name': 'World'},
    ),
  );

  for (final content in result.content) {
    if (content is TextContent) {
      print(content.text);
    }
  }
}
```

### Handling Sampling Requests
If the client advertises `sampling` capabilities, it should handle requests from the server to generate LLM completions.

```dart
client.onSamplingRequest = (params) async {
  // Integrate with your preferred LLM provider here
  return CreateMessageResult(
    model: 'my-llm-model',
    role: SamplingMessageRole.assistant,
    content: SamplingTextContent(text: 'Generated completion based on ${params.messages.length} messages.'),
    stopReason: StopReason.endTurn,
  );
};
```

## 5. Transport Configuration

### Streamable HTTP Server
Establish an MCP server over HTTP using `StreamableHTTPServerTransport`.

```dart
import 'dart:io';

Future<void> startHttpServer(McpServer server) async {
  final transportOptions = StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
    keepAliveInterval: 25, // Recommended SSE keep-alive interval
  );
  
  final transport = StreamableHTTPServerTransport(options: transportOptions);

  final httpServer = await HttpServer.bind('localhost', 8080);
  httpServer.listen((request) {
    if (request.uri.path == '/mcp') {
      transport.handleRequest(request);
    }
  });
}
```

## 6. Configuration Classes
- **`McpServerOptions`**: Configures `capabilities` and `instructions` for the server.
- **`McpClientOptions`**: Configures `capabilities` like `sampling`, `roots`, or `elicitation`.
- **`StdioServerParameters`**: Specifies process details (`command`, `args`, `environment`, `workingDirectory`) for stdio communication.
- **`StreamableHTTPServerTransportOptions`**: Manages `sessionIdGenerator`, `eventStore` for resumability, and DNS rebinding protection.

## 7. Package Integration
The **`mcp_dart`** package is designed to work seamlessly with:
- **`mcp_dart_cli`**: Provides a CLI for testing and running MCP servers.
- **`shelf_mcp_adapter`**: (If applicable) Integration with the `shelf` package for more complex HTTP routing.

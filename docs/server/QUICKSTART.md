# Server Module Quickstart

## 1. Overview
The **Server** module of `mcp_dart` provides a comprehensive framework for building Model Context Protocol (MCP) servers in Dart. It includes a high-level `McpServer` API for registering tools, prompts, resources, and tasks, alongside robust transport implementations (`StdioServerTransport`, `SseServerTransport`, and `StreamableHTTPServerTransport`) to expose your server over standard I/O or HTTP.

### Owning Package
This module is owned by the core **`mcp_dart`** package. It is designed to be the foundation for any MCP server implementation in the Dart ecosystem and integrates with `mcp_dart_cli` for project scaffolding.

## 2. Import
Import the server components and types directly from the `mcp_dart` package:

```dart
import 'package:mcp_dart/mcp_dart.dart';
// or explicitly import the server module and types:
import 'package:mcp_dart/src/server/module.dart';
import 'package:mcp_dart/src/types.dart';
```

## 3. Basic Setup
To create an MCP server, instantiate an `McpServer` with your implementation details and desired capabilities, then connect it to a transport.

```dart
import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  // 1. Initialize the server with basic information and capabilities
  final server = McpServer(
    Implementation(
      name: 'my-mcp-server', 
      version: '1.0.0',
      description: 'A sample MCP server built with Dart',
    ),
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
      ),
    ),
  );

  // 2. Register features (see sections below)
  // server.registerTool(...);

  // 3. Connect the server to standard input/output
  final transport = StdioServerTransport();
  await server.connect(transport);
  
  print('Server is running and listening on stdin...');
}
```

## 4. Registering Features

### Registering a Tool
Tools allow clients to perform actions. Use `registerTool` to define the tool name, description, and the execution callback.

```dart
server.registerTool(
  'calculate_sum',
  description: 'Calculates the sum of two numbers',
  inputSchema: ToolInputSchema(
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
      content: [TextContent(text: 'The sum is ${a + b}')],
    );
  },
);
```

### Registering a Prompt
Prompts are templated messages. Use `registerPrompt` to define arguments and a callback that returns messages.

```dart
server.registerPrompt(
  'greet',
  description: 'Generates a greeting for the user',
  argsSchema: {
    'userName': PromptArgumentDefinition(
      description: 'The name of the user',
      required: true,
      type: String,
    ),
  },
  callback: (args, extra) {
    final name = args?['userName'] as String;
    return GetPromptResult(
      description: 'A friendly greeting',
      messages: [
        PromptMessage(
          role: Role.assistant,
          content: TextContent(text: 'Hello, $name! How can I assist you today?'),
        ),
      ],
    );
  },
);
```

### Registering Resources
Resources are read-only data sources. You can register fixed resources or resource templates.

#### Fixed Resource
```dart
server.registerResource(
  'Server Logs',
  'mcp://logs/current',
  (description: 'Current system logs', mimeType: 'text/plain'),
  (uri, extra) async {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'text/plain',
          text: 'System started at ${DateTime.now()}\nAll systems nominal.',
        ),
      ],
    );
  },
);
```

#### Resource Template
```dart
server.registerResourceTemplate(
  'User Profile',
  ResourceTemplateRegistration(
    'mcp://users/{userId}/profile',
    listCallback: (extra) async {
      // Logic to list available users
      return ListResourcesResult(resources: []);
    },
  ),
  (description: 'Dynamic user profile resource', mimeType: 'application/json'),
  (uri, variables, extra) async {
    final userId = variables['userId'];
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: '{"id": "$userId", "name": "User $userId"}',
        ),
      ],
    );
  },
);
```

## 5. Advanced Features

### Completions
Enable auto-completion for prompt arguments or resource templates by providing `completable` fields.

```dart
server.registerPrompt(
  'search_docs',
  argsSchema: {
    'category': PromptArgumentDefinition(
      required: true,
      completable: CompletableField(
        def: CompletableDef(
          complete: (value) async => ['API', 'Guide', 'Examples'].where((s) => s.startsWith(value)).toList(),
        ),
      ),
    ),
  },
  callback: (args, extra) => GetPromptResult(messages: []),
);
```

### Experimental Tasks
The `experimental` namespace provides support for long-running tasks.

```dart
server.experimental.registerToolTask(
  'long_running_job',
  description: 'A task that takes time to complete',
  handler: MyTaskHandler(), // Implements ToolTaskHandler
);

// In your ToolTaskHandler.createTask:
// Use extra.sessionId to track user sessions if needed.
```

### Server-Sent Notifications
Notify clients of changes in real-time.

```dart
server.sendLoggingMessage(
  LoggingMessageNotification(
    level: LoggingLevel.info,
    logger: 'mcp_server',
    data: 'System heartbeat detected',
  ),
);

// Notify that the tool list has changed
server.sendToolListChanged();
```

## 6. Hosting over HTTP (SSE)
Use `StreamableMcpServer` for hosting over HTTP with Server-Sent Events (SSE) support.

```dart
final httpServer = StreamableMcpServer(
  serverFactory: (sessionId) {
    return McpServer(
      Implementation(name: 'http-server', version: '1.0.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    )..registerTool('ping', callback: (args, extra) => CallToolResult(content: []));
  },
  host: '0.0.0.0',
  port: 8080,
  enableDnsRebindingProtection: true,
  allowedHosts: {'myserver.com', 'localhost'},
);

await httpServer.start();
```

## 7. Configuration Reference

### `McpServerOptions`
- `capabilities`: Define what your server supports (`tools`, `prompts`, `resources`, `logging`, `tasks`, `elicitation`, `completions`).
- `instructions`: Optional string provided to the client during initialization to describe server usage.
- `enforceStrictCapabilities`: If true, the server validates that clients support requested features.

### `StreamableHTTPServerTransportOptions`
- `maxBodySize`: Limits the size of incoming POST requests (default 10MB).
- `keepAliveInterval`: Frequency of SSE keep-alive comments (default 25s).
- `enableJsonResponse`: If true, returns direct JSON responses instead of SSE streams for simple requests.
- `eventStore`: Provide an implementation of `EventStore` to enable SSE resumability.

## 8. Integration with other Packages
- **`mcp_dart_cli`**: Use the CLI to quickly generate a production-ready server scaffold.
- **Shelf**: Use `ShelfHttpAdapter` to integrate the MCP server into an existing `shelf` pipeline.

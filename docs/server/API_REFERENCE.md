# Server Module API Reference

## Package Context

The **Server** module is a core part of the `mcp_dart` package. It provides a robust, type-safe implementation of the Model Context Protocol (MCP) server-side specifications.

- **Owning Package:** `mcp_dart`
- **Integration:** This module is designed to work with any `Transport` implementation. It provides built-in support for Standard I/O (stdio), Server-Sent Events (SSE), and Streamable HTTP. It integrates natively with the `shelf` ecosystem for flexible web server deployment.
- **Related Packages:** The `mcp_dart_cli` package utilizes this module to provide a command-line interface for running and testing MCP servers.

---

## 1. Core Server Classes

### McpServer

The `McpServer` class is the high-level API for creating and managing an MCP server. It simplifies the registration of resources, tools, and prompts and handles the underlying JSON-RPC protocol.

#### Example: Basic Server Setup

```dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'package:mcp_dart/src/server/stdio.dart';

void main() async {
  // 1. Define server information
  final serverInfo = Implementation(
    name: 'example-server',
    version: '1.0.0',
  );

  // 2. Create the server with options
  final server = McpServer(
    serverInfo,
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        logging: {},
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
        tools: ServerCapabilitiesTools(listChanged: true),
      ),
    ),
  );

  // 3. Register a tool
  server.registerTool(
    'echo',
    description: 'Echoes the input message',
    inputSchema: const ToolInputSchema(
      properties: {
        'message': JsonSchema(type: 'string', description: 'The message to echo'),
      },
      required: ['message'],
    ),
    callback: (args, extra) async {
      final message = args['message'] as String;
      return CallToolResult(
        content: [TextContent(text: 'Echo: $message')],
      );
    },
  );

  // 4. Connect to a transport (e.g., Stdio)
  final transport = StdioServerTransport();
  await server.connect(transport);
  
  print('Server started on Stdio');
}
```

#### Methods

- `registerResource(String name, String uri, ResourceMetadata? metadata, ReadResourceCallback readCallback)`: Registers a fixed resource.
- `registerResourceTemplate(String name, ResourceTemplateRegistration template, ResourceMetadata? metadata, ReadResourceTemplateCallback readCallback)`: Registers a parameterized resource template.
- `registerTool(String name, {String? title, String? description, ToolInputSchema? inputSchema, ToolOutputSchema? outputSchema, ToolAnnotations? annotations, Map<String, dynamic>? meta, required ToolFunction callback})`: Registers an executable tool.
- `registerPrompt(String name, {String? title, String? description, Map<String, PromptArgumentDefinition>? argsSchema, required PromptCallback callback})`: Registers a prompt template.
- `connect(Transport transport)`: Connects the server to a communication transport.
- `close()`: Gracefully shuts down the server and its transport.
- `sendLoggingMessage(LoggingMessageNotification params, {String? sessionId})`: Sends a log notification to the client.
- `elicitInput(ElicitRequest params, [RequestOptions? options])`: Requests interactive input from the client (Form mode).

---

### McpServerOptions

Configuration options for the `McpServer`.

| Field | Type | Description |
| :--- | :--- | :--- |
| `capabilities` | `ServerCapabilities?` | The MCP capabilities advertised by this server. |
| `instructions` | `String?` | Human-readable instructions for LLMs on how to use this server. |
| `enforceStrictCapabilities` | `bool` | If true, the server will reject requests for unsupported capabilities. |

---

### StreamableMcpServer

A high-level server implementation specifically designed for the **Streamable HTTP** transport. It manages multiple sessions (connections) automatically.

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) {
    return McpServer(
      Implementation(name: 'multi-session-server', version: '1.0.0'),
    )..registerTool('ping', callback: (args, extra) async {
      return CallToolResult(content: [TextContent(text: 'pong')]);
    });
  },
  host: '0.0.0.0',
  port: 8080,
);

await server.start();
```

---

## 2. Transports

### StdioServerTransport

The standard transport for MCP servers running as sub-processes. It uses `stdin` for receiving and `stdout` for sending messages.

```dart
final transport = StdioServerTransport();
await server.connect(transport);
```

### SseServerTransport & SseServerManager

Used for Server-Sent Events (SSE) communication. This requires an HTTP server to handle the initial GET request and subsequent POST messages.

```dart
final sseManager = SseServerManager(
  mcpServer,
  ssePath: '/sse',
  messagePath: '/messages',
);

// Integration with dart:io HttpServer
final httpServer = await HttpServer.bind('localhost', 3000);
httpServer.listen(sseManager.handleRequest);
```

### StreamableHTTPServerTransport

Implements the **Streamable HTTP** transport specification, supporting both SSE streaming and direct JSON responses. It is highly flexible and works with both `dart:io` and `shelf`.

#### Shelf Integration Example

```dart
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
  ),
);

// Shelf handler
Future<Response> handler(Request request) async {
  if (request.url.path == 'mcp') {
    return await transport.handleShelfRequest(request);
  }
  return Response.notFound('Not Found');
}

await io.serve(handler, 'localhost', 8080);
```

---

## 3. Experimental Task Support

The `experimental` field on `McpServer` provides access to task-based tool execution. This is useful for long-running operations that require intermediate user feedback or multi-step processing.

### Registering a Task Tool

```dart
server.experimental.registerToolTask(
  'long_running_job',
  description: 'A job that takes time and asks for input',
  handler: MyTaskHandler(), // Implements ToolTaskHandler
);
```

### ToolTaskHandler Interface

To support tasks, implement the `ToolTaskHandler` interface:

| Method | Description |
| :--- | :--- |
| `createTask(args, extra)` | Initiates the task and returns a `CreateTaskResult`. |
| `getTask(taskId, extra)` | Returns the current status of the task (`Task`). |
| `cancelTask(taskId, extra)` | Aborts a running task. |
| `getTaskResult(taskId, extra)` | Retrieves the final `CallToolResult` upon completion. |

---

## 4. Key Types (Protobuf Derived)

All types follow Dart camelCase naming conventions for fields. Use the cascade operator (`..`) for clean construction of complex results.

### CallToolResult

The result returned by tool implementations. Use the `structuredContent` field for JSON-serializable data and `content` for human-readable or multimodal output.

```dart
return CallToolResult(
  isError: false,
  content: [
    TextContent(text: 'Operation successful'),
    ImageContent(
      data: 'base64_encoded_image',
      mimeType: 'image/png',
    ),
  ],
  structuredContent: {
    'totalItems': 42,
    'status': 'success',
  },
);
```

### Content Parts

Tool results and prompt messages are composed of one or more `Content` parts.

| Type | Class | Description |
| :--- | :--- | :--- |
| **Text** | `TextContent` | Plain text output. |
| **Image** | `ImageContent` | Base64 encoded image data with a `mimeType`. |
| **Audio** | `AudioContent` | Base64 encoded audio data with a `mimeType`. |
| **Resource** | `EmbeddedResource` | An embedded `ResourceContents` object. |
| **Link** | `ResourceLink` | A reference to an external resource by URI. |

### ResourceContents

When a resource is read, it returns one or more `ResourceContents` parts.

- `TextResourceContents`: Contains a `text` string.
- `BlobResourceContents`: Contains a base64 encoded `blob`.

### JsonSchema

The `mcp_dart` package provides a lightweight `JsonSchema` class for defining tool input and output structures.

```dart
const schema = JsonSchema(
  type: 'object',
  properties: {
    'query': JsonSchema(type: 'string', description: 'Search query'),
    'limit': JsonSchema(type: 'integer', defaultValue: 10),
  },
  required: ['query'],
);
```

### ResourceMetadata

Used when registering resources to provide context.

```dart
const metadata = (
  description: 'The primary system log file',
  mimeType: 'text/plain',
);
```

### ToolAnnotations

Hints provided to clients about tool behavior. All fields use **camelCase**.

```dart
const annotations = ToolAnnotations(
  title: 'Safe Delete',
  readOnlyHint: false,
  destructiveHint: true,
  idempotentHint: false,
  priority: 0.8,
);
```

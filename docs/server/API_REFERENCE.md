# Server API Reference

This module provides the server-side implementation of the Model Context Protocol (MCP) for the **mcp_dart** package. It is designed to be highly pluggable, supporting various transport layers and integration with other packages in the workspace, such as **mcp_dart_cli**.

## Multi-Package Structure

The MCP Dart workspace is organized into multiple packages:
- **mcp_dart** (Core): Contains the core protocol, client, and server implementations. This is the package that owns this "Server" module.
- **mcp_dart_cli** (`packages/mcp_dart_cli/`): A command-line interface that uses this server module to easily bootstrap and run MCP servers.

### Integration with mcp_dart_cli

The `mcp_dart_cli` package leverages the classes defined in this module (especially `McpServer` and `StreamableMcpServer`) to provide features like `mcp_dart serve`, which can automatically host an MCP server over SSE or Stdio based on configuration.

---

## 1. Core Server API

### McpServer

The `McpServer` class is the primary entry point for creating an MCP server. It provides high-level methods for registering tools, resources, and prompts.

#### Example: Basic Server Setup

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = McpServer(
    Implementation(
      name: "ExampleServer",
      version: "1.0.0",
    ),
  );

  // Register a simple tool
  // The client can invoke this tool with a 'message' argument.
  server.registerTool(
    "echo",
    description: "Echoes the input back to the client",
    inputSchema: ToolInputSchema(
      properties: {
        "message": JsonSchema.string(description: "The message to echo"),
      },
      required: ["message"],
    ),
    callback: (args, extra) async {
      final message = args["message"] as String;
      return CallToolResult(
        content: [TextContent(text: "Echo: $message")],
      );
    },
  );

  // Register a static resource
  // This resource will be available at the URI 'mcp://config'.
  server.registerResource(
    "config",
    "mcp://config",
    (description: "Server configuration", mimeType: "application/json"),
    (uri, extra) async {
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            text: '{"status": "ok"}',
            mimeType: "application/json",
          ),
        ],
      );
    },
  );

  // Connect via Stdio
  final transport = StdioServerTransport();
  await server.connect(transport);
}
```

#### Key Fields
- `experimental` (**ExperimentalMcpServerTasks**): Access to experimental task-related features.
- `isConnected` (**bool**): Whether the server is currently connected to a transport.
- `onError` (**void Function(Error)?**): Global error handler for the server.

#### Key Methods
- `connect(Transport transport)`: Attaches the server to a transport (e.g., Stdio, SSE).
- `close()`: Gracefully shuts down the server and its connection.
- `registerTool(...)`: Registers a tool that clients can call. Uses `ToolInputSchema` for argument validation.
- `registerResource(...)`: Registers a static resource accessible by URI.
- `registerResourceTemplate(...)`: Registers a dynamic resource pattern using URI templates.
- `registerPrompt(...)`: Registers a prompt that can be used for LLM interaction.
- `sendLoggingMessage(...)`: Sends a notification to the client with a log entry.
- `sendResourceListChanged()`: Notifies clients that the list of available resources has changed.
- `sendToolListChanged()`: Notifies clients that the list of available tools has changed.
- `sendPromptListChanged()`: Notifies clients that the list of available prompts has changed.
- `elicitInput(...)`: Requests structured user input from the client using form mode.

### McpServerOptions

Configuration options passed to the `McpServer` constructor.

```dart
const options = McpServerOptions(
  capabilities: ServerCapabilities(
    logging: {},
    prompts: ServerCapabilitiesPrompts(listChanged: true),
    resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
    tools: ServerCapabilitiesTools(listChanged: true),
  ),
  instructions: "Use the 'echo' tool to test connectivity.",
);
```

- `capabilities`: Defines what MCP features this server supports.
- `instructions`: Human-readable text for the client on how to use this server.

---

## 2. High-Level Servers

### StreamableMcpServer

A complete HTTP server implementation that handles multiple concurrent sessions using the Streamable HTTP transport.

```dart
final server = StreamableMcpServer(
  host: 'localhost',
  port: 3000,
  serverFactory: (sessionId) {
    return McpServer(
      Implementation(name: "HostedServer", version: "1.0.0"),
    );
  },
);

await server.start();
```

- `start()`: Binds the HTTP server and starts listening for connections.
- `stop()`: Closes the HTTP server and all active session transports.
- `enableDnsRebindingProtection`: Security feature to prevent DNS rebinding attacks.

### SseServerManager

Used for managing SSE (Server-Sent Events) connections manually, typically when integrating with an existing `dart:io` `HttpServer`.

---

## 3. Transports

Transports define how the MCP JSON-RPC messages are moved between client and server.

- **StdioServerTransport**: Communicates over standard input/output. Ideal for local processes managed by an IDE or CLI.
- **SseServerTransport**: Uses a persistent GET request for server-to-client events and separate POST requests for client-to-server messages.
- **StreamableHTTPServerTransport**: Implements the Model Context Protocol's "Streamable HTTP" specification, supporting both SSE and direct JSON responses.

---

## 4. Tasks (Experimental)

The experimental Tasks API allows servers to handle long-running operations that might require intermediate client interaction (like user input or model sampling).

### ExperimentalMcpServerTasks

Access this via `server.experimental`.

- `registerToolTask(...)`: Registers a tool that returns a task instead of an immediate result.
- `onListTasks(callback)`: Handler for when the client requests a list of tasks.
- `onCancelTask(callback)`: Handler for task cancellation.

### ToolTaskHandler

Interface for implementing task-based tools.

```dart
class MyLongRunningTask implements ToolTaskHandler {
  @override
  Future<CreateTaskResult> createTask(Map<String, dynamic>? args, RequestHandlerExtra? extra) async {
    // Start background work...
    return CreateTaskResult(
      task: Task(
        taskId: "task-123",
        status: TaskStatus.working,
        statusMessage: "Starting processing...",
      ),
    );
  }

  @override
  Future<Task> getTask(String taskId, RequestHandlerExtra? extra) async {
    // Return current status...
  }

  // ... other methods ...
}
```

---

## 5. Common Enums

The server implementation uses several enums to represent states and configurations.

- **TaskStatus**: Used in the Task API to track execution state (`working`, `inputRequired`, `completed`, `failed`, `cancelled`).
- **SamplingMessageRole**: Defines the sender of a message in sampling (`user`, `assistant`).
- **IncludeContext**: Options for including server context in sampling (`none`, `thisServer`, `allServers`).
- **StopReason**: Reason why LLM sampling might stop (`endTurn`, `stopSequence`, `maxTokens`).

---

## 6. HTTP Adapters

To remain framework-agnostic, the server uses adapters for HTTP requests/responses.

- **HttpAdapter** / **HttpResponseAdapter**: Interfaces for request/response handling.
- **DartIoHttpAdapter**: For `dart:io` native `HttpServer`.
- **ShelfHttpAdapter**: For the `shelf` middleware ecosystem.

---

## 6. Registration Types & Schemas

### RegisteredTool

When you call `registerTool`, it returns a `RegisteredTool` instance that allows you to manage the tool's lifecycle.

- `enable()` / `disable()`: Control whether the tool is visible to clients.
- `remove()`: Unregister the tool from the server.
- `update(...)`: Dynamically change the tool's metadata or callback.

### ToolInputSchema

Defines the parameters a tool accepts using JSON Schema.

```dart
final schema = ToolInputSchema(
  properties: {
    "count": JsonSchema.integer(minimum: 1),
    "apiKey": JsonSchema.string(format: "password"),
  },
  required: ["count"],
);
```

---

## 7. Sampling & Elicitation

Servers can request information back from the client during request processing.

### CreateMessageRequest (Sampling)

Request an LLM completion from the client's configured model.

```dart
final samplingResult = await server.server.createMessage(
  CreateMessageRequest(
    messages: [
      SamplingMessage(
        role: SamplingMessageRole.user,
        content: SamplingTextContent(text: "What is the weather?"),
      ),
    ],
    maxTokens: 100,
  ),
);
```

### ElicitRequest (Elicitation)

Request specific structured input from the user.

```dart
final userInput = await server.elicitInput(
  ElicitRequest.form(
    message: "Please provide your username",
    requestedSchema: ElicitationInputSchema(
      properties: {
        "username": JsonSchema.string(),
      },
      required: ["username"],
    ),
  ),
);
```

---

*Note: This documentation covers the Server-specific aspects of the MCP SDK. For shared types like `JsonSchema`, `TextContent`, and `ImageContent`, please refer to the Shared API Reference.*

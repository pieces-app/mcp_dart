# Server Module API Reference

The **Server** module is the core of the `mcp_dart` package's server-side implementation. It provides the high-level API for defining MCP tools, resources, and prompts, as well as the underlying transport layers and protocol handling.

This module is a foundational component of the `mcp_dart` workspace and is utilized by:
- **mcp_dart_cli** (`packages/mcp_dart_cli/`): Employs this module to provide the `serve` and `inspect` commands for running and debugging MCP servers.

## 1. Core Server API

### **McpServer**
The primary entry point for creating an MCP server. It manages the registration of capabilities and handles the JSON-RPC lifecycle.

*   **Constructors**:
    *   `McpServer(Implementation serverInfo, {McpServerOptions? options})`
*   **Properties**:
    *   `bool isConnected`: Returns true if the server is currently attached to a transport.
    *   `ExperimentalMcpServerTasks experimental`: Access to task-management features (sampling, elicitation).
*   **Methods**:
    *   `Future<void> connect(Transport transport)`: Connects the server to a transport (Stdio, SSE, etc.) and starts the initialization handshake.
    *   `Future<void> close()`: Disconnects the transport and cleans up resources.
    *   `RegisteredTool registerTool(...)`: Registers a tool that the client can invoke.
    *   `RegisteredResource registerResource(...)`: Registers a static resource.
    *   `RegisteredResourceTemplate registerResourceTemplate(...)`: Registers a dynamic resource pattern.
    *   `RegisteredPrompt registerPrompt(...)`: Registers a prompt for the client to use.
    *   `void sendToolListChanged()`: Notifies the client that the tool list has been updated.

#### **Example: Creating a simple server**
```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final server = McpServer(
    Implementation(name: 'ExampleServer', version: '1.0.0'),
  );

  // Register a simple tool
  server.registerTool(
    'echo',
    description: 'Echoes back the input',
    inputSchema: ToolInputSchema(
      properties: {
        'message': JsonSchema.string(description: 'The message to echo'),
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

  // Connect via Stdio
  final transport = StdioServerTransport();
  await server.connect(transport);
}
```

### **McpServerOptions**
Configuration for the `McpServer`.
*   **Fields**:
    *   `ServerCapabilities? capabilities`: Explicitly define supported capabilities (e.g., logging, tools, resources).
    *   `String? instructions`: Optional instructions for the client on how to use the server.
    *   `bool enforceStrictCapabilities`: Whether to strictly validate incoming requests against advertised capabilities.

---

## 2. Transport Layers

The Server module supports multiple transport mechanisms to adapt to different environments.

### **StdioServerTransport**
Standard I/O transport, typically used when the server process is managed directly by an MCP client.
*   **Example**:
    ```dart
    final transport = StdioServerTransport();
    await server.connect(transport);
    ```

### **SseServerTransport** / **SseServerManager**
Server-Sent Events transport for web-friendly communication.
*   **SseServerManager**: Manages multiple SSE connections and routes POST messages to the correct sessions.
*   **Example**:
    ```dart
    final manager = SseServerManager(mcpServer);
    final server = await HttpServer.bind('localhost', 8080);
    server.listen(manager.handleRequest);
    ```

### **StreamableHTTPServerTransport**
Implements the MCP **Streamable HTTP** specification. Supports both SSE streaming and direct JSON responses for environments where persistent connections might be interrupted.
*   **Options**: `StreamableHTTPServerTransportOptions`
    *   `sessionIdGenerator`: Callback to generate unique session IDs.
    *   `enableJsonResponse`: If true, prefers JSON responses over SSE.
    *   `keepAliveInterval`: Interval (in seconds) for SSE keep-alive messages (default: 25).

---

## 3. Resource & Prompt Registration

### **RegisteredResource**
*   **Fields**: `name`, `uri`, `metadata`, `enabled`.
*   **Methods**: `update(...)`, `remove()`, `enable()`, `disable()`.

### **RegisteredResourceTemplate**
*   **Fields**: `resourceTemplate`, `metadata`, `enabled`.
*   **Methods**: `update(...)`, `remove()`.

### **RegisteredPrompt**
*   **Fields**: `name`, `title`, `description`, `argsSchemaDefinition`, `enabled`.
*   **Methods**: `update(...)`, `remove()`.

---

## 4. Task Management (Experimental)

The server supports long-running "Tasks" which allow for asynchronous execution and intermediate interaction with the client via sampling or elicitation.

### **ToolTaskHandler** (Abstract)
Interface for tools that implement task-based logic.
*   `createTask(args, extra)`: Initiates a task.
*   `getTask(taskId, extra)`: Checks task status.
*   `getTaskResult(taskId, extra)`: Retrieves final output.

### **TaskSession**
Provides a task-specific context for interacting with the client.
*   `elicit(message, schema)`: Ask the user for specific input.
*   `createMessage(messages, maxTokens)`: Request LLM sampling from the client.

#### **Example: Task with Elicitation**
```dart
class MyTaskHandler implements ToolTaskHandler {
  @override
  Future<CreateTaskResult> createTask(Map<String, dynamic>? args, RequestHandlerExtra? extra) async {
    // ... logic to start a background process ...
    return CreateTaskResult(
      task: Task(
        taskId: 'task-123',
        status: TaskStatus.working,
      ),
    );
  }
  // ... implement other methods ...
}
```

---

## 5. HTTP Adapters

To support both `dart:io` and the `shelf` framework, the server uses an adapter pattern.

*   **HttpAdapter**: Common interface for HTTP requests.
*   **HttpResponseAdapter**: Common interface for HTTP responses.
*   **Implementations**:
    *   `DartIoHttpAdapter`: Wraps `HttpRequest` from `dart:io`.
    *   `ShelfHttpAdapter`: Wraps `Request` from the `shelf` package.

---

## 6. Helper Types & Constants

### **Typedefs**
*   **`ToolFunction`**: `FutureOr<CallToolResult> Function(Map<String, dynamic> args, RequestHandlerExtra extra)`
*   **`PromptCallback`**: `FutureOr<GetPromptResult> Function(Map<String, dynamic>? args, RequestHandlerExtra? extra)`
*   **`ReadResourceCallback`**: `FutureOr<ReadResourceResult> Function(Uri uri, RequestHandlerExtra extra)`

### **Constants**
*   `relatedTaskMetaKey`: Used in `meta` maps to link a result to a `taskId`.
*   `taskNameKey`: Metadata key for the original tool name in a task.
*   `taskInputKey`: Metadata key for the original arguments in a task.

### **Naming Conventions**
All Dart accessors for MCP types use `camelCase`, even though the underlying JSON protocol uses `snake_case`:
*   Use `taskId`, NOT `task_id`
*   Use `maxTokens`, NOT `max_tokens`
*   Use `inputSchema`, NOT `input_schema`

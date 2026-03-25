# Shared Module API Reference

The **Shared** module provides foundational components for the Model Context Protocol (MCP) in Dart. It handles core logic that is platform-agnostic or commonly used by both client and server implementations, including transport abstraction, protocol framing, JSON Schema validation, and task management.

## Owning Package: `mcp_dart`

This module is owned by the [**mcp_dart**](../../README.md) package. It serves as the primary protocol layer and is used extensively by other packages in the ecosystem.

### Integration across Packages

- **`mcp_dart` (Core)**: Provides the base classes (`Protocol`, `Transport`) and utilities (`JsonSchema`, `UriTemplateExpander`) used by the Client and Server implementations.
- **`mcp_dart_cli` (CLI Package)**: Utilizes the shared `IOStreamTransport` to implement its command-line interface, enabling standard I/O communication between the CLI tool and other MCP-compatible systems.

---

## 1. Transport Layer

The transport layer defines how JSON-RPC messages are moved between a client and a server.

### `Transport` (Interface)
Describes the minimal contract for an MCP transport.

*   **Fields**:
    *   `onclose: void Function()?` - Callback when the connection closes.
    *   `onerror: void Function(Error)?` - Callback when an error occurs.
    *   `onmessage: void Function(JsonRpcMessage)?` - Callback when a message is received.
    *   `sessionId: String?` - The unique session ID (if applicable).
*   **Methods**:
    *   `start() -> Future<void>` - Starts processing messages.
    *   `send(JsonRpcMessage message, {int? relatedRequestId}) -> Future<void>` - Sends a message.
    *   `close() -> Future<void>` - Closes the transport.

### `IOStreamTransport`
A concrete implementation of `Transport` that uses standard input and output streams.

*   **Example**:
    ```dart
    import 'dart:io';
    import 'package:mcp_dart/mcp_dart.dart';

    final transport = IOStreamTransport(
      stream: stdin,
      sink: stdout,
    );
    await transport.start();
    ```

---

## 2. Protocol Layer

The protocol layer implements MCP framing, request/response linking, and notification handling.

### `Protocol` (Abstract Class)
Handles the core JSON-RPC message flow. Concrete subclasses like `McpClient` and `McpServer` implement specific capabilities.

*   **Key Methods**:
    *   `connect(Transport transport) -> Future<void>` - Attaches to a transport and starts listening.
    *   `request<T>(...) -> Future<T>` - Sends a request and awaits a response.
    *   `notification(...) -> Future<void>` - Sends a one-way notification.
    *   `requestStream<T>(...) -> Stream<TaskStreamMessage>` - Sends a request and yields updates (often used with tasks).
    *   `setRequestHandler<ReqT>(...)` - Registers a handler for incoming requests.
    *   `setNotificationHandler<NotifT>(...)` - Registers a handler for incoming notifications.

### `ProtocolOptions`
Configuration for the protocol handler.

*   **Fields**:
    *   `enforceStrictCapabilities: bool` - Whether to restrict requests based on advertised capabilities.
    *   `debouncedNotificationMethods: List<String>?` - Methods to automatically debounce.
    *   `taskStore: TaskStore?` - Optional task storage.
    *   `taskMessageQueue: TaskMessageQueue?` - Optional task message queue.
    *   `defaultTaskPollInterval: int?` - Polling interval for task status checks.
    *   `maxTaskQueueSize: int?` - Limit for queued task messages.

### `RequestOptions`
Per-request configuration.

*   **Fields**:
    *   `onprogress: ProgressCallback?` - Callback for progress updates.
    *   `signal: AbortSignal?` - Signal to cancel the request.
    *   `timeout: Duration?` - Request timeout.
    *   `resetTimeoutOnProgress: bool` - Whether progress resets the timeout timer.
    *   `task: TaskCreation?` - Parameters for creating a task.
    *   `relatedTask: RelatedTaskMetadata?` - Associates the request with an existing task.

### `RequestHandlerExtra`
Context provided to request handlers.

*   **Example**:
    ```dart
    server.setRequestHandler<JsonRpcCallToolRequest>(
      Method.toolsCall,
      (request, extra) async {
        // Send progress updates back to the client
        await extra.sendProgress(0.5, message: 'Processing...');
        
        // Access metadata or session info
        print('Session ID: ${extra.sessionId}');
        
        return CallToolResult(content: [TextContent(text: 'Success')]);
      },
      (id, params, meta) => JsonRpcCallToolRequest.fromJson({'id': id, 'params': params, '_meta': meta}),
    );
    ```

---

## 3. Task Management

Interfaces and classes for long-running operations.

### `TaskStore`
Interface for storing and retrieving task states.

### `Task`
Represents a task and its current status.

*   **Fields**:
    *   `taskId: String`
    *   `status: TaskStatus` (`working`, `inputRequired`, `completed`, `failed`, `cancelled`)
    *   `statusMessage: String?`
    *   `ttl: int?`
    *   `pollInterval: int?`
    *   `createdAt: String?`
    *   `lastUpdatedAt: String?`

---

## 4. JSON Schema Utilities

A type-safe builder for creating JSON Schemas used in tool definitions and data validation.

### `JsonSchema` (Builder)
*   **Example**:
    ```dart
    final schema = JsonSchema.object(
      properties: {
        'batchId': JsonSchema.string(description: 'Unique batch identifier'),
        'mailSettings': JsonSchema.object(
          properties: {
            'sandboxMode': JsonSchema.boolean(defaultValue: false),
          },
        ),
        'ipPoolName': JsonSchema.string(),
        'replyToList': JsonSchema.array(items: JsonSchema.string()),
      },
      required: ['batchId'],
    );
    ```

### Supported Types
*   `JsonString`: `minLength`, `maxLength`, `pattern`, `format`, `enumValues`.
*   `JsonNumber` / `JsonInteger`: `minimum`, `maximum`, `multipleOf`.
*   `JsonBoolean`, `JsonNull`.
*   `JsonArray`: `items`, `minItems`, `maxItems`, `uniqueItems`.
*   `JsonObject`: `properties`, `required`, `additionalProperties`.
*   Logical: `JsonAllOf`, `JsonAnyOf`, `JsonOneOf`, `JsonNot`.

### Validation
Available via the `JsonSchemaValidation` extension.
```dart
try {
  schema.validate({'batchId': '123'});
} catch (e) {
  print('Validation failed: $e');
}
```

---

## 5. URI Templates

### `UriTemplateExpander`
Parses and expands RFC 6570 URI Templates.

*   **Example**:
    ```dart
    final expander = UriTemplateExpander('/search{?q,lang}');
    final uri = expander.expand({'q': 'mcp', 'lang': 'dart'});
    // Result: /search?q=mcp&lang=dart
    ```

---

## 6. General Utilities

*   **`generateUUID()`**: Generates an RFC4122 version 4 UUID.
*   **`validateToolName(String name)`**: Validates a tool name against the MCP specification (SEP-986).
*   **`Logger`**: Internal logging utility.
    ```dart
    final logger = Logger('MyLogger');
    logger.info('Protocol started');
    ```
*   **`AbortController` / `AbortSignal`**: For cancelling asynchronous operations.
    ```dart
    final controller = BasicAbortController();
    // Later...
    controller.abort('User cancelled');
    ```

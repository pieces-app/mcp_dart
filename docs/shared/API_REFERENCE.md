# mcp_dart: Shared Module API Reference

The **Shared** module is the foundational core of the `mcp_dart` ecosystem, providing the essential infrastructure for implementing the Model Context Protocol (MCP). It defines the base protocol framing, transport abstractions, and shared data models used by both clients and servers.

## 1. Package Architecture

### Owning Package: `mcp_dart`
- **Location:** `lib/src/shared/`
- **Core Role:** Provides the foundational protocol logic, transport interfaces, and common utilities (logging, URI templates, JSON Schema).

### Sub-package Integration: `mcp_dart_cli`
- **Location:** `packages/mcp_dart_cli/`
- **Integration:** The CLI package relies extensively on the Shared module's `Protocol` and `Transport` abstractions to communicate with MCP servers. It specifically uses `StdioClientTransport` (an implementation of the `Transport` interface) and handles connection lifecycles via the shared protocol logic.

---

## 2. Core Protocol Infrastructure

The protocol layer handles the serialization, deserialization, and lifecycle of JSON-RPC messages.

### Protocol

The `Protocol` class is an abstract implementation of MCP framing. It manages request-response pairing, notification handling, and transport integration.

**Key Fields:**
- `transport`: The currently attached `Transport?`.
- `onclose`: Callback for when the transport closes.
- `onerror`: Callback for protocol or transport errors.
- `fallbackRequestHandler`: Handles requests without a specific registered handler.
- `fallbackNotificationHandler`: Handles notifications without a specific registered handler.

**Principal Methods:**
- `Future<void> connect(Transport transport)`: Attaches to and starts the given transport.
- `Future<void> close()`: Closes the connection by closing the underlying transport.
- `Future<T> request<T extends BaseResultData>(JsonRpcRequest requestData, T Function(Map<String, dynamic> resultJson) resultFactory, [RequestOptions? options, int? relatedRequestId])`: Sends a request and waits for a typed response.
- `Future<void> notification(JsonRpcNotification notificationData, {RelatedTaskMetadata? relatedTask, int? relatedRequestId})`: Sends a one-way notification.
- `Stream<TaskStreamMessage> requestStream<T extends BaseResultData>(JsonRpcRequest requestData, T Function(Map<String, dynamic> resultJson) resultFactory, [RequestOptions? options])`: Specialized helper for tracking long-running tasks as a stream of updates.
- `void setRequestHandler<ReqT extends JsonRpcRequest>(String method, Future<BaseResultData> Function(ReqT request, RequestHandlerExtra extra) handler, ReqT Function(RequestId id, Map<String, dynamic>? params, Map<String, dynamic>? meta) requestFactory)`: Registers a handler for a specific method name.
- `void setNotificationHandler<NotifT extends JsonRpcNotification>(String method, Future<void> Function(NotifT notification) handler, NotifT Function(Map<String, dynamic>? params, Map<String, dynamic>? meta) notificationFactory)`: Registers a notification handler.

**Example: Sending a Request**
```dart
final result = await protocol.request<ToolsListResult>(
  JsonRpcListToolsRequest(id: 1),
  (json) => ToolsListResult.fromJson(json),
  RequestOptions(timeout: Duration(seconds: 30)),
);
```

### Transport

An interface defining the contract for message delivery. Concrete implementations like `IOStreamTransport` or `StdioClientTransport` provide the actual communication channel.

- `Future<void> start()`: Initializes the connection and starts listening for data.
- `Future<void> send(JsonRpcMessage message, {int? relatedRequestId})`: Sends a framed message to the peer.
- `Future<void> close()`: Tears down the connection and cleans up resources.
- `void Function(JsonRpcMessage message)? onmessage`: Callback invoked when a message is received.
- `String? sessionId`: Unique identifier for the connection (if applicable).

### IOStreamTransport

A concrete implementation of `Transport` using standard Dart `Stream<List<int>>` and `StreamSink<List<int>>`. It is typically used for communication over pipes or network sockets.

**Fields:**
- `stream`: The input stream to read from.
- `sink`: The output sink to write to.

**Example: Using Socket Transport**
```dart
final socket = await Socket.connect('localhost', 8080);
final transport = IOStreamTransport(
  stream: socket.asBroadcastStream(),
  sink: socket,
);
await protocol.connect(transport);
```

---

## 3. Options & Configuration

### ProtocolOptions

Initial configuration for a protocol instance.
- `enforceStrictCapabilities`: Whether to validate remote capabilities before sending requests.
- `debouncedNotificationMethods`: List of methods that should be automatically debounced.
- `taskStore`: Optional implementation of `TaskStore` for long-running task support.
- `taskMessageQueue`: Optional queue for side-channel task messages.
- `defaultTaskPollInterval`: Default interval (ms) for status checks.
- `maxTaskQueueSize`: Cap for queued messages per task.

### RequestOptions

Per-request tuning parameters.
- `onprogress`: A `ProgressCallback` that receives updates from the peer.
- `signal`: An `AbortSignal` used to cancel an in-flight request.
- `timeout`: Maximum wait time for a response (defaults to 60s).
- `resetTimeoutOnProgress`: If enabled, each progress update resets the request timeout timer.
- `maxTotalTimeout`: Hard upper limit for the total request duration, regardless of progress.
- `task`: Augments the request with `TaskCreation` parameters.
- `relatedTask`: Associates the request with an existing task.

### RequestHandlerExtra

Provides additional context and capabilities to request handlers during execution.

**Fields:**
- `signal`: `AbortSignal` indicating if the request was cancelled by the client.
- `sessionId`: The session ID from the transport.
- `requestId`: The ID of the current request.
- `meta`: Metadata from the original request.
- `taskId`: Associated task ID (if any).
- `taskStore`: `RequestTaskStore` for managing the associated task.

**Methods:**
- `Future<void> sendProgress(double progress, {double? total, String? message})`: Sends a progress notification back to the client.

**Example: Handling a Long-Running Request**
```dart
Future<BaseResultData> myHandler(JsonRpcRequest request, RequestHandlerExtra extra) async {
  // Send progress back to the caller
  await extra.sendProgress(0.5, message: 'Processing...');
  
  // Check if the request was cancelled
  if (extra.signal.aborted) {
    throw McpError(ErrorCode.invalidRequest.value, 'Request aborted by client');
  }
  
  return const EmptyResult();
}
```

---

## 4. Abortion & Signal Handling

The module provides a robust mechanism for request and task cancellation using `AbortSignal` and `AbortController`.

- **AbortController**: Used to trigger the abortion of a signal.
- **AbortSignal**: Passed into operations to monitor for cancellation via the `aborted` flag or `onAbort` stream.
- **AbortError**: A specialized `Error` thrown when an operation is cancelled.
- **BasicAbortController**: The standard implementation used throughout the SDK.

**Example: Triggering Cancellation**
```dart
final controller = BasicAbortController();

// Send request with signal
final future = protocol.request(
  requestData,
  resultFactory,
  RequestOptions(signal: controller.signal),
);

// Trigger cancellation if needed
controller.abort('User clicked cancel');
```

---

## 5. JSON Schema Builder

The module includes a comprehensive, type-safe builder for JSON Schemas, essential for defining tool parameters and resource schemas.

### JsonSchema (Sealed Class)

Use the static factory methods to create typed schemas:

- `JsonSchema.string({int? minLength, int? maxLength, String? pattern, ...})`
- `JsonSchema.number({num? minimum, num? maximum, ...})`
- `JsonSchema.integer({int? minimum, int? maximum, ...})`
- `JsonSchema.boolean()`
- `JsonSchema.nullValue()`
- `JsonSchema.object({Map<String, JsonSchema>? properties, List<String>? required, ...})`
- `JsonSchema.array({JsonSchema? items, int? minItems, ...})`
- `JsonSchema.oneOf(List<JsonSchema> schemas)`
- `JsonSchema.anyOf(List<JsonSchema> schemas)`
- `JsonSchema.allOf(List<JsonSchema> schemas)`
- `JsonSchema.not(JsonSchema schema)`

**Example: Defining a Tool Schema**
```dart
final schema = JsonSchema.object(
  properties: {
    'count': JsonSchema.integer(minimum: 1, defaultValue: 10),
    'mode': JsonSchema.string(enumValues: ['fast', 'slow']),
    'metadata': JsonSchema.object(additionalProperties: true),
  },
  required: ['count'],
);

final map = schema.toJson(); // Standard JSON Schema map
```

---

## 6. Task Management Interfaces

Task interfaces allow for the implementation of side-channel communication and long-lived operations that outlive a single request-response cycle.

- **TaskStore**: Interface for persisting task state, metadata, and results.
- **TaskMessageQueue**: Manages delivery of out-of-band messages (requests/notifications) related to a task.
- **Task**: Data model representing a task, including its `taskId`, `status`, and `pollInterval`.
- **TaskStatus**: Enum for task states: `working`, `inputRequired`, `completed`, `failed`, `cancelled`.
- **QueuedMessage**: A message (`JsonRpcMessage`) waiting in the task queue.

---

## 7. Utilities & Helpers

### UriTemplateExpander

A robust RFC 6570 compliant URI template engine used for resource and prompt templates.

```dart
final expander = UriTemplateExpander('/projects/{projectId}/files/{+path}{?version}');

// Expansion
final uri = expander.expand({
  'projectId': 'abc-123',
  'path': 'src/main.dart',
  'version': '1.0'
}); 
// Result: /projects/abc-123/files/src/main.dart?version=1.0

// Matching
final matches = expander.match('/projects/my-id/files/README.md');
print(matches?['projectId']); // my-id
```

### ToolNameValidation

Ensures that tool names conform to the MCP standard (limited to `[A-Za-z0-9._-]`, maximum 128 characters).

- `validateToolName(String name)`: Returns a `ToolNameValidationResult` with an `isValid` flag and a list of `warnings`.
- `validateAndWarnToolName(String name)`: Validates the name and automatically logs warnings to the internal logger if formatting issues are found.

### ReadBuffer (Stdio Handling)

Used by stdio-based transports to safely buffer and parse discrete JSON-RPC messages from a continuous binary stream.
- `append(Uint8List chunk)`: Adds data to the buffer.
- `readMessage()`: Attempts to extract a complete, newline-terminated `JsonRpcMessage`.
- `maxBufferSize`: Default limit of 10MB to prevent memory exhaustion.

### Logger

A simple, pluggable logging system used throughout the module.

- `Logger.setHandler(LogHandler handler)`: Redirects all logs to a custom destination (e.g., a file or a CLI console).
- `LogLevel`: Enum with `debug`, `info`, `warn`, and `error`.

---

## 8. Global Functions & Types

- **`generateUUID()`**: Generates an RFC 4122 compliant version 4 UUID.
- **`mergeCapabilities(base, additional)`**: Deep merges two capability maps, preserving nested structures.
- **`deserializeMessage(String line)`**: Parses a single JSON line into a `JsonRpcMessage`.
- **`serializeMessage(JsonRpcMessage message)`**: Converts a message to a newline-terminated JSON string.
- **`writeLog(String message)`**: Cross-platform log writer (uses `stderr` on native, `print` on web).
- **`ProgressToken`**: A `dynamic` type (typically `int` or `String`) used to identify a progress stream.
- **`RequestId`**: A `dynamic` type (typically `int` or `String`) used for JSON-RPC request IDs.

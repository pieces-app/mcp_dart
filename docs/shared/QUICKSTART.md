# Shared Module Quickstart

The **Shared** module is the foundational layer of the `mcp_dart` ecosystem. It provides the essential primitives for implementing the Model Context Protocol (MCP), including JSON-RPC protocol handling, transport abstractions, type-safe JSON schema building, and cross-platform utilities.

## Package Context
- **Owning Package:** `mcp_dart`
- **Integration:** This module is the core dependency for both `mcp_dart` (Client/Server) and the `mcp_dart_cli` package. It ensures that protocol logic and validation rules remain consistent across all implementations.

## 1. Import
The module provides both standard IO and web-compatible entry points.

```dart
// Standard IO-compatible components (includes IOStreamTransport)
import 'package:mcp_dart/src/shared/module.dart';

// Web-compatible components (excludes dart:io dependencies)
import 'package:mcp_dart/src/shared/module_web.dart';

// Specific utilities and types
import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/protocol.dart';
import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/uri_template.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
```

## 2. Core Transport: IOStream
`IOStreamTransport` allows MCP communication over standard input and output streams. This is the primary transport for local MCP servers.

```dart
import 'dart:io';
import 'package:mcp_dart/src/shared/iostream.dart';

final transport = IOStreamTransport(
  stream: stdin,
  sink: stdout,
);

// The transport is typically started by the Client or Server connect() method.
```

## 3. Protocol Configuration
The `Protocol` class handles the JSON-RPC lifecycle and can be customized using `ProtocolOptions`.

```dart
import 'package:mcp_dart/src/shared/protocol.dart';

final options = ProtocolOptions(
  // Restrict requests to advertised capabilities
  enforceStrictCapabilities: true,
  // Automatically debounce specific notifications
  debouncedNotificationMethods: ['notifications/progress'],
  // Default polling for task status (ms)
  defaultTaskPollInterval: 1000,
  // Maximum messages to queue per task
  maxTaskQueueSize: 100,
);
```

### Request-Level Control
Use `RequestOptions` to manage timeouts and track operation progress.

```dart
final requestOptions = RequestOptions(
  timeout: Duration(seconds: 45),
  // Note: onprogress is used for progress notification callbacks
  onprogress: (progress) {
    print('Progress: ${progress.progress * 100}% - ${progress.message ?? ""}');
  },
);
```

## 4. Type-Safe JSON Schema
The `JsonSchema` builder provides a fluent API for defining MCP-compatible validation rules.

```dart
final searchSchema = JsonSchema.object(
  title: 'SearchParameters',
  description: 'Parameters for the search tool',
  properties: {
    'query': JsonSchema.string(
      description: 'The search term',
      minLength: 1,
    ),
    'limit': JsonSchema.integer(
      description: 'Maximum results to return',
      minimum: 1,
      maximum: 100,
      defaultValue: 10,
    ),
  },
  required: ['query'],
);

// Convert to JSON for registration
final jsonRepresentation = searchSchema.toJson();
```

## 5. Advanced Features

### Cancellable Requests
Use `AbortController` to cancel in-flight requests gracefully.

```dart
import 'package:mcp_dart/src/shared/protocol.dart';

final controller = BasicAbortController();
final options = RequestOptions(signal: controller.signal);

// Call a tool with the cancellation signal
client.callTool('heavy_task', {}, options);

// Later, if needed:
controller.abort('Operation no longer required');
```

### Request Streams (Tasks)
For long-running operations that support progress and status updates, use `requestStream`.

```dart
final stream = client.requestStream(
  JsonRpcRequest(
    method: 'tools/call',
    params: {'name': 'generate_report', 'arguments': {...}},
  ),
  (json) => CallToolResult.fromJson(json),
  RequestOptions(task: TaskCreation(ttl: 3600)),
);

await for (final message in stream) {
  if (message is TaskCreatedMessage) {
    print('Task ID: ${message.task.taskId}');
  } else if (message is TaskStatusMessage) {
    print('Status: ${message.task.status.name}');
  } else if (message is TaskResultMessage) {
    print('Completed: ${message.result}');
  }
}
```

### Progress Reporting
Inside request handlers, use `RequestHandlerExtra` to send updates back to the client.

```dart
Future<BaseResultData> handleRequest(JsonRpcRequest request, RequestHandlerExtra extra) async {
  // Send a progress notification if the client requested it
  await extra.sendProgress(0.5, message: 'Processing data...');
  
  // ... perform work ...
  
  return const EmptyResult();
}
```

## 6. Essential Utilities

### URI Template Expansion
```dart
final template = UriTemplateExpander('/files/{path}{?version}');
final uri = template.expand({'path': 'docs/readme.md', 'version': '2.0'});
// Result: /files/docs/readme.md?version=2.0
```

### Tool Name Validation
Ensure tool names conform to the MCP standard (SEP-986).

```dart
import 'package:mcp_dart/src/shared/tool_name_validation.dart';

// Validates against standard and issues warnings for non-conforming names
final isValid = validateAndWarnToolName('my_tool_v1');
```

### UUID Generation
```dart
import 'package:mcp_dart/src/shared/uuid.dart';

final id = generateUUID(); // Returns an RFC4122 v4 UUID string
```

### Global Logging
Configure how the entire MCP stack logs internal events.

```dart
Logger.setHandler((loggerName, level, message) {
  print('[$level][$loggerName] $message');
});
```

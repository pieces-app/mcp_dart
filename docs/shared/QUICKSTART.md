# Shared Module Quickstart

## 1. Overview

The **Shared** module is the foundational layer of the `mcp_dart` package. It provides the core primitives, protocol framing, and utilities used by both the [Client](../client/QUICKSTART.md) and [Server](../server/QUICKSTART.md) implementations.

### Package Ownership
This module is owned by the main **`mcp_dart`** package. It is designed to be platform-agnostic where possible, with specific entry points for standard Dart IO and Web environments.

### Integration
- **`mcp_dart`**: The root package uses these primitives to implement the full MCP stack.
- **`mcp_dart_cli`**: The CLI tool leverages the shared utilities (like `ToolNameValidation` and `UriTemplateExpander`) to inspect servers and validate configurations.

## 2. Import

Primary access to the shared module is through platform-specific exports:

```dart
// For standard Dart IO (Servers, CLI tools, Native clients)
import 'package:mcp_dart/mcp_dart.dart'; // Exports common utilities
import 'package:mcp_dart/src/shared/module.dart'; // Exports Transport, Protocol, etc.

// For Web-compatible applications
import 'package:mcp_dart/src/shared/module_web.dart';
```

Specific utilities can also be imported directly:

```dart
import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/uri_template.dart';
import 'package:mcp_dart/src/shared/tool_name_validation.dart';
```

## 3. Core Utilities

### Building and Validating JSON Schemas

The module provides a type-safe `JsonSchema` builder. Note that Dart properties use `camelCase`.

```dart
import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema_validator.dart';

void main() {
  // Define a complex schema using the builder pattern
  final schema = JsonSchema.object(
    required: ['productId', 'quantity'],
    properties: {
      'productId': JsonSchema.string(
        pattern: r'^[A-Z]{3}-\d{4}$',
        description: 'Format: AAA-1234',
      ),
      'quantity': JsonSchema.integer(minimum: 1, defaultValue: 1),
      'category': JsonSchema.string(
        enumValues: ['electronics', 'clothing', 'books'],
      ),
    },
  );

  final data = {
    'productId': 'LAP-9021',
    'quantity': 2,
    'category': 'electronics',
  };

  try {
    schema.validate(data);
    print('Schema validation passed!');
  } on JsonSchemaValidationException catch (e) {
    print('Validation error: ${e.message} at ${e.path.join("/")}');
  }
}
```

### Expanding URI Templates (RFC 6570)

The `UriTemplateExpander` is used for resource templates and prompt arguments.

```dart
import 'package:mcp_dart/src/shared/uri_template.dart';

void main() {
  final template = UriTemplateExpander('https://api.example.com/v1/users/{userId}/posts{?limit,sort}');
  
  final expanded = template.expand({
    'userId': '123',
    'limit': 10,
    'sort': 'desc',
  });
  
  print('Expanded URI: $expanded');
  // Output: https://api.example.com/v1/users/123/posts?limit=10&sort=desc
}
```

### Tool Name Validation

Ensures tool names comply with MCP specifications (SEP-986).

```dart
import 'package:mcp_dart/src/shared/tool_name_validation.dart';

void main() {
  const toolName = 'my_awesome-tool.v1';
  final result = validateToolName(toolName);
  
  if (result.isValid) {
    print('"$toolName" is a valid MCP tool name.');
  } else {
    for (final warning in result.warnings) {
      print('Warning: $warning');
    }
  }
}
```

### Generating UUIDs

A simple utility for generating RFC4122 compliant UUID (version 4) strings.

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() {
  final myId = generateUUID();
  print('Generated ID: $myId');
}
```

## 4. Transport & Protocol

### IOStreamTransport

The `IOStreamTransport` implements the `Transport` interface using standard I/O streams, which is the default for most MCP servers.

```dart
import 'dart:io';
import 'package:mcp_dart/src/shared/iostream.dart';

void main() async {
  final transport = IOStreamTransport(
    stream: stdin,
    sink: stdout,
  );

  // The transport is usually managed by a Client or Server instance
  // but can be started manually for custom protocol implementations.
  await transport.start();
  
  transport.onmessage = (message) {
    print('Received message: ${message.toJson()}');
  };
}
```

### Protocol Options

When initializing the protocol layer, you can configure various behaviors:

```dart
import 'package:mcp_dart/src/shared/protocol.dart';

const options = ProtocolOptions(
  enforceStrictCapabilities: true, // Validate requests against advertised capabilities
  defaultTaskPollInterval: 2000,   // Polling interval for tasks in ms
  maxTaskQueueSize: 100,           // Max messages per task queue
);
```

## 5. Global Logging

Logging is centralized and can be customized by providing a custom handler.

```dart
import 'package:mcp_dart/src/shared/logging.dart';

void setupLogging() {
  Logger.setHandler((loggerName, level, message) {
    final timestamp = DateTime.now().toIso8601String();
    // Redirect logs to stderr to avoid polluting stdout in MCP stdio servers
    stderr.writeln('[$timestamp] [${level.name.toUpperCase()}] [$loggerName] $message');
  });
}
```

## 6. Task Interfaces

The shared module defines the interfaces for long-running tasks:

- **`TaskStore`**: Interface for persisting task state and results.
- **`TaskMessageQueue`**: Interface for managing side-channel messages (notifications, progress) for active tasks.

Implement these interfaces if you need custom task persistence (e.g., using a database or Redis).

# Client Module Quickstart

## Package Context

### `mcp_dart` (Core Package)
This module is owned by the core `mcp_dart` package. It provides the foundational client capabilities required to connect to and interact with Model Context Protocol (MCP) servers.

### `mcp_dart_cli` (CLI Integration)
The Client module is utilized by the `mcp_dart_cli` sub-package to establish connections (typically via `StdioClientTransport`) and forward commands from the command line interface to MCP servers.

---

## 1. Overview

The Client module implements the MCP client specification, handling:
- **Initialization**: Protocol negotiation and capability exchange.
- **Transports**: Plug-in support for `stdio` and `http` (SSE).
- **RPC Methods**: Discovery and invocation of tools, resources, and prompts.
- **Handlers**: Client-side logic for sampling and elicitation requests.
- **Tasks**: Support for long-running, asynchronous operations.

## 2. Importing

```dart
// Core client implementation and transports
import 'package:mcp_dart/src/client/module.dart'; 

// Protocol types and message structures
import 'package:mcp_dart/src/types.dart'; 
```

*For web platforms, use `import 'package:mcp_dart/src/client/module_web.dart';` to avoid `dart:io` dependencies.*

## 3. Initialization & Setup

Instantiate an `McpClient` with your application details and desired capabilities.

```dart
final client = McpClient(
  Implementation(name: 'my-app', version: '1.0.0'),
  options: McpClientOptions(
    capabilities: ClientCapabilities(
      roots: ClientCapabilitiesRoots(listChanged: true),
      sampling: ClientCapabilitiesSampling(tools: ClientCapabilitiesSamplingTools()),
      elicitation: ClientElicitation.all(),
      tasks: ClientCapabilitiesTasks(
        cancel: true,
        list: true,
      ),
    ),
  ),
);

// Register handlers for server-initiated requests
client.onSamplingRequest = (params) async {
  return CreateMessageResult(
    role: 'assistant',
    content: TextContent(text: 'Hello from client sampling!'),
    model: 'gpt-4',
    stopReason: 'endTurn',
  );
};

client.onElicitRequest = (params) async {
  return ElicitResult(
    action: 'accept',
    content: {'user_confirmed': true},
  );
};
```

## 4. Transports

### Standard I/O (Local Subprocess)
```dart
import 'dart:io';

final transport = StdioClientTransport(
  StdioServerParameters(
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-everything'],
    stderrMode: ProcessStartMode.inheritStdio,
  ),
);

await transport.start();
await client.connect(transport);
```

### Streamable HTTP (Remote SSE)
```dart
final transport = StreamableHttpClientTransport(
  Uri.parse('https://mcp.example.com/sse'),
  opts: StreamableHttpClientTransportOptions(
    sessionId: 'optional-session-id',
  ),
);

await transport.start();
await client.connect(transport);
```

## 5. Core Operations

### Tool Operations
```dart
// List available tools
final toolsResult = await client.listTools();

// Call a tool
final callResult = await client.callTool(
  CallToolRequest(
    name: 'calculate_sum',
    arguments: {'a': 5, 'b': 10},
  ),
);
```

### Resource Operations
```dart
// List resources
final resources = await client.listResources();

// Read a specific resource
final content = await client.readResource(
  ReadResourceRequest(uri: 'file:///logs/today.log'),
);

// Subscribe to resource updates
await client.subscribeResource(
  SubscribeRequest(uri: 'file:///logs/today.log'),
);
```

### Prompt Operations
```dart
// List available prompts
final prompts = await client.listPrompts();

// Retrieve a templated prompt
final prompt = await client.getPrompt(
  GetPromptRequest(
    name: 'code_review',
    arguments: {'language': 'dart'},
  ),
);
```

### Autocompletion
```dart
final completions = await client.complete(
  CompleteRequest(
    ref: PromptReference(name: 'code_review'),
    argument: ArgumentCompletionInfo(name: 'language', value: 'da'),
  ),
);
```

### Logging & Utility
```dart
// Ping the server
await client.ping();

// Set server-side logging level
await client.setLoggingLevel(LoggingLevel.debug);

// Notify server that client roots have changed
await client.sendRootsListChanged();
```

## 6. Advanced: Task Management

Use the `TaskClient` for tools that support long-running task execution.

```dart
final taskClient = TaskClient(client);

final stream = taskClient.callToolStream(
  'expensive_operation',
  {'input': 'data'},
  task: {'ttl': 30000, 'pollInterval': 500},
);

await for (final event in stream) {
  if (event is TaskCreatedMessage) {
    print('Task started: ${event.task.taskId}');
  } else if (event is TaskStatusMessage) {
    print('Progress: ${event.task.progress}');
  } else if (event is TaskResultMessage) {
    print('Final result: ${event.result.structuredContent}');
  }
}
```

## 7. Configuration Reference

| Class | Key Fields | Purpose |
|-------|------------|---------|
| `McpClientOptions` | `capabilities`, `enforceStrictCapabilities` | Handshake config |
| `StdioServerParameters` | `command`, `args`, `workingDirectory`, `environment` | Spawning local servers |
| `StreamableHttpClientTransportOptions` | `authProvider`, `requestInit`, `reconnectionOptions` | HTTP/SSE config |
| `ClientCapabilities` | `roots`, `sampling`, `elicitation`, `tasks` | Feature advertisement |
| `RequestOptions` | `timeout`, `onProgress` | Per-request behavior |

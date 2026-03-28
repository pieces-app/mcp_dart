# MCP Client Quickstart

**Owning Package:** `mcp_dart`
*(Note: This module is the core client implementation. It is used by the `mcp_dart_cli` package located in `packages/mcp_dart_cli/` for its command-line features like `inspect` and `doctor`.)*

## 1. Overview

The Client module provides a robust, fully-featured implementation of the Model Context Protocol (MCP) client for Dart. It manages the connection lifecycle, handles the initialization handshake, and provides a strongly-typed API for interacting with an MCP server's features such as tools, prompts, resources, and tasks. It supports pluggable transports, including Standard I/O (stdio) for local server processes and Streamable HTTPS (SSE) for remote servers.

## 2. Import

Import the client module to access the `McpClient` and built-in transports:

```dart
import 'package:mcp_dart/src/client/module.dart';

// You will also likely need the shared types:
import 'package:mcp_dart/src/types.dart';
```

*(Note: For web-specific projects, import `package:mcp_dart/src/client/module_web.dart` instead. This module excludes `dart:io` dependencies such as the `StdioClientTransport`.)*

## 3. Setup

To get started, instantiate a transport and an `McpClient`, then connect them. 

### Connecting via Stdio (Local Process)

Use `StdioClientTransport` to launch and connect to a local MCP server via its standard input and output streams:

```dart
import 'dart:io';
import 'package:mcp_dart/src/client/module.dart';
import 'package:mcp_dart/src/types.dart';

void main() async {
  // 1. Define the transport parameters for the server process
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-everything'],
      stderrMode: ProcessStartMode.inheritStdio,
    ),
  );

  // 2. Initialize the client with basic implementation info and optional capabilities
  final client = McpClient(
    Implementation(name: 'my-dart-client', version: '1.0.0'),
    options: McpClientOptions(
      capabilities: ClientCapabilities(
        roots: ClientCapabilitiesRoots(listChanged: true),
        sampling: ClientCapabilitiesSampling(tools: true),
        elicitation: ClientElicitation.formOnly(),
        tasks: ClientCapabilitiesTasks(list: true, cancel: true),
      ),
    ),
  );

  // 3. Connect (this starts the process and performs the MCP handshake)
  await client.connect(transport);
  print('Connected to server: ${client.getServerVersion()?.name}');
}
```

### Connecting via Streamable HTTPS (Remote Server)

For web clients or connecting to remote servers, use `StreamableHttpClientTransport`:

```dart
final transport = StreamableHttpClientTransport(
  Uri.parse('https://api.example.com/mcp/sse'),
  opts: StreamableHttpClientTransportOptions(
    httpTimeout: Duration(seconds: 30),
    reconnectionOptions: StreamableHttpReconnectionOptions(
      maxRetries: 3,
      initialReconnectionDelay: 1000,
      maxReconnectionDelay: 30000,
      reconnectionDelayGrowFactor: 1.5,
    )
  ),
);

final client = McpClient(Implementation(name: 'my-web-client', version: '1.0.0'));
await client.connect(transport);
```

## 4. Common Operations

### Calling a Tool

Once connected, you can list the available tools on the server and execute them:

```dart
// List available tools
final toolsResult = await client.listTools();
for (final tool in toolsResult.tools) {
  print('Available tool: ${tool.name}');
}

// Call a specific tool
final result = await client.callTool(
  CallToolRequest(
    name: 'echo',
    arguments: {'message': 'Hello MCP!'},
  ),
);

if (result.isError) {
  print('Tool execution encountered an error.');
}

for (final content in result.content) {
  print(content.toJson());
}
```

### Handling Elicitation (User Input)

If you advertise the `elicitation` capability, you must provide a handler to process server requests for user input:

```dart
client.onElicitRequest = (request) async {
  print('Server requested input: ${request.message}');
  
  if (request.isFormMode) {
    // Prompt user for form data based on request.requestedSchema
    return ElicitResult(
      action: 'accept',
      content: {'user_name': 'John Doe'},
    );
  } else if (request.isUrlMode) {
    print('Please navigate to: ${request.url}');
    return ElicitResult(action: 'accept', elicitationId: request.elicitationId);
  }
  
  return ElicitResult(action: 'decline');
};
```

### Listing and Reading Resources

Resources allow clients to read file-like data provided by the server:

```dart
// List resources exposed by the server
final resources = await client.listResources();
for (final resource in resources.resources) {
  print('Resource URI: ${resource.uri}');
}

// Read a specific resource
final readResult = await client.readResource(
  ReadResourceRequest(uri: 'file:///path/to/resource.txt'),
);

for (final content in readResult.contents) {
  print('Content: ${content.toJson()}');
}
```

### Using TaskClient for Long-Running Tasks

For advanced task-augmented tools that execute asynchronously, wrap your client in a `TaskClient` to track and stream status updates:

```dart
final taskClient = TaskClient(client);

// Call a tool that supports tasks, passing task augmentation parameters
final stream = taskClient.callToolStream(
  'long_running_analysis',
  {'target': 'data.csv'},
  task: {'ttl': 60000}, 
);

await for (final message in stream) {
  if (message is TaskCreatedMessage) {
    print('Task created with ID: ${message.task.taskId}');
  } else if (message is TaskStatusMessage) {
    print('Task status: ${message.task.status}');
  } else if (message is TaskResultMessage) {
    print('Final result: ${message.result.toJson()}');
  } else if (message is TaskErrorMessage) {
    print('Task encountered an error: ${message.error}');
  }
}
```

## 5. Configuration

### `McpClientOptions`
Configures the client behavior, particularly the capabilities the client advertises during the handshake. Capabilities enable advanced features like:
- `elicitation` (`ClientElicitation`): Allows the server to prompt the client user for structured form or URL input.
- `sampling` (`ClientCapabilitiesSampling`): Allows the server to request LLM completions directly from the client.
- `roots` (`ClientCapabilitiesRoots`): Allows the client to manage and expose workspace roots.
- `tasks` (`ClientCapabilitiesTasks`): Enables task-based tools and background task execution.

### `StdioServerParameters`
Configures how the child server process is spawned by the `StdioClientTransport`:
- `command`: The executable to run (e.g., `node`, `python`, `npx`).
- `args`: Command-line arguments passed to the executable.
- `environment`: Custom environment variables (inherits parent environment by default).
- `stderrMode`: Controls how stderr is handled (e.g., `ProcessStartMode.inheritStdio` for passthrough printing, or `ProcessStartMode.normal` to read from the transport's `stderr` stream).

### `StreamableHttpClientTransportOptions`
Configures HTTP and Server-Sent Events behavior:
- `authProvider`: An `OAuthClientProvider` interface for automated token management, exchange, and refresh.
- `requestInit`: Custom headers to append to HTTP requests.
- `reconnectionOptions`: Tuning for exponential backoff during stream disconnects (`maxRetries`, `initialReconnectionDelay`, etc.).
- `httpTimeout`: Maximum duration to wait for HTTP requests before timing out.

## 6. Related Modules

- **Types (`package:mcp_dart/src/types.dart`)**: Contains all the JSON-RPC models, request/response objects, and data structures used extensively by the Client.
- **Shared Protocol (`package:mcp_dart/src/shared/protocol.dart`)**: The underlying `Protocol` class that `McpClient` extends, handling JSON-RPC message framing, promises, and routing.
- **Server (`package:mcp_dart/src/server/module.dart`)**: The counterpart to the Client module, providing the `McpServer` implementation for creating MCP servers.
- **CLI (`package:mcp_dart_cli`)**: A companion package that provides a command-line interface for interacting with and debugging MCP servers.
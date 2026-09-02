# Model Context Protocol (MCP) for Dart

This repository provides a comprehensive implementation of the [Model Context Protocol (MCP)](https://modelcontextprotocol.io), enabling seamless communication between AI models and local or remote resources.

## `mcp_dart` (Core Library)

The `mcp_dart` package is the core library containing the protocol logic, standard transports, and high-level APIs for building MCP clients and servers.

### 1. Overview
The **Package Entry Points** module serves as the primary gateway. It provides platform-aware exports, routing native environments (via `dart:io`) and web environments to their respective implementations.

### 2. Installation
Add `mcp_dart` to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_dart: ^1.2.0
```

### 3. Setup

#### McpServer Setup
```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final serverInfo = Implementation(
    name: 'sample-server',
    version: '1.0.0',
    description: 'A sample MCP server',
  );

  final server = McpServer(
    serverInfo,
    options: McpServerOptions(
      capabilities: ServerCapabilities(
        logging: {},
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
        tools: ServerCapabilitiesTools(listChanged: true),
      ),
    ),
  );

  // Connect via Stdio
  final transport = StdioServerTransport();
  await server.connect(transport);
}
```

#### McpClient Setup
```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final clientInfo = Implementation(name: 'sample-client', version: '1.0.0');
  final client = McpClient(
    clientInfo,
    options: McpClientOptions(
      capabilities: ClientCapabilities(
        roots: ClientCapabilitiesRoots(listChanged: true),
        sampling: ClientCapabilitiesSampling(tools: true, context: true),
      ),
    ),
  );

  // Connect via Stdio
  final transport = StdioClientTransport(
    StdioServerParameters(command: 'dart', args: ['run', 'bin/server.dart']),
  );
  await client.connect(transport);
}
```

### 4. Core Operations

#### Tools (Function Calling)
Servers can register tools that clients can discover and invoke.

```dart
// Server: Register a tool
server.registerTool(
  'calculate_sum',
  description: 'Adds two numbers',
  inputSchema: ToolInputSchema(
    properties: {
      'a': JsonNumber(description: 'First number'),
      'b': JsonNumber(description: 'Second number'),
    },
    required: ['a', 'b'],
  ),
  callback: (args, extra) async {
    final sum = (args['a'] as num) + (args['b'] as num);
    return CallToolResult(
      content: [TextContent(text: 'The sum is $sum')],
    );
  },
);

// Client: Call a tool
final result = await client.callTool(
  CallToolRequest(
    name: 'calculate_sum',
    arguments: {'a': 10, 'b': 20},
  ),
);
```

#### Resources (Data Access)
Resources allow servers to expose data (files, logs, database records) to models.

```dart
// Server: Register a static resource
server.registerResource(
  'System Logs',
  'mcp://logs/system',
  (description: 'Current system logs', mimeType: 'text/plain'),
  (uri, extra) async {
    return ReadResourceResult(
      contents: [TextResourceContents(uri: uri.toString(), text: 'System is running normally.')],
    );
  },
);

// Client: Read a resource
final logs = await client.readResource(ReadResourceRequest(uri: 'mcp://logs/system'));
```

#### Resource Templates
Templates allow servers to expose dynamic resources based on URI patterns (RFC 6570).

```dart
// Server: Register a resource template
server.registerResourceTemplate(
  'File Browser',
  ResourceTemplateRegistration(
    'file:///{path}',
    listCallback: (extra) async => ListResourcesResult(resources: []), // Optional: list matching resources
  ),
  (description: 'Browses local files', mimeType: 'text/plain'),
  (uri, variables, extra) async {
    final path = variables['path'] as String;
    return ReadResourceResult(
      contents: [TextResourceContents(uri: uri.toString(), text: 'Content of $path')],
    );
  },
);
```

#### Prompts (Templated Interaction)
Prompts allow servers to provide reusable instructions or conversation starters.

```dart
// Server: Register a prompt
server.registerPrompt(
  'review_code',
  description: 'Reviews a code snippet',
  argsSchema: {
    'code': PromptArgumentDefinition(description: 'The code to review', required: true),
  },
  callback: (args, extra) async {
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Please review this code:\n${args?['code']}'),
        ),
      ],
    );
  },
);

// Client: Get a prompt
final prompt = await client.getPrompt(
  GetPromptRequest(name: 'review_code', arguments: {'code': 'print("hello")'}),
);
```

#### Logging
Servers can send structured log messages to clients.

```dart
// Server: Send a log message
await server.sendLoggingMessage(
  LoggingMessageNotification(
    level: LoggingLevel.info,
    data: 'Process started successfully',
  ),
);

// Client: Adjust logging level
await client.setLoggingLevel(LoggingLevel.debug);
```

#### Roots (Workspace Access)
Roots allow clients to share specific file system paths (like workspace folders) with the server.

```dart
// Client: Inform server of available roots
// Typically handled automatically if roots capability is enabled.
await client.sendRootsListChanged();

// Server: List roots shared by the client
final roots = await server.listRoots();
for (final root in roots.roots) {
  print('Shared root: ${root.uri} (${root.name})');
}
```

#### Progress Notifications
Long-running operations can report progress back to the client.

```dart
// Server: Send progress updates
server.registerTool(
  'long_task',
  callback: (args, extra) async {
    await extra.sendProgress(0.5, total: 1.0, message: 'Halfway there...');
    // ... continue work
    return CallToolResult(content: [TextContent(text: 'Done')]);
  },
);

// Client: Receive progress updates
final result = await client.callTool(
  CallToolRequest(name: 'long_task'),
  options: RequestOptions(
    onprogress: (progress) {
      print('Progress: ${progress.progress}/${progress.total} - ${progress.message}');
    },
  ),
);
```

### 5. Advanced Features

#### Sampling (Model Interaction)
Clients can handle sampling requests from servers to perform LLM completions.

```dart
// Client: Handle sampling request
client.onSamplingRequest = (params) async {
  return CreateMessageResult(
    model: 'gpt-4o',
    role: SamplingMessageRole.assistant,
    content: SamplingTextContent(text: 'Generated text from client'),
    stopReason: StopReason.endTurn,
  );
};

// Server: Request sampling
final response = await server.createMessage(
  CreateMessageRequest(
    messages: [SamplingMessage(role: SamplingMessageRole.user, content: SamplingTextContent(text: 'Hello!'))],
    maxTokens: 100,
  ),
);
```

#### Elicitation (User Input)
Servers can request structured input from users via the client.

```dart
// Client: Handle elicitation
client.onElicitRequest = (params) async {
  // Show form to user...
  return ElicitResult(action: 'accept', content: {'key': 'value'});
};

// Server: Elicit input
final input = await server.elicitInput(
  ElicitRequest.form(
    message: 'Please provide configuration',
    requestedSchema: JsonObject(properties: {'key': JsonString()}),
  ),
);
```

#### Streamable HTTP (SSE) Server
For environments requiring HTTP-based communication (e.g., remote servers or web integrations), use `StreamableMcpServer`.

```dart
final server = StreamableMcpServer(
  serverFactory: (sessionId) {
    return McpServer(
      Implementation(name: 'web-server', version: '1.0.0'),
    )..registerTool(
        'hello',
        callback: (args, extra) async => CallToolResult(
          content: [TextContent(text: 'Hello from session $sessionId')],
        ),
      );
  },
  host: '0.0.0.0',
  port: 3000,
  path: '/mcp',
);

await server.start();
print('MCP Server listening on port ${server.port}');
```

### 6. Error Handling
Always handle `McpError` to catch protocol-level issues like timeouts or missing tools.

```dart
try {
  await client.callTool(CallToolRequest(name: 'unknown_tool'));
} on McpError catch (e) {
  print('Error ${e.code}: ${e.message}');
}
```

---

## `mcp_dart_cli` (Sub-package)

The `mcp_dart_cli` package provides command-line tools for managing MCP servers, including scaffolding and testing.

### Installation
```bash
dart pub global activate mcp_dart_cli
```

### Features
- **Scaffolding**: Quickly create new MCP server projects.
- **Validation**: Test server compliance with the Model Context Protocol.
- **Execution**: Run and monitor servers with built-in logging.

Refer to `packages/mcp_dart_cli/README.md` for detailed CLI documentation.

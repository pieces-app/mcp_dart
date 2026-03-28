# Package Entry Points Quickstart

The **Package Entry Points** module is the primary gateway to the Model Context Protocol (MCP) SDK for Dart. This module, owned by the core `mcp_dart` package, provides the essential interfaces for building MCP clients and servers, handling protocol handshakes, and managing various MCP capabilities.

## 1. Multi-Package Repository Structure

This workspace is a multi-package repository:
- **`mcp_dart`** (Root): The core SDK library providing protocol implementation, types, and transports.
- **`mcp_dart_cli`** (`packages/mcp_dart_cli/`): A command-line interface for creating, inspecting, and serving MCP servers built with `mcp_dart`.

## 2. Installation

Add `mcp_dart` to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_dart: ^1.0.0
```

## 3. Import

Import the main library to access all core MCP functionalities. The library automatically handles platform-specific exports for native (`dart:io`) and web environments.

```dart
import 'package:mcp_dart/mcp_dart.dart';
```

## 4. Basic Setup

MCP utilizes a client-server architecture where both sides exchange information about their implementation and capabilities during a handshake.

### Implementation Details
Define your implementation info using the `Implementation` class:

```dart
final clientInfo = Implementation(
  name: 'example-client',
  version: '1.0.0',
);

final serverInfo = Implementation(
  name: 'example-server',
  version: '1.0.0',
);
```

### Initializing Client and Server
Instantiate `McpClient` or `McpServer` with implementation details and optional configuration.

```dart
// Setup a Client
final client = McpClient(clientInfo);

// Setup a Server with specific capabilities and instructions
final server = McpServer(
  serverInfo,
  options: McpServerOptions(
    capabilities: const ServerCapabilities(
      logging: {},
      tools: ServerCapabilitiesTools(listChanged: true),
    ),
    instructions: 'Use this server to fetch weather data and manage tasks.',
  ),
);
```

## 5. Server Implementation

The `McpServer` class provides high-level methods to register various MCP features.

### Registering Tools
Tools allow clients (and LLMs) to perform actions.

```dart
server.registerTool(
  'get_weather',
  description: 'Fetches current weather for a location',
  inputSchema: JsonSchema.object(
    properties: {
      'city': JsonSchema.string(description: 'The city name'),
      'unit': JsonSchema.string(
        enumValues: ['celsius', 'fahrenheit'],
        defaultValue: 'celsius',
      ),
    },
    required: ['city'],
  ),
  callback: (args, extra) async {
    final city = args['city'] as String;
    final unit = args['unit'] as String;
    
    // Implementation logic here
    return CallToolResult(
      content: [TextContent(text: 'The weather in $city is 22° $unit.')],
    );
  },
);
```

### Registering Resources
Resources provide structured data or content to the client.

```dart
server.registerResource(
  'system_logs',
  'file:///var/log/system.log',
  const (description: 'Access to system log files', mimeType: 'text/plain'),
  (uri, extra) async {
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: 'Log entry: System started at 2026-03-28...',
        ),
      ],
    );
  },
);
```

### Registering Resource Templates
Resource templates use URI patterns (RFC 6570) to dynamically resolve resources.

```dart
server.registerResourceTemplate(
  'user_profile',
  ResourceTemplateRegistration(
    'users://{username}/profile',
    listCallback: (extra) async {
      return const ListResourcesResult(resources: []);
    },
  ),
  const (description: 'Dynamic user profile data', mimeType: 'application/json'),
  (uri, variables, extra) async {
    final username = variables['username'];
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          mimeType: 'application/json',
          text: '{"user": "$username", "status": "active"}',
        ),
      ],
    );
  },
);
```

### Registering Prompts
Prompts are templates for LLM interactions.

```dart
server.registerPrompt(
  'code_review',
  description: 'Reviews code for potential bugs and style issues',
  argsSchema: {
    'language': const PromptArgumentDefinition(
      description: 'The programming language',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final lang = args?['language'] ?? 'dart';
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: PromptMessageRole.user,
          content: TextContent(text: 'Please review this $lang code for me.'),
        ),
      ],
    );
  },
);
```

## 6. Client Operations

Establish a connection using a `Transport` and perform standard MCP requests.

### Connecting to a Server (Stdio)
```dart
Future<void> initClient() async {
  final transport = StdioClientTransport(
    StdioServerParameters(
      command: 'dart',
      args: ['run', 'bin/server.dart'],
    ),
  );

  await client.connect(transport);
  print('Connected to server: ${client.getServerVersion()?.name}');
}
```

### Calling a Tool
```dart
final result = await client.callTool(
  CallToolRequest(
    name: 'get_weather',
    arguments: {'city': 'San Francisco'},
  ),
);

if (!result.isError) {
  for (final item in result.content) {
    if (item is TextContent) print(item.text);
  }
}
```

### Listing and Reading Resources
```dart
// List available resources
final resources = await client.listResources();

// Read a specific resource
final content = await client.readResource(
  ReadResourceRequest(uri: 'file:///var/log/system.log'),
);
```

## 7. Advanced Features

### Tasks and Progress
MCP supports long-running tasks with progress notifications and cancellation.

```dart
// Server-side progress reporting
server.registerTool(
  'heavy_operation',
  callback: (args, extra) async {
    for (var i = 0; i <= 100; i += 20) {
      await Future.delayed(const Duration(seconds: 1));
      await extra.sendProgress(i.toDouble(), total: 100, message: 'Processing...');
    }
    return CallToolResult(content: [TextContent(text: 'Done!')]);
  },
);

// Client-side request with progress callback
final result = await client.callTool(
  CallToolRequest(name: 'heavy_operation'),
  options: RequestOptions(
    onprogress: (progress) {
      print('Progress: ${progress.progress}/${progress.total} - ${progress.message}');
    },
  ),
);
```

### Sampling (LLM-in-the-loop)
Servers can request the client to sample an LLM.

```dart
// Client-side setup for sampling
client.onSamplingRequest = (params) async {
  // Integrate with your LLM provider (e.g., OpenAI, Anthropic, Gemini)
  return CreateMessageResult(
    model: 'gpt-4',
    role: SamplingMessageRole.assistant,
    content: SamplingTextContent(text: 'This is a sample response.'),
    stopReason: StopReason.endTurn,
  );
};

// Server-side requesting sampling
final sample = await server.createMessage(
  CreateMessageRequest(
    messages: [
      SamplingMessage(
        role: SamplingMessageRole.user,
        content: SamplingTextContent(text: 'Explain MCP in one sentence.'),
      ),
    ],
    maxTokens: 100,
  ),
);
```

### Elicitation (User-in-the-loop)
Servers can request structured user input from the client.

```dart
// Server requesting input
final elicitationResult = await server.elicitInput(
  ElicitRequest.form(
    message: 'Please provide your API key:',
    requestedSchema: JsonSchema.string(title: 'API Key'),
  ),
);

if (elicitationResult.accepted) {
  print('User provided: ${elicitationResult.content}');
}
```

### Logging
MCP provides a standardized way for servers to send log messages to clients.

```dart
// Server sending a log message
await server.sendLoggingMessage(
  LoggingMessageNotification(
    level: LoggingLevel.info,
    logger: 'database_service',
    data: 'Connected to database successfully.',
  ),
);

// Client-side control of logging level
await client.setLoggingLevel(LoggingLevel.debug);
```

### Roots
Clients can expose "roots" (e.g., workspace folders) that the server can operate on.

```dart
// Server requesting the list of roots from the client
final rootsResult = await server.listRoots();
for (final root in rootsResult.roots) {
  print('Client root: ${root.uri} (${root.name})');
}

// Client notifying the server when roots change
await client.sendRootsListChanged();
```

## 8. Integration with `mcp_dart_cli`

The `mcp_dart_cli` package provides tools to facilitate the development lifecycle of `mcp_dart` servers:

- **Scaffolding**: Create new MCP server projects with `mcp_dart create`.
- **Debugging**: Inspect and test your server capabilities using `mcp_dart inspect`.
- **Deployment**: Serve your MCP server over various transports with `mcp_dart serve`.

For more details, refer to the [mcp_dart_cli documentation](../packages/mcp_dart_cli/README.md).

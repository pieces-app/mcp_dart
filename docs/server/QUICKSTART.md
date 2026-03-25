# Server Module Quickstart

The **Server** module provides the core implementation for building Model Context Protocol (MCP) servers in Dart. It handles the lifecycle of MCP connections, manages JSON-RPC message routing, and provides high-level APIs for registering tools, resources, and prompts.

## Multi-Package Repository Structure

This repository is organized as a multi-package workspace:

### mcp_dart (Core SDK)
The `mcp_dart` package contains the core Server, Client, and Shared modules. The Server module is defined here and provides the foundational logic for any Dart-based MCP server.

### mcp_dart_cli
Located in `packages/mcp_dart_cli/`, this package provides command-line utilities. It can be used to host or test servers built with the `mcp_dart` Server module.

---

## 1. Setup & Initialization

To build a server, instantiate `McpServer` with your implementation details and capabilities.

```dart
import 'package:mcp_dart/mcp_dart.dart';

Future<void> main() async {
  // 1. Initialize the MCP Server
  final server = McpServer(
    const Implementation(
      name: 'example_server', 
      version: '1.0.0',
      description: 'A comprehensive example server',
    ),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
        resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
        prompts: ServerCapabilitiesPrompts(listChanged: true),
        logging: {}, // Enable logging capability
      ),
    ),
  )
    // 2. Set global error handler using cascade notation
    ..onError = (error) => print('Server error: $error');

  // 3. Connect to a transport (stdio is standard for local MCP)
  final transport = StdioServerTransport();
  await server.connect(transport);
}
```

## 2. Registering Tools

Tools are executable functions exposed to the client.

```dart
server.registerTool(
  'calculate_bmi',
  description: 'Calculate Body Mass Index',
  inputSchema: JsonSchema.object(
    properties: {
      'weightKg': JsonSchema.number(description: 'Weight in kilograms'),
      'heightM': JsonSchema.number(description: 'Height in meters'),
    },
    required: ['weightKg', 'heightM'],
  ),
  callback: (args, extra) {
    final weight = args['weightKg'] as num;
    final height = args['heightM'] as num;
    final bmi = weight / (height * height);
    
    return CallToolResult(
      content: [TextContent(text: 'Your BMI is ${bmi.toStringAsFixed(2)}')],
    );
  },
);
```

### Task-Augmented Tools (Experimental)
For long-running operations, you can register a tool that returns a task ID and supports polling or notifications.

```dart
server.experimental.registerToolTask(
  'long_running_job',
  handler: MyTaskHandler(), // Implements ToolTaskHandler
);
```

## 3. Resources & Templates

Resources expose data (text or binary) to the client.

### Static Resources
```dart
server.registerResource(
  'system_logs',
  'file:///var/log/system.log',
  (description: 'Current system logs', mimeType: 'text/plain'),
  (uri, extra) async {
    return const ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: 'file:///var/log/system.log',
          text: 'Log entry 1: System started...',
          mimeType: 'text/plain',
        ),
      ],
    );
  },
);
```

### Resource Templates
Templates allow dynamic URI matching using RFC 6570 patterns.

```dart
server.registerResourceTemplate(
  'user_profile',
  ResourceTemplateRegistration(
    'users://{userId}/profile',
    listCallback: (extra) => const ListResourcesResult(resources: []),
  ),
  (description: 'User profile data', mimeType: 'application/json'),
  (uri, variables, extra) async {
    final userId = variables['userId'];
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: '{"userId": "$userId", "name": "John Doe"}',
          mimeType: 'application/json',
        ),
      ],
    );
  },
);
```

## 4. Prompts & Completions

Prompts provide reusable templates for generating LLM interactions.

```dart
server.registerPrompt(
  'code_review',
  description: 'Request a code review for a snippet',
  argsSchema: {
    'language': const PromptArgumentDefinition(
      description: 'Programming language',
      required: true,
    ),
  },
  callback: (args, extra) {
    final lang = args?['language'] as String;
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: Role.user,
          content: TextContent(text: 'Review this $lang code...'),
        ),
      ],
    );
  },
);
```

## 5. Server-Initiated Input (Elicitation)

Servers can request structured input from the client during tool execution or other operations.

```dart
final result = await server.elicitInput(
  ElicitRequest.form(
    message: 'Please provide your API key',
    requestedSchema: JsonSchema.object(
      properties: {
        'apiKey': JsonSchema.string(title: 'API Key'),
      },
      required: ['apiKey'],
    ),
  ),
);

if (result.accepted) {
  final apiKey = result.content?['apiKey'];
  // ... process API key
}
```

## 6. Advanced Transports

### HTTP with Server-Sent Events (SSE)
Use `StreamableMcpServer` to host multiple sessions over HTTP.

```dart
final streamable = StreamableMcpServer(
  serverFactory: (sessionId) => McpServer(
    Implementation(name: 'sse_server', version: '1.0.0'),
  ),
  host: '0.0.0.0',
  port: 8080,
  enableDnsRebindingProtection: true,
  allowedHosts: {'localhost', 'my-server.local'},
);

await streamable.start();
```

---

## 7. Configuration Details

### McpServerOptions
- **`capabilities`**: Define what the server supports (tools, resources, prompts, completions, logging, tasks).
- **`instructions`**: Provide guidance to the client on how to best use this server.

### Protocol Support
The Server module implements the full MCP specification, including:
- **Initialization**: Automatic handling of `initialize` and `notifications/initialized`.
- **Liveness**: Support for `ping` requests.
- **List Changes**: Use `sendToolListChanged()`, `sendResourceListChanged()`, etc., to notify clients of updates.
- **Logging**: Use `sendLoggingMessage()` to stream logs to the client.

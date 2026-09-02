# Server Module Quickstart

The **Server** module is a core component of the [**`mcp_dart`**](https://github.com/pieces-app/mcp_dart) package. It provides both high-level and low-level APIs for building Model Context Protocol (MCP) servers in Dart.

## 1. Overview
The Server module enables you to expose **Tools**, **Resources**, and **Prompts** to MCP clients. It handles the JSON-RPC protocol details and provides several transport implementations for different environments.

### Integration & Ownership
- **Package**: Part of the main `mcp_dart` package.
- **CLI Support**: Integrates with `mcp_dart_cli` (in `packages/mcp_dart_cli/`) for project scaffolding and server management.
- **Types**: Heavily utilizes the `Shared` module types (found in `package:mcp_dart/src/types.dart`).

## 2. Basic Setup
Initialize an `McpServer` with your server's identity and desired capabilities:

```dart
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/server/stdio.dart';

final server = McpServer(
  Implementation(name: 'example-server', version: '1.0.0'),
  options: McpServerOptions(
    capabilities: ServerCapabilities(
      tools: ServerCapabilitiesTools(listChanged: true),
      resources: ServerCapabilitiesResources(subscribe: true, listChanged: true),
      prompts: ServerCapabilitiesPrompts(listChanged: true),
      logging: ServerCapabilitiesLogging(),
      tasks: ServerCapabilitiesTasks(listChanged: true),
    ),
    instructions: 'Use this server to perform custom operations.',
  ),
);
```

## 3. Registering Capabilities

### Tools
Tools are executable functions defined with a name, description, and an input schema. Dart field access in tools must always use **camelCase**.

```dart
server.registerTool(
  'send_batch_email',
  description: 'Sends a batch of emails using provided settings',
  inputSchema: ToolInputSchema(
    properties: {
      'batchId': JsonSchema(type: 'string', description: 'Unique ID for the batch'),
      'sendAt': JsonSchema(type: 'string', description: 'ISO 8601 scheduled time'),
      'mailSettings': JsonSchema(
        type: 'object',
        properties: {
          'sandboxMode': JsonSchema(type: 'boolean'),
          'clickTracking': JsonSchema(type: 'boolean'),
        },
      ),
    },
    required: ['batchId'],
  ),
  callback: (args, extra) async {
    // Correctly using camelCase for all field access
    final batchId = args['batchId'] as String;
    final sendAt = args['sendAt'] as String?;
    final mailSettings = args['mailSettings'] as Map<String, dynamic>?;
    
    final sandboxMode = mailSettings?['sandboxMode'] as bool? ?? false;
    
    return CallToolResult(
      content: [TextContent(text: 'Email batch $batchId scheduled.')],
    );
  },
);
```

### Resources
Resources allow clients to access static or dynamic data.

#### Fixed Resource
```dart
server.registerResource(
  'server_status',
  'file:///status/current',
  (description: 'Current operational status', mimeType: 'application/json'),
  (uri, extra) async => ReadResourceResult(
    contents: [
      TextResourceContents(
        uri: uri.toString(),
        text: '{"status": "online", "uptime": 3600}',
      ),
    ],
  ),
);
```

#### Resource Template
Use RFC 6570 URI templates for dynamic paths.
```dart
server.registerResourceTemplate(
  'metrics_history',
  ResourceTemplateRegistration(
    'file:///metrics/{metricId}/{year}',
    listCallback: (extra) async => ListResourcesResult(
      resources: [
        Resource(uri: 'file:///metrics/cpu/2024', name: 'CPU Metrics 2024'),
      ],
    ),
    completeCallbacks: {
      'metricId': (value) async => ['cpu', 'memory', 'disk']
          .where((m) => m.startsWith(value))
          .toList(),
    },
  ),
  (description: 'Metric data by year', mimeType: 'text/csv'),
  (uri, variables, extra) async {
    final metricId = variables['metricId'];
    final year = variables['year'];
    return ReadResourceResult(
      contents: [
        TextResourceContents(
          uri: uri.toString(),
          text: 'id,value\n$metricId,10.5',
        ),
      ],
    );
  },
);
```

### Prompts
Prompts are reusable templates for LLM interaction.

```dart
server.registerPrompt(
  'code_review',
  description: 'Requests a code review for a snippet',
  argsSchema: {
    'codeSnippet': PromptArgumentDefinition(
      description: 'The code to review',
      required: true,
    ),
  },
  callback: (args, extra) async {
    final codeSnippet = args?['codeSnippet'] ?? '';
    return GetPromptResult(
      messages: [
        SamplingMessage(
          role: 'user',
          content: TextContent(text: 'Please review this Dart code:\n\n$codeSnippet'),
        ),
      ],
    );
  },
);
```

## 4. Advanced Interaction

### Argument Completion
Supported for both Prompts and Resource Templates via `CompletableField`.

```dart
// Example in Prompt definition:
'category': PromptArgumentDefinition(
  completable: CompletableField(
    def: CompletableDef(
      complete: (value) async => ['electronics', 'books', 'clothing']
          .where((e) => e.startsWith(value))
          .toList(),
    ),
  ),
),
```

### Experimental: Tasks
Handle long-running operations asynchronously. Register a tool that returns a task state.

```dart
server.experimental.registerToolTask(
  'heavy_export',
  handler: MyCustomTaskHandler(), // Implementation of ToolTaskHandler
);
```

### Server-to-Client Requests
The server can proactively communicate with the client for logging, elicitation, or sampling.

```dart
// Proactive Logging
await server.sendLoggingMessage(
  LoggingMessageNotification(
    level: LoggingLevel.info,
    data: 'Background indexing started.',
  ),
);

// Elicitation (UI Forms)
final result = await server.elicitInput(
  ElicitRequest.form(
    message: 'Confirm deployment to production?',
    requestedSchema: JsonSchema(type: 'boolean'),
  ),
);
```

## 5. Transports & Deployment

### Standard I/O (stdio)
The standard for local command-line tools and IDE integrations.
```dart
final transport = StdioServerTransport();
await server.connect(transport);
```

### Streamable HTTP (SSE)
High-level HTTP server supporting sessions and resumability.

```dart
import 'package:mcp_dart/src/server/streamable_mcp_server.dart';
import 'package:mcp_dart/src/server/in_memory_event_store.dart';

final streamableServer = StreamableMcpServer(
  serverFactory: (sessionId) => server,
  host: 'localhost',
  port: 3000,
  eventStore: InMemoryEventStore(), // Optional: Enables message resumability
);
await streamableServer.start();
```

#### HTTP Adapters
The transport layer uses adapters to work across different Dart HTTP environments:
- **`DartIoHttpAdapter`**: Direct integration with `dart:io`.
- **`ShelfHttpAdapter`**: Integration with the `shelf` middleware ecosystem.

## 6. Error Handling
Always use `McpError` to return protocol-standard error codes and messages.

```dart
if (subtotal < 0) {
  throw McpError(
    ErrorCode.invalidParams.value,
    'Subtotal cannot be negative',
  );
}
```
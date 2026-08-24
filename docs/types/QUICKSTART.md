# Types Module Quickstart

## 1. Overview

The **Types** module provides the foundational, strongly-typed data models and JSON-RPC message envelopes for the Model Context Protocol (MCP) in Dart. It includes serialization (`toJson`) and deserialization (`fromJson`) logic for all core MCP concepts such as Tools, Resources, Prompts, Tasks, Sampling, and Elicitation, ensuring type-safe communication between clients and servers.

### 1a. Owning Package

This module is owned by the core **mcp_dart** package. It serves as the common type system used across the entire ecosystem, including the `mcp_dart_cli` tool.

### 1b. Integration with `mcp_dart_cli`

The `mcp_dart_cli` package (located in `packages/mcp_dart_cli/`) utilizes these types to provide a command-line interface for interacting with MCP servers. When you define a `Tool` or a `Prompt` in your server using this module, the CLI can automatically discover and interact with them using the same underlying models.

### 1c. What's New

*   **Spec Alignment:** `ClientCapabilitiesSampling` now properly serializes capabilities (`tools` and `context`) as empty-object markers (`"tools": {}`) on the wire to match the MCP 2025-11-25 specification, while maintaining boolean properties in the Dart API for backward compatibility.
*   **Reliability & Error Handling:** Improved JSON-RPC error mapping clearly distinguishes between Parse errors (`-32700`), Invalid params (`-32602`), and Invalid Request (`-32600`) classes, helping you diagnose transport and payload issues faster.

## 2. Installation

Add `mcp_dart` to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_dart:
    git:
      url: git@github.com:pieces-app/mcp_dart.git
      tag_pattern: v{{version}}
```

Then run `dart pub get`.

## 3. Import

Import the core MCP library, which exports these types:

```dart
import 'package:mcp_dart/mcp_dart.dart';
// Or explicitly import the types module if needed:
// import 'package:mcp_dart/src/types.dart';
```

## 4. Setup & Common Operations

The models in this module represent data structures—they do not have active background services. You will instantiate them to form requests or parse incoming JSON maps.

### Example 1: Defining a Tool
Use the `Tool` class alongside `JsonSchema` to define tool capabilities:

```dart
final weatherTool = Tool(
  name: 'get_weather',
  description: 'Retrieve the current weather for a location',
  inputSchema: JsonSchema.fromJson({
    'type': 'object',
    'properties': {
      'location': {'type': 'string', 'description': 'City name'},
    },
    'required': ['location'],
  }),
);

// Convert to a JSON map for transmission
final Map<String, dynamic> toolJson = weatherTool.toJson();
```

### Example 2: Constructing JSON-RPC Requests
MCP uses a structured envelope for JSON-RPC. You can construct typed requests like `JsonRpcInitializeRequest`:

```dart
final initializeRequest = JsonRpcInitializeRequest(
  id: 'req-1',
  initParams: InitializeRequest(
    protocolVersion: latestProtocolVersion, // e.g. "2025-11-25"
    capabilities: ClientCapabilities(
      sampling: ClientCapabilitiesSampling(context: true, tools: true),
    ),
    clientInfo: Implementation(
      name: 'my-dart-client',
      version: '1.0.0',
    ),
  ),
);

final requestPayload = initializeRequest.toJson();
```

### Example 3: Parsing Incoming JSON-RPC Messages
You can parse incoming maps dynamically using the base `JsonRpcMessage.fromJson` factory, which automatically figures out if it's a Request, Response, Notification, or Error:

```dart
final incomingJson = {
  'jsonrpc': '2.0',
  'id': 'req-1',
  'result': {
    'protocolVersion': '2025-11-25',
    'capabilities': {},
    'serverInfo': {'name': 'my-server', 'version': '1.0.0'}
  }
};

final message = JsonRpcMessage.fromJson(incomingJson);

if (message is JsonRpcResponse) {
  // Parse the specific result type
  final result = InitializeResult.fromJson(message.result);
  print('Connected to server: ${result.serverInfo.name}');
} else if (message is JsonRpcNotification) {
  print('Received notification method: ${message.method}');
}
```

### Example 4: Creating Content Parts for Results
When returning data from tools, prompts, or sampling, use the sealed `Content` subclasses like `TextContent` or `ImageContent`:

```dart
final toolResult = CallToolResult(
  content: [
    TextContent(text: 'The weather in San Francisco is 65°F and sunny.'),
  ],
  isError: false,
);
```

### Example 5: Working with Resources
Resources allow servers to expose data (like files, logs, or DB records). Here is how you define a `Resource` and return its content:

```dart
// Defining a resource
final myResource = Resource(
  uri: 'file:///logs/app.log',
  name: 'Application Logs',
  description: 'Main application log file',
  mimeType: 'text/plain',
);

// Constructing the response content
final readResult = ReadResourceResult(
  contents: [
    TextResourceContents(
      uri: 'file:///logs/app.log',
      mimeType: 'text/plain',
      text: '2026-08-24 10:00:00 INFO: System started',
    ),
  ],
);
```

### Example 6: Defining Prompts with Arguments
Prompts are reusable templates for LLM interactions. You can define them with arguments that the client provides:

```dart
final translatePrompt = Prompt(
  name: 'translate',
  description: 'Translate text between languages',
  arguments: [
    PromptArgument(
      name: 'text',
      description: 'The text to translate',
      required: true,
    ),
    PromptArgument(
      name: 'to',
      description: 'The target language',
      required: true,
    ),
  ],
);

// Creating a PromptMessage for the result
final promptMessage = PromptMessage(
  role: PromptMessageRole.user,
  content: TextContent(text: 'Translate "Hello" to Spanish'),
);
```

### Example 7: Sampling and Model Preferences
Sampling allows a server to ask the client to generate a message using an LLM. You can specify `ModelPreferences` to guide model selection:

```dart
final samplingRequest = CreateMessageRequest(
  messages: [
    SamplingMessage(
      role: SamplingMessageRole.user,
      content: SamplingTextContent(text: 'Explain quantum computing in one sentence.'),
    ),
  ],
  maxTokens: 100,
  modelPreferences: ModelPreferences(
    costPriority: 0.2,
    speedPriority: 0.8, // Prioritize fast response
    intelligencePriority: 0.5,
  ),
);
```

### Example 8: Creating and Monitoring Tasks
Tasks are used for long-running operations. You can initiate a task and report its status:

```dart
// Defining a task status update
final taskUpdate = TaskStatusNotification(
  taskId: 'task-123',
  status: TaskStatus.working,
  statusMessage: 'Processing data...',
  pollInterval: 5000, // Suggest client polls every 5 seconds
);

// Completing a task
final taskCompleted = TaskStatusNotification(
  taskId: 'task-123',
  status: TaskStatus.completed,
  statusMessage: 'Operation successful',
);
```

### Example 9: User Input Elicitation
Elicitation allows a server to request input from the user, either via a structured form or an external URL:

```dart
// Requesting a form-based elicitation
final formRequest = ElicitRequest.form(
  message: 'Please enter your API key:',
  requestedSchema: JsonSchema.fromJson({
    'type': 'object',
    'properties': {
      'apiKey': {'type': 'string', 'title': 'API Key'},
    },
    'required': ['apiKey'],
  }),
);

// Handling the result
final result = ElicitResult(
  action: 'accept',
  content: {'apiKey': 'sk-123...'},
);
```

### Example 10: Managing Roots
Roots represent the project folders or files a client makes available to the server:

```dart
final roots = [
  Root(uri: 'file:///home/user/project', name: 'Main Project'),
  Root(uri: 'file:///home/user/docs', name: 'Documentation'),
];

final listRootsResult = ListRootsResult(roots: roots);
```

### Example 11: Server Logging
Servers can send log messages to the client at various severity levels:

```dart
final logNotification = LoggingMessageNotification(
  level: LoggingLevel.info,
  logger: 'database_service',
  data: 'Connection established successfully',
);
```

### Example 12: Autocompletion
Servers can provide completion options for prompt and resource arguments:

```dart
// Requesting completions for a prompt argument
final completeRequest = CompleteRequest(
  ref: PromptReference(name: 'translate'),
  argument: ArgumentCompletionInfo(
    name: 'to',
    value: 'Spa', // User has typed "Spa"
  ),
);

// Returning completion options
final completeResult = CompleteResult(
  completion: CompletionResultData(
    values: ['Spanish', 'Slovak', 'Slovenian'],
    hasMore: false,
  ),
);
```

## 5. Advanced Types

### Pagination with Cursors
Many "list" requests support pagination using opaque cursors.

```dart
// Initial request
final listRequest = ListToolsRequest();

// Parsing the result with a nextCursor
final result = ListToolsResult(
  tools: [...],
  nextCursor: 'page-2-token',
);

// Fetching the next page
final nextRequest = ListToolsRequest(cursor: result.nextCursor);
```

### JSON-RPC Metadata (`_meta`)
Most requests and responses support optional metadata for extensions or protocol features like progress tokens:

```dart
final requestWithProgress = JsonRpcPingRequest(id: 1);
// Metadata is typically passed in the params map or as a separate argument 
// depending on the specific JsonRpcRequest subclass constructor.
```

## 6. Error Handling

The protocol represents standard and domain-specific errors via `JsonRpcError` and the internal `McpError` exception.

```dart
final errorJson = {
  'jsonrpc': '2.0',
  'id': 'req-2',
  'error': {
    'code': -32602,
    'message': 'Invalid params'
  }
};

final message = JsonRpcMessage.fromJson(errorJson);

if (message is JsonRpcError) {
  print('RPC Error ${message.error.code}: ${message.error.message}');
  
  // Check against known standard ErrorCode enum values
  if (message.error.code == ErrorCode.invalidParams.value) {
    print('The server rejected the provided parameters.');
  } else if (message.error.code == ErrorCode.urlElicitationRequired.value) {
    print('URL interaction is required before proceeding.');
  }
}
```

## 7. Related Modules

*   **Client**: Uses these Types models extensively to construct requests, parse responses, and dispatch notifications.
*   **Server**: Builds upon these types to handle client requests, advertise capabilities, and format tool results.
*   **Shared**: Contains standard structures like `JsonSchema` that are nested within the type definitions.
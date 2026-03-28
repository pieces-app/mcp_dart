# Types Module Quickstart

**Owning Package:** `mcp_dart`

## 1. Overview

The Types module provides the core data structures and JSON-RPC message definitions for the Model Context Protocol (MCP) Dart implementation. It contains strongly-typed, JSON-serializable classes representing the standard MCP primitives—such as tools, resources, prompts, and sampling—as well as the underlying JSON-RPC protocol definitions (requests, responses, notifications, and errors) utilized by clients and servers to communicate.

## 2. Import

To use the types in your project, import the main package:

```dart
import 'package:mcp_dart/mcp_dart.dart';
```

If you need to access specific type definitions directly, you can import them from the `src/types` directory:

```dart
import 'package:mcp_dart/src/types/tools.dart';
import 'package:mcp_dart/src/types/resources.dart';
import 'package:mcp_dart/src/types/json_rpc.dart';
import 'package:mcp_dart/src/types/prompts.dart';
import 'package:mcp_dart/src/types/content.dart';
import 'package:mcp_dart/src/types/elicitation.dart';
import 'package:mcp_dart/src/types/sampling.dart';
import 'package:mcp_dart/src/types/tasks.dart';
```

## 3. Core Concepts

### Initialization & Capabilities

MCP starts with an initialization handshake where both parties exchange capabilities.

```dart
// Describe your implementation
final clientInfo = Implementation(
  name: 'my-mcp-client',
  version: '1.0.0',
);

// Define supported capabilities
final capabilities = ClientCapabilities(
  roots: ClientCapabilitiesRoots(listChanged: true),
  sampling: ClientCapabilitiesSampling(tools: true),
  elicitation: ClientElicitation.all(), // Supports both form and URL modes
);

// Create the initialize request
final initRequest = InitializeRequest(
  protocolVersion: latestProtocolVersion,
  capabilities: capabilities,
  clientInfo: clientInfo,
);
```

### Tools

Tools allow servers to expose executable functions to models.

```dart
final weatherTool = Tool(
  name: 'get_weather',
  description: 'Get current weather for a location',
  inputSchema: JsonSchema.object(
    properties: {
      'location': JsonSchema.string(description: 'City and state/country'),
      'unit': JsonSchema.string(
        description: 'Temperature unit',
        enumValues: ['celsius', 'fahrenheit'],
      ),
    },
    required: ['location'],
  ),
);

// Returning a tool result
final toolResult = CallToolResult(
  content: [
    TextContent(text: 'Current weather in San Francisco: 62°F, Partly Cloudy'),
    ImageContent(
      data: 'base64_encoded_image_data',
      mimeType: 'image/png',
    ),
  ],
  isError: false,
);
```

### Resources

Resources are data items (files, DB records, etc.) provided by the server.

```dart
// Resource description
final configResource = Resource(
  uri: 'file:///app/config.json',
  name: 'Application Configuration',
  mimeType: 'application/json',
);

// Resource Template for dynamic URIs
final userResourceTemplate = ResourceTemplate(
  uriTemplate: 'mcp://users/{userId}/profile',
  name: 'User Profile',
  description: 'Retrieves a specific user profile by ID',
);

// Reading resource contents
final readResult = ReadResourceResult(
  contents: [
    TextResourceContents(
      uri: 'file:///app/config.json',
      text: '{"theme": "dark", "notifications": true}',
      mimeType: 'application/json',
    ),
  ],
);
```

### Prompts

Prompts are predefined templates for model interactions.

```dart
final reviewPrompt = Prompt(
  name: 'code_review',
  description: 'Request a review for a specific code block',
  arguments: [
    PromptArgument(
      name: 'code',
      description: 'The code to review',
      required: true,
    ),
    PromptArgument(
      name: 'language',
      description: 'Programming language',
      required: false,
    ),
  ],
);

// Returning prompt messages
final promptResult = GetPromptResult(
  description: 'Code review request',
  messages: [
    PromptMessage(
      role: PromptMessageRole.user,
      content: TextContent(text: 'Please review this Dart code...'),
    ),
  ],
);
```

### Elicitation (User Interaction)

Servers can request user input or external interaction via elicitation.

```dart
// Form Mode: Collect structured data in-band
final formRequest = ElicitRequest.form(
  message: 'Please enter your API key',
  requestedSchema: JsonSchema.string(description: 'Provider API Key'),
);

// URL Mode: Direct user to external site
final urlRequest = ElicitRequest.url(
  message: 'Please authenticate with GitHub',
  url: 'https://github.com/login/oauth/authorize...',
  elicitationId: 'auth_session_123',
);

// Elicitation response result
final elicitResult = ElicitResult(
  action: 'accept',
  content: {'key': 'sk-12345'},
);
```

### Sampling (LLM Integration)

Sampling allows servers to request model completions from the client.

```dart
final samplingRequest = CreateMessageRequest(
  messages: [
    SamplingMessage(
      role: SamplingMessageRole.user,
      content: SamplingTextContent(text: 'What is the capital of France?'),
    ),
  ],
  maxTokens: 100,
  temperature: 0.7,
  modelPreferences: ModelPreferences(
    intelligencePriority: 0.9,
  ),
);

// Sampling result
final samplingResult = CreateMessageResult(
  model: 'gpt-4o',
  role: SamplingMessageRole.assistant,
  content: SamplingTextContent(text: 'The capital of France is Paris.'),
  stopReason: StopReason.endTurn,
);
```

### Tasks

Tasks represent long-running operations with status tracking.

```dart
final myTask = Task(
  taskId: 'job_789',
  status: TaskStatus.working,
  statusMessage: 'Analyzing repository structure...',
  createdAt: '2026-03-28T12:00:00Z',
  pollInterval: 2000,
);

// Notifying status changes
final taskNotification = TaskStatusNotification(
  taskId: 'job_789',
  status: TaskStatus.completed,
  statusMessage: 'Analysis complete',
);
```

## 4. JSON-RPC Protocol

All messages can be serialized/deserialized via `JsonRpcMessage`.

```dart
// Parsing a raw message
final Map<String, dynamic> rawJson = {...};
final message = JsonRpcMessage.fromJson(rawJson);

if (message is JsonRpcRequest) {
  print('Received request: ${message.method} with ID ${message.id}');
}

// Handling errors
try {
  // operation that might fail
} catch (e) {
  final mcpError = McpError(
    ErrorCode.internalError.value,
    'Something went wrong: $e',
  );
  // Send as JsonRpcError...
}
```

## 5. Multi-Package Integration

- **`mcp_dart`:** This package owns the Types module. All core types are exported here.
- **`mcp_dart_cli` (Workspace Sub-Package):** The CLI uses these types to provide diagnostic tools. It leverages the strongly-typed nature of these classes to validate server responses and inspect protocol payloads in real-time.

## 6. Best Practices

1. **Use CamelCase:** Always use camelCase for accessing Dart fields (e.g., `protocolVersion`, `listChanged`, `taskId`).
2. **Handle Nulls:** Many MCP fields are optional. Use null-safe operators when accessing results.
3. **Validate Metadata:** Metadata (`_meta` or `.meta`) can contain experimental or non-standard fields. Validate their presence before use.
4. **Prefer Enums:** Use provided enums like `PromptMessageRole`, `TaskStatus`, and `LoggingLevel` instead of raw strings where possible.
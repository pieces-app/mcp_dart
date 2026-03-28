# Types API Reference

## Package Ownership

The **Types** module is part of the core `mcp_dart` package. It defines the foundational data structures and JSON-RPC protocol messages used by all Model Context Protocol (MCP) implementations in this repository.

### Integration with `mcp_dart_cli`
This module is utilized by the `mcp_dart_cli` package (located in `packages/mcp_dart_cli/`) to provide type-safe interactions when inspecting, serving, or debugging MCP servers. All command-line tools and inter-process communication (IPC) rely on these definitions for protocol compliance.

---

## 1. JSON-RPC Core

These classes define the base messaging layer for MCP.

### Methods & Constants
Standard MCP JSON-RPC methods are defined as static constants in the `Method` class.

```dart
import 'package:mcp_dart/mcp_dart.dart';

// Example usage of Method constants
print(Method.initialize); // "initialize"
print(Method.toolsCall);   // "tools/call"
```

### JsonRpcMessage
Base class for all messages. Use `JsonRpcMessage.fromJson` to deserialize any incoming message.

### JsonRpcRequest
Base class for requests expecting a response.
- **Fields:** `id`, `method`, `params`, `meta`
- **Properties:** `progressToken` (retrieved from `_meta`)

```dart
final request = JsonRpcInitializeRequest(
  id: 1,
  initParams: InitializeRequest(
    protocolVersion: latestProtocolVersion,
    clientInfo: Implementation(name: "ExampleClient", version: "1.0.0"),
    capabilities: ClientCapabilities(),
  ),
);
```

### JsonRpcError
Represents a protocol error.
- **Fields:** `id`, `error` (instance of `JsonRpcErrorData`)

```dart
final errorResponse = JsonRpcError(
  id: 1,
  error: JsonRpcErrorData(
    code: ErrorCode.methodNotFound.value,
    message: "Method not found",
  ),
);
```

---

## 2. Lifecycle & Capabilities

### Implementation
Describes an MCP implementation (client or server).
- **Fields:** `name`, `version`, `description`

### ClientCapabilities
Declares what features a client supports.
- **Fields:** `experimental`, `sampling`, `roots`, `elicitation`, `tasks`, `extensions`

### ServerCapabilities
Declares what features a server provides.
- **Fields:** `experimental`, `logging`, `prompts`, `resources`, `tools`, `completions`, `tasks`, `elicitation`, `extensions`

### InitializeRequest / InitializeResult
The handshake messages exchanged during connection setup.

```dart
// Constructing an InitializeResult
final result = InitializeResult(
  protocolVersion: "2025-11-25",
  serverInfo: Implementation(
    name: "WeatherServer",
    version: "1.2.0",
    description: "Provides weather updates",
  ),
  capabilities: ServerCapabilities(
    tools: ServerCapabilitiesTools(listChanged: true),
    resources: ServerCapabilitiesResources(subscribe: true),
  ),
);
```

---

## 3. Tools & Resources

### Tool
Defines an executable tool.
- **Fields:** `name`, `description`, `inputSchema`, `outputSchema`, `annotations`, `execution`, `icon`, `icons`

```dart
final weatherTool = Tool(
  name: "get_weather",
  description: "Get current weather for a city",
  inputSchema: JsonSchema.object(
    properties: {
      "city": JsonSchema.string(description: "The city name"),
    },
    required: ["city"],
  ),
)..annotations = ToolAnnotations(
  title: "Weather Checker",
  readOnlyHint: true,
);
```

### Resource
Describes a data source.
- **Fields:** `uri`, `name`, `description`, `mimeType`, `icon`, `icons`, `annotations`

### Content
Sealed class for data parts.
- **Subclasses:** `TextContent`, `ImageContent`, `AudioContent`, `EmbeddedResource`, `ResourceLink`

---

## 4. Prompts & Sampling

### Prompt
A template for model interaction.
- **Fields:** `name`, `description`, `arguments`, `icon`, `icons`

### SamplingMessage
Represents a message in an LLM sampling exchange.
- **Fields:** `role` (user/assistant), `content` (SamplingContent)

```dart
final samplingRequest = CreateMessageRequest(
  messages: [
    SamplingMessage(
      role: SamplingMessageRole.user,
      content: SamplingTextContent(text: "Hello!"),
    ),
  ],
  maxTokens: 100,
  temperature: 0.7,
);
```

---

## 5. Advanced Interactions

### Tasks
Tasks allow for long-running operations with status updates and cancellation.
- **Task Fields:** `taskId`, `status`, `statusMessage`, `ttl`, `pollInterval`, `createdAt`, `lastUpdatedAt`

```dart
final taskStatus = Task(
  taskId: "task-123",
  status: TaskStatus.working,
  statusMessage: "Processing data...",
)..pollInterval = 5000;
```

### Elicitation
Server-initiated requests for user input.
- **Modes:** `form` (structured JSON), `url` (out-of-band)

```dart
final elicitation = ElicitRequest.form(
  message: "Please enter your API key",
  requestedSchema: JsonSchema.string(format: "password"),
);
```

---

## 6. JSON Schema Builder

The `JsonSchema` class provides a type-safe DSL for building JSON schemas.

```dart
final configSchema = JsonSchema.object(
  properties: {
    "port": JsonSchema.integer(minimum: 1024, maximum: 65535, defaultValue: 8080),
    "enableLogging": JsonSchema.boolean(defaultValue: true),
    "apiKey": JsonSchema.string(minLength: 32),
  },
  required: ["apiKey"],
);
```

---

## 7. Enums & Extensions

### TaskStatus & TaskStatusName
| Value | Description |
|---|---|
| `working` | Task is currently in progress. |
| `inputRequired` | Task is waiting for user input (elicitation). |
| `completed` | Task finished successfully. |
| `failed` | Task encountered an error. |
| `cancelled` | Task was aborted by client or server. |

**Extension Methods:**
- `status.name`: Returns string representation (e.g., "input_required").
- `status.isTerminal`: Returns true if status is `completed`, `failed`, or `cancelled`.

### ErrorCode
| Value | Code | Description |
|---|---|---|
| `parseError` | -32700 | Invalid JSON was received. |
| `invalidRequest` | -32600 | The JSON sent is not a valid Request object. |
| `methodNotFound` | -32601 | The method does not exist / is not available. |
| `invalidParams` | -32602 | Invalid method parameter(s). |
| `internalError` | -32603 | Internal JSON-RPC error. |
| `urlElicitationRequired`| -32042 | URL mode elicitation is required. |

---

## Full Class Index

### completion.dart
- `Reference` (Sealed), `ResourceReference`, `PromptReference`
- `ArgumentCompletionInfo`
- `CompleteRequest`, `JsonRpcCompleteRequest`
- `CompletionResultData`, `CompleteResult`
- `JsonRpcCompletionListChangedNotification`

### content.dart
- `ResourceContents` (Sealed), `TextResourceContents`, `BlobResourceContents`, `UnknownResourceContents`
- `McpIcon`
- `Content` (Sealed), `TextContent`, `ImageContent`, `AudioContent`, `EmbeddedResource`, `ResourceLink`, `UnknownContent`

### elicitation.dart
- `ElicitRequest`, `JsonRpcElicitRequest`, `ElicitResult`
- `ElicitationCompleteNotification`, `JsonRpcElicitationCompleteNotification`
- `URLElicitationRequiredErrorData`

### initialization.dart
- `Implementation`
- `ClientCapabilities`, `ServerCapabilities`
- `InitializeRequest`, `InitializeResult`, `JsonRpcInitializeRequest`

### json_rpc.dart
- `JsonRpcMessage` (Sealed), `JsonRpcRequest`, `JsonRpcNotification`, `JsonRpcResponse`, `JsonRpcError`
- `ErrorCode` (Enum)
- `JsonRpcListToolsRequest`, `JsonRpcCallToolRequest`

### logging.dart
- `LoggingLevel` (Enum)
- `SetLevelRequest`, `JsonRpcSetLevelRequest`
- `LoggingMessageNotification`, `JsonRpcLoggingMessageNotification`

### misc.dart
- `EmptyResult`
- `CancelledNotification`, `JsonRpcCancelledNotification`
- `JsonRpcPingRequest`
- `Progress`, `ProgressNotification`, `JsonRpcProgressNotification`

### prompts.dart
- `PromptArgument`, `Prompt`
- `ListPromptsRequest`, `ListPromptsResult`, `JsonRpcListPromptsRequest`
- `GetPromptRequest`, `GetPromptResult`, `JsonRpcGetPromptRequest`
- `PromptMessage`, `PromptMessageRole` (Enum)
- `JsonRpcPromptListChangedNotification`

### resources.dart
- `Resource`, `ResourceTemplate`, `ResourceAnnotations`
- `ListResourcesRequest`, `ListResourcesResult`, `JsonRpcListResourcesRequest`
- `ListResourceTemplatesRequest`, `ListResourceTemplatesResult`, `JsonRpcListResourceTemplatesRequest`
- `ReadResourceRequest`, `ReadResourceResult`, `JsonRpcReadResourceRequest`
- `SubscribeRequest`, `UnsubscribeRequest`, `JsonRpcSubscribeRequest`, `JsonRpcUnsubscribeRequest`
- `ResourceUpdatedNotification`, `JsonRpcResourceUpdatedNotification`
- `JsonRpcResourceListChangedNotification`

### roots.dart
- `Root`
- `ListRootsResult`, `JsonRpcListRootsRequest`
- `JsonRpcRootsListChangedNotification`

### sampling.dart
- `SamplingMessage`, `SamplingContent` (Sealed), `SamplingTextContent`, `SamplingImageContent`, `SamplingToolUseContent`, `SamplingToolResultContent`
- `ModelHint`, `ModelPreferences`
- `CreateMessageRequest`, `CreateMessageResult`, `JsonRpcCreateMessageRequest`
- `StopReason` (Enum), `IncludeContext` (Enum)

### tasks.dart
- `Task`, `TaskStatus` (Enum), `TaskStatusName` (Extension)
- `TaskCreation`, `CreateTaskResult`
- `ListTasksRequest`, `ListTasksResult`, `JsonRpcListTasksRequest`
- `GetTaskRequest`, `CancelTaskRequest`, `TaskResultRequest`
- `JsonRpcTaskStatusNotification`
- `TaskStreamMessage` (Sealed), `TaskCreatedMessage`, `TaskStatusMessage`, `TaskResultMessage`, `TaskErrorMessage`

### tools.dart
- `Tool`, `ToolAnnotations`, `ToolExecution`
- `ListToolsRequest`, `ListToolsResult`, `JsonRpcListToolsRequest`
- `CallToolRequest`, `CallToolResult`, `JsonRpcCallToolRequest`
- `JsonRpcToolListChangedNotification`

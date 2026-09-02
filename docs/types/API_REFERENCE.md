# Types API Reference

**Owning Package:** `mcp_dart`

The **Types** module provides the core data structures, Model Context Protocol (MCP) primitives, and JSON-RPC message envelopes used across the `mcp_dart` workspace. It acts as the shared vocabulary between clients and servers, ensuring type-safe communication and consistent behavior.

## Workspace Integration

- **mcp_dart**: This package contains the primary implementation of these types.
- **mcp_dart_cli**: Utilizes these types to provide CLI-based management, inspection, and interaction with MCP servers.

---

## 1. Messages

### Initialization & Capabilities
- **Implementation** -- Describes an MCP implementation.
  - `name` (String): Name of the implementation.
  - `version` (String): Version string.
  - `description` (String, optional): Optional description.
- **ClientCapabilities** -- Capabilities supported by the client.
  - `sampling` (ClientCapabilitiesSampling, optional)
  - `roots` (ClientCapabilitiesRoots, optional)
  - `elicitation` (ClientElicitation, optional)
  - `tasks` (ClientCapabilitiesTasks, optional)
  - `extensions` (Map, optional): MCP extension capabilities (SEP-1724).
- **ServerCapabilities** -- Capabilities supported by the server.
  - `logging` (Map, optional)
  - `prompts` (ServerCapabilitiesPrompts, optional)
  - `resources` (ServerCapabilitiesResources, optional)
  - `tools` (ServerCapabilitiesTools, optional)
  - `completions` (ServerCapabilitiesCompletions, optional)
  - `tasks` (ServerCapabilitiesTasks, optional)
  - `elicitation` (ServerCapabilitiesElicitation, optional)
- **InitializeRequest** -- Parameters to begin the connection.
  - `protocolVersion` (String): Latest protocol version supported by the client.
  - `capabilities` (ClientCapabilities): Client-side capabilities.
  - `clientInfo` (Implementation): Client implementation details.

### Content & Resources
- **ResourceContents** -- Sealed class for resource data.
  - **TextResourceContents**: Text-based content.
  - **BlobResourceContents**: Binary content (Base64 encoded).
- **Content** -- Sealed class for prompt/tool result parts.
  - **TextContent**: Simple text message.
  - **ImageContent**: Image data with `mimeType`.
  - **AudioContent**: Audio data with `mimeType`.
  - **EmbeddedResource**: A resource embedded directly in content.
  - **ResourceLink**: A reference to a resource via URI.
- **Resource** -- A known resource offered by a server.
  - `uri` (String): Unique resource identifier.
  - `name` (String): Human-readable name.
  - `mimeType` (String, optional)
  - `annotations` (ResourceAnnotations, optional): Metadata like `title`, `priority`, or `lastModified`.

### Sampling
- **CreateMessageRequest** -- Request to an LLM via the client.
  - `messages` (List<SamplingMessage>): Conversation history.
  - `systemPrompt` (String, optional)
  - `maxTokens` (int): Maximum tokens to generate.
  - `modelPreferences` (ModelPreferences, optional): Hints for model selection.
- **SamplingContent** -- Sealed class for sampling parts.
  - **SamplingTextContent**
  - **SamplingImageContent**
  - **SamplingToolUseContent**
  - **SamplingToolResultContent**

### Elicitation
- **ElicitRequest** -- Server request for user input.
  - `mode` (ElicitationMode): `form` or `url`.
  - `message` (String): Explanation for the user.
  - `requestedSchema` (JsonSchema, optional): For `form` mode.
  - `url` (String, optional): For `url` mode.

### Tasks
- **Task** -- Represents an asynchronous operation.
  - `taskId` (String): Unique ID.
  - `status` (TaskStatus): `working`, `inputRequired`, `completed`, `failed`, or `cancelled`.
- **TaskStreamMessage** -- Sealed class for task status streams.
  - **TaskCreatedMessage**
  - **TaskStatusMessage**
  - **TaskResultMessage**
  - **TaskErrorMessage**

---

## 2. Services (JSON-RPC Methods)

MCP uses standalone methods rather than grouped services. Major methods include:

| Method | Description |
|--------|-------------|
| `initialize` | Begins the session and exchanges capabilities. |
| `resources/list` | Lists available resources on the server. |
| `resources/read` | Reads the contents of a specific resource. |
| `prompts/list` | Lists available prompt templates. |
| `prompts/get` | Retrieves a specific prompt with arguments. |
| `tools/list` | Lists available tools. |
| `tools/call` | Executes a specific tool with arguments. |
| `sampling/createMessage` | (Server-to-Client) Requests LLM completion. |
| `elicitation/create` | (Server-to-Client) Requests user input/interaction. |
| `completion/complete` | Requests completion options for an argument. |
| `roots/list` | (Server-to-Client) Requests list of root URIs. |
| `tasks/list` | Lists active tasks. |
| `tasks/get` | Retrieves the current status of a task. |
| `logging/setLevel` | Adjusts the server's logging level. |

---

## 3. Enums

- **LoggingLevel**: `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency`.
- **TaskStatus**: `working`, `inputRequired`, `completed`, `failed`, `cancelled`.
- **ElicitationMode**: `form`, `url`.
- **StopReason**: `endTurn`, `stopSequence`, `maxTokens`.

---

## 4. Dart Usage Examples

### Constructing an Initialize Request
All fields use **camelCase** as per Dart conventions.

```dart
import 'package:mcp_dart/mcp_dart.dart';

final request = InitializeRequest(
  protocolVersion: "2025-11-25",
  clientInfo: Implementation(
    name: "dart-mcp-client",
    version: "1.0.0",
  ),
  capabilities: ClientCapabilities(
    sampling: ClientCapabilitiesSampling(
      context: true,
      tools: true,
    ),
    roots: ClientCapabilitiesRoots(listChanged: true),
  ),
);
```

### Creating Tool Results
You can use standard constructors to build complex content lists.

```dart
final result = CallToolResult(
  content: [
    TextContent(text: "Operation successful."),
    ImageContent(
      data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BfAAAACQBxFEwI3QAAAABJRU5ErkJggg==",
      mimeType: "image/png",
    ),
  ],
  isError: false,
);
```

### Handling Task Streams
The sealed `TaskStreamMessage` allows for clean exhaustive switching.

```dart
void handleStream(TaskStreamMessage message) {
  switch (message) {
    case TaskCreatedMessage(task: var t):
      print("Task started: ${t.taskId}");
    case TaskStatusMessage(task: var t):
      print("Status: ${t.statusName}");
    case TaskResultMessage(result: var r):
      print("Task finished with result: ${r.toJson()}");
    case TaskErrorMessage(error: var e):
      print("Task failed: $e");
  }
}
```

---

## 5. Installation

```yaml
dependencies:
  mcp_dart: ^1.2.0
```

For the latest features, you can also depend on the repository directly:

```yaml
dependencies:
  mcp_dart:
    git:
      url: https://github.com/leehack/mcp_dart.git
```

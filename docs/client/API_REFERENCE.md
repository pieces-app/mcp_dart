# Client Module API Reference

**Owning Package:** `mcp_dart`

The **Client** module provides the core implementation for the Multi-Channel Protocol (MCP) in Dart. It handles the protocol handshake, session management, and standard MCP requests (tools, resources, prompts, etc.) over a pluggable transport layer.

## Integration with Other Packages

- **`mcp_dart_cli`**: This package utilizes the `McpClient` and `StdioClientTransport` to provide a ready-to-use command-line interface for interacting with MCP servers.
- **Custom Clients**: Use this module to build custom desktop or web-based MCP clients by choosing the appropriate transport (`StdioClientTransport` for native or `StreamableHttpClientTransport` for web/native).

---

## Core Classes

### McpClient

The primary entry point for MCP client functionality. It extends `Protocol` and manages the initialization lifecycle with an MCP server.

#### Constructors
- `McpClient(Implementation clientInfo, {McpClientOptions? options})`: Initializes a client with metadata and optional configuration.

#### Fields
- `onElicitRequest` (`Future<ElicitResult> Function(ElicitRequest)?`): Callback for handling server-initiated elicitation requests.
- `onSamplingRequest` (`Future<CreateMessageResult> Function(CreateMessageRequest)?`): Callback for handling server-initiated sampling (LLM completion) requests.
- `onTaskStatus` (`FutureOr<void> Function(TaskStatusNotification)?`): Callback for handling task status notifications.

#### Key Methods
- `connect(Transport transport)`: Connects to the server using the provided transport and completes the initialization handshake.
- `callTool(CallToolRequest params)`: Invokes a tool on the server.
- `listTools({ListToolsRequest? params})`: Lists available tools.
- `getPrompt(GetPromptRequest params)`: Retrieves a prompt template.
- `listPrompts({ListPromptsRequest? params})`: Lists available prompts.
- `readResource(ReadResourceRequest params)`: Reads the content of a resource.
- `listResources({ListResourcesRequest? params})`: Lists available resources.
- `ping()`: Sends a protocol-level ping to verify connection.

#### Example: Initializing and Calling a Tool

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  // 1. Define client information
  final clientInfo = Implementation(
    name: "MyClient",
    version: "1.0.0"
  );

  // 2. Configure client options
  final options = McpClientOptions(
    capabilities: const ClientCapabilities(
      sampling: ClientCapabilitiesSampling(tools: true)
    )
  );

  final client = McpClient(clientInfo, options: options);

  // 3. Setup Transport (Example: Stdio)
  final transport = StdioClientTransport(const StdioServerParameters(
    command: "node",
    args: ["server.js"]
  ));

  // 4. Connect
  await client.connect(transport);

  // 5. Call a tool using cascade notation for request building
  final result = await client.callTool(
    CallToolRequest(name: "calculate_sum")
      ..arguments = {"a": 10, "b": 20}
  );

  if (!result.isError) {
    print("Result: ${result.content}");
  }

  await client.close();
}
```

---

### TaskClient

A helper class that abstracts the complexity of task-augmented tool calls, handling polling and terminal state retrieval automatically.

#### Methods
- `callToolStream(String name, Map<String, dynamic> arguments, {Map<String, dynamic>? task})`: Returns a `Stream<TaskStreamMessage>` that yields status updates and the final result.

#### Example: Using Task-Augmented Tool Calls

```dart
final taskClient = TaskClient(client);

final taskStream = taskClient.callToolStream(
  "long_running_process",
  {"input": "data"},
  task: {"ttl": 60000} // Request task augmentation
);

await for (final message in taskStream) {
  if (message is TaskCreatedMessage) {
    print("Task created: ${message.task.taskId}");
  } else if (message is TaskStatusMessage) {
    print("Status: ${message.task.status.name}");
  } else if (message is TaskResultMessage) {
    print("Final result: ${message.result.toJson()}");
  } else if (message is TaskErrorMessage) {
    print("Error: ${message.error}");
  }
}
```

---

## Transports

### StdioClientTransport

Connects to a server by spawning a process and communicating via `stdin`/`stdout`.

```dart
final transport = StdioClientTransport(
  StdioServerParameters(
    command: "python",
    args: ["mcp_server.py"],
    environment: {"DEBUG": "true"},
    stderrMode: ProcessStartMode.inheritStdio
  )
);
```

### StreamableHttpClientTransport

Connects to a server using HTTP POST for sending and Server-Sent Events (SSE) for receiving messages. Supports authentication and resumable streams.

```dart
final transport = StreamableHttpClientTransport(
  Uri.parse("https://mcp-server.example.com/endpoint"),
  opts: StreamableHttpClientTransportOptions(
    authProvider: myOAuthProvider,
    reconnectionOptions: const StreamableHttpReconnectionOptions(
      maxRetries: 5,
      initialReconnectionDelay: 1000,
      reconnectionDelayGrowFactor: 2.0,
      maxReconnectionDelay: 60000
    )
  )
);
```

---

## Configuration Classes

### McpClientOptions
- `capabilities`: The `ClientCapabilities` the client supports.
- `enforceStrictCapabilities`: Whether to fail requests if the server hasn't advertised the required capability.

### ClientCapabilities
Used to advertise support for specific MCP features.
- `sampling`: Support for `sampling/createMessage`.
- `roots`: Support for `roots/list` and `list_changed` notifications.
- `elicitation`: Support for `elicitation/create`.
- `tasks`: Support for task-based execution.

---

## Shared Types (Client Usage)

When interacting with the client, you will use these common message types. All fields use **camelCase**.

### CallToolResult
- `content` (`List<Content>`): The items returned by the tool (text, image, etc.).
- `isError` (`bool`): Whether the tool call failed.
- `structuredContent` (`Map<String, dynamic>?`): Structured data returned by the tool.

### Task
- `taskId` (`String`): Unique identifier.
- `status` (`TaskStatus`): Current state (`working`, `inputRequired`, `completed`, `failed`, `cancelled`).
- `statusMessage` (`String?`): Optional description of the current state.
- `pollInterval` (`int?`): Suggested milliseconds between status checks.

### CreateMessageRequest (Sampling)
- `messages` (`List<SamplingMessage>`): Context for the LLM.
- `maxTokens` (`int`): Maximum length of response.
- `modelPreferences` (`ModelPreferences?`): Hints for model selection.
- `systemPrompt` (`String?`): Optional system instructions.

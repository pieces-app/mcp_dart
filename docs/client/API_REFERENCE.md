# Client Module API Reference

**Owning Package:** `mcp_dart`

This module provides the core client implementation for the Model Context Protocol (MCP). It includes the main `McpClient` class, built on a pluggable transport architecture, alongside built-in transports like `StdioClientTransport` and `StreamableHttpClientTransport`.

## Multi-Package Repository Structure

The `mcp_dart` repository is a multi-package workspace. This **Client** module is owned by the core `mcp_dart` package.

### Sub-packages
- **mcp_dart_cli**: A command-line interface for MCP, located in `packages/mcp_dart_cli/`. It utilizes this module to connect to and inspect MCP servers.

---

## 1. Classes

### McpClientOptions
Options for configuring the MCP `McpClient`.

**Fields:**
- `capabilities`: `ClientCapabilities?` - Capabilities to advertise as being supported by this client.
- `enforceStrictCapabilities`: `bool` - Whether to restrict emitted requests to only those that the remote side has indicated they can handle (inherited from `ProtocolOptions`).

**Constructors:**
- `McpClientOptions({bool enforceStrictCapabilities = false, ClientCapabilities? capabilities})`

**Example:**
```dart
import 'package:mcp_dart/mcp_dart.dart';

final options = McpClientOptions(
  enforceStrictCapabilities: true,
  capabilities: ClientCapabilities(
    sampling: const ClientCapabilitiesSampling(tools: true),
    roots: const ClientCapabilitiesRoots(listChanged: true),
  ),
);
```

### McpClient
An MCP client implementation built on top of a pluggable `Transport`. Handles the initialization handshake with the server upon connection and provides methods for making standard MCP requests.

**Fields:**
- `onElicitRequest`: `Future<ElicitResult> Function(ElicitRequest)?` - Callback for handling elicitation requests from the server.
- `onTaskStatus`: `FutureOr<void> Function(TaskStatusNotification params)?` - Callback for handling task status notifications from the server.
- `onSamplingRequest`: `Future<CreateMessageResult> Function(CreateMessageRequest params)?` - Callback for handling sampling requests from the server.

**Constructors:**
- `McpClient(Implementation clientInfo, {McpClientOptions? options})`

**Initialization Example:**
```dart
import 'package:mcp_dart/mcp_dart.dart';

final client = McpClient(
  const Implementation(
    name: 'my-client',
    version: '1.0.0',
    description: 'A custom MCP client',
  ),
  options: McpClientOptions(
    capabilities: const ClientCapabilities(
      roots: ClientCapabilitiesRoots(listChanged: true),
    ),
  ),
);

// Register handlers before connecting
client.onElicitRequest = (request) async {
  // Handle server elicitation request
  return ElicitResult(
    action: 'accept',
    content: {'key': 'value'},
  );
};
```

**Methods:**
- `registerCapabilities(ClientCapabilities capabilities)`: `void` - Registers new capabilities for this client before connecting.
- `connect(Transport transport)`: `Future<void>` - Connects to the server using the given transport and performs the initialization handshake.
- `getServerCapabilities()`: `ServerCapabilities?` - Gets the server's reported capabilities after successful initialization.
- `getServerVersion()`: `Implementation?` - Gets the server's reported implementation info.
- `getInstructions()`: `String?` - Gets the server's instructions provided during initialization.
- `ping([RequestOptions? options])`: `Future<EmptyResult>` - Sends a `ping` request to the server.
- `complete(CompleteRequest params, [RequestOptions? options])`: `Future<CompleteResult>` - Sends a `completion/complete` request for argument completion.
- `setLoggingLevel(LoggingLevel level, [RequestOptions? options])`: `Future<EmptyResult>` - Sends a `logging/setLevel` request.
- `getPrompt(GetPromptRequest params, [RequestOptions? options])`: `Future<GetPromptResult>` - Sends a `prompts/get` request to retrieve a prompt template.
- `listPrompts({ListPromptsRequest? params, RequestOptions? options})`: `Future<ListPromptsResult>` - Sends a `prompts/list` request.
- `listResources({ListResourcesRequest? params, RequestOptions? options})`: `Future<ListResourcesResult>` - Sends a `resources/list` request.
- `listResourceTemplates({ListResourceTemplatesRequest? params, RequestOptions? options})`: `Future<ListResourceTemplatesResult>` - Sends a `resources/templates/list` request.
- `readResource(ReadResourceRequest params, [RequestOptions? options])`: `Future<ReadResourceResult>` - Sends a `resources/read` request.
- `subscribeResource(SubscribeRequest params, [RequestOptions? options])`: `Future<EmptyResult>` - Sends a `resources/subscribe` request.
- `unsubscribeResource(UnsubscribeRequest params, [RequestOptions? options])`: `Future<EmptyResult>` - Sends a `resources/unsubscribe` request.
- `callTool(CallToolRequest params, {RequestOptions? options})`: `Future<CallToolResult>` - Sends a `tools/call` request to invoke a tool.
- `listTools({ListToolsRequest? params, RequestOptions? options})`: `Future<ListToolsResult>` - Sends a `tools/list` request.
- `close()`: `Future<void>` - Clears cached server state and closes the connection.
- `sendRootsListChanged()`: `Future<void>` - Sends a `notifications/roots/list_changed` notification.

**Tool Call Example:**
```dart
final result = await client.callTool(
  CallToolRequest(
    name: 'get_weather',
    arguments: {'city': 'San Francisco'},
  ),
);

if (!result.isError) {
  print('Weather: ${result.content}');
}
```

### StdioServerParameters
Configuration parameters for launching a server process for stdio communication.

**Fields:**
- `command`: `String` - The executable command to run (e.g., `'node'`, `'python'`, `'dart'`).
- `args`: `List<String>` - Command line arguments to pass to the executable.
- `environment`: `Map<String, String>?` - Environment variables for the process.
- `stderrMode`: `ProcessStartMode` - How to handle stderr. Defaults to `inheritStdio`. Use `normal` to capture via `transport.stderr`.
- `workingDirectory`: `String?` - The working directory for the process.

**Constructors:**
- `StdioServerParameters({required String command, List<String> args = const [], Map<String, String>? environment, ProcessStartMode stderrMode = ProcessStartMode.inheritStdio, String? workingDirectory})`

### StdioClientTransport
Client transport for stdio: connects to a server by spawning a process and communicating with it over stdin/stdout pipes.

**Fields:**
- `onclose`: `void Function()?` - Callback for when the process exits.
- `onerror`: `void Function(Error error)?` - Callback for reporting process or stream errors.
- `onmessage`: `void Function(JsonRpcMessage message)?` - Callback for received messages.
- `stderr`: `Stream<List<int>>?` - Access to the child process's stderr stream (requires `ProcessStartMode.normal`).

**Constructors:**
- `StdioClientTransport(StdioServerParameters serverParams)`

**Example:**
```dart
import 'dart:io';
import 'package:mcp_dart/mcp_dart.dart';

final transport = StdioClientTransport(
  const StdioServerParameters(
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-weather'],
    environment: {'API_KEY': 'your-key'},
  ),
);

final client = McpClient(const Implementation(name: 'weather-client', version: '1.0.0'));
await client.connect(transport);
```

### StreamableHttpClientTransportOptions
Configuration options for the `StreamableHttpClientTransport`.

**Fields:**
- `authProvider`: `OAuthClientProvider?` - Provider for OAuth-based authentication.
- `requestInit`: `Map<String, dynamic>?` - Custom headers or other HTTP request parameters.
- `reconnectionOptions`: `StreamableHttpReconnectionOptions?` - Reconnection strategy settings.
- `sessionId`: `String?` - A pre-existing session ID to resume.
- `httpTimeout`: `Duration?` - Timeout for individual HTTP requests (defaults to 30s).

**Constructors:**
- `StreamableHttpClientTransportOptions({OAuthClientProvider? authProvider, Map<String, dynamic>? requestInit, StreamableHttpReconnectionOptions? reconnectionOptions, String? sessionId, Duration? httpTimeout})`

### StreamableHttpClientTransport
Client transport for Streamable HTTP: connects to a server using HTTP POST for sending and GET (SSE) for receiving messages.

**Fields:**
- `onclose`: `void Function()?` - Callback for connection closure.
- `onerror`: `void Function(Error error)?` - Callback for transport errors.
- `onmessage`: `void Function(JsonRpcMessage message)?` - Callback for incoming messages.
- `sessionId`: `String?` - The current active session ID.

**Constructors:**
- `StreamableHttpClientTransport(Uri url, {StreamableHttpClientTransportOptions? opts})`

**Methods:**
- `finishAuth(String authorizationCode)`: `Future<void>` - Exchanges an authorization code for tokens.
- `terminateSession()`: `Future<void>` - Sends a `DELETE` request to explicitly end the session.

**Example:**
```dart
import 'package:mcp_dart/mcp_dart.dart';

final transport = StreamableHttpClientTransport(
  Uri.parse('https://mcp.example.com/api'),
  opts: StreamableHttpClientTransportOptions(
    httpTimeout: const Duration(seconds: 10),
  ),
);

final client = McpClient(const Implementation(name: 'http-client', version: '1.0.0'));
await client.connect(transport);
```

### StreamableHttpError
Error thrown for Streamable HTTP transport issues.

**Fields:**
- `code`: `int?` - The HTTP status code (e.g., 404, 500).
- `message`: `String` - A descriptive error message.

### UnauthorizedError
Specialized error indicating that authentication is required or failed.

**Fields:**
- `message`: `String?` - Optional detail about the auth failure.

### OAuthClientProvider
Abstract interface for providing OAuth tokens and handling redirects.

**Methods:**
- `tokens()`: `Future<OAuthTokens?>` - Returns current access/refresh tokens.
- `redirectToAuthorization()`: `Future<void>` - Navigates the user to the provider's auth page.

### OAuthTokens
Container for OAuth credentials.

**Fields:**
- `accessToken`: `String` - The active access token.
- `refreshToken`: `String?` - Optional refresh token.

### TaskClient
A high-level wrapper to simplify task-based tool calls. It handles polling and state management for long-running tasks.

**Fields:**
- `client`: `McpClient` - The underlying client.

**Constructors:**
- `TaskClient(McpClient client)`

**Methods:**
- `callToolStream(String name, Map<String, dynamic> arguments, {Map<String, dynamic>? task})`: `Stream<TaskStreamMessage>` - Invokes a tool and returns a stream of status updates and final result.
- `listTasks()`: `Future<List<Task>>` - Lists all active tasks on the server.
- `cancelTask(String taskId)`: `Future<void>` - Cancels a running task.

**Example:**
```dart
final taskClient = TaskClient(client);

final stream = taskClient.callToolStream(
  'process_video',
  {'url': 'https://example.com/video.mp4'},
  task: {'ttl': 600000}, // Request task augmentation
);

await for (final message in stream) {
  if (message is TaskCreatedMessage) {
    print('Task created: ${message.task.taskId}');
  } else if (message is TaskStatusMessage) {
    print('Status: ${message.task.status}');
  } else if (message is TaskResultMessage) {
    print('Result: ${message.result.content}');
  }
}
```

---

## 2. Enums
*(No public enums are directly defined in this module, see common types in shared module)*

## 3. Extensions
*(No public extensions are directly defined in this module)*

## 4. Top-Level Functions

- **auth** -- Performs authentication with the provided OAuth client.
  - Signature: `Future<AuthResult> auth(OAuthClientProvider provider, {required Uri serverUrl, String? authorizationCode})`
  - Returns: `Future<AuthResult>`

## 5. Typedefs

- **ClientOptions** -- Deprecated alias for `McpClientOptions`. Use `McpClientOptions` instead.
- **Client** -- Deprecated alias for `McpClient`. Use `McpClient` instead.
- **AuthResult** -- Result of an authentication attempt (alias for `String`).
- **ProgressCallback** -- Callback for progress notifications. Signature: `void Function(Progress progress)`.

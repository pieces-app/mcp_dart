# mcp_dart Server API Reference

The Server module is owned by the `mcp_dart` package. It provides the Model Context Protocol (MCP) server implementation and handles protocol interactions, transports, and tool/resource/prompt registration. It seamlessly integrates with both `dart:io` and `shelf` ecosystems.

## Multi-Package Context
- **mcp_dart**: The core package containing this module.
- **mcp_dart_cli**: A sub-package (`packages/mcp_dart_cli/`) that provides CLI tools and templates utilizing this server implementation.

## 1. Messages & Types

### McpServerOptions
Options for configuring the MCP Server.
- `capabilities` (ServerCapabilities?): Capabilities to advertise as being supported by this server.
- `instructions` (String?): Optional instructions describing how to use the server and its features.
- `enforceStrictCapabilities` (bool): Whether to strictly enforce capability checks.

### CompletableDef
Definition for a completable argument.
- `complete` (CompleteCallback): The callback to invoke to get completion suggestions.

### CompletableField
A field that supports auto-completion.
- `def` (CompletableDef): The completion definition.
- `underlyingType` (Type): The underlying type of the field (defaults to `String`).

### ResourceMetadata
Metadata for a resource.
- `description` (String?): A description of the resource.
- `mimeType` (String?): The MIME type of the resource.

### RegisteredResource (Interface)
An interface for a registered resource, allowing for lifecycle management.
- `name` (String): The name of the resource.
- `uri` (String): The unique URI of the resource.
- `enabled` (bool): Whether the resource is currently enabled.
- `enable()`: Enables the resource.
- `disable()`: Disables the resource.
- `remove()`: Removes the resource from the server.
- `update(...)`: Updates the resource configuration.

### RegisteredTool (Interface)
An interface for a registered tool.
- `name` (String): The name of the tool.
- `description` (String?): The description of the tool.
- `inputSchema` (ToolInputSchema?): The input schema for the tool.
- `enabled` (bool): Whether the tool is currently enabled.
- `enable()` / `disable()` / `remove()`: Lifecycle methods.
- `update(...)`: Updates the tool configuration.

### RegisteredPrompt (Interface)
An interface for a registered prompt.
- `name` (String): The name of the prompt.
- `description` (String?): The description of the prompt.
- `enabled` (bool): Whether the prompt is currently enabled.
- `enable()` / `disable()` / `remove()`: Lifecycle methods.
- `update(...)`: Updates the prompt configuration.

### PromptArgumentDefinition
Definition of an argument for a prompt.
- `description` (String?): Description of what the argument is for.
- `required` (bool): Whether the argument is required.
- `type` (Type): The expected Dart type (e.g., `String`, `int`).
- `completable` (CompletableField?): Configuration for auto-completion.

### StreamableHTTPServerTransportOptions
Configuration options for `StreamableHTTPServerTransport`.
- `sessionIdGenerator` (String? Function()?): Generates unique session IDs.
- `onsessioninitialized` (FutureOr<void> Function(String)?): Callback when a session is initialized.
- `enableJsonResponse` (bool): If true, returns JSON responses instead of SSE.
- `eventStore` (EventStore?): Event store for resumability.
- `enableDnsRebindingProtection` (bool): Enables protection against DNS rebinding.
- `allowedHosts` (Set<String>?): Explicit host allowlist.
- `allowedOrigins` (Set<String>?): Explicit origin allowlist.
- `keepAliveInterval` (int?): SSE keep-alive interval in seconds (default: 25).

## 2. Services & Core Classes

### McpServer
The primary class for implementing an MCP server.

**Lifecycle:**
- `connect(Transport transport)`: Connects to a transport (e.g., Stdio, SSE).
- `close()`: Closes the server and transport.

**Registration:**
- `registerTool(String name, {String? description, ToolInputSchema? inputSchema, required ToolFunction callback})`: Registers a standard tool.
- `registerResource(String name, String uri, ResourceMetadata? metadata, ReadResourceCallback readCallback)`: Registers a static resource.
- `registerResourceTemplate(String name, ResourceTemplateRegistration template, ResourceMetadata? metadata, ReadResourceTemplateCallback readCallback)`: Registers a dynamic resource via URI template.
- `registerPrompt(String name, {String? description, Map<String, PromptArgumentDefinition>? argsSchema, required PromptCallback callback})`: Registers a prompt.

**Notifications:**
- `sendLoggingMessage(LoggingMessageNotification params)`: Sends a log message to the client.
- `sendResourceListChanged()`: Notifies client of resource changes.
- `sendToolListChanged()`: Notifies client of tool changes.
- `sendPromptListChanged()`: Notifies client of prompt changes.

### ExperimentalMcpServerTasks
Accessible via `server.experimental`. Handles long-running tasks.
- `registerToolTask(...)`: Registers a tool that returns a `Task` instead of an immediate result.
- `elicitForTask(String taskId, ElicitRequest params)`: Requests input from the client on behalf of a task.
- `createMessageForTask(String taskId, CreateMessageRequest params)`: Requests sampling from the client for a task.

### StreamableMcpServer
A manager for multi-session Streamable HTTP servers.
- `start()`: Binds the HTTP server and starts listening.
- `stop()`: Stops the server and closes all sessions.

## 3. Transports

### StdioServerTransport
Standard I/O transport. Used when the server is spawned as a child process.
```dart
final transport = StdioServerTransport();
await server.connect(transport);
```

### SseServerTransport
Server-Sent Events transport for web-based or remote clients.
```dart
final transport = SseServerTransport(
  response: httpRequest.response,
  messageEndpointPath: '/messages',
);
await server.connect(transport);
```

### StreamableHTTPServerTransport
Implements the MCP Streamable HTTP specification. Supports both `dart:io` and `shelf`.

## 4. Callbacks & Interfaces

### ToolFunction
`FutureOr<CallToolResult> Function(Map<String, dynamic> args, RequestHandlerExtra extra)`

### ToolTaskHandler (Interface)
Used for task-based tools.
- `createTask(Map<String, dynamic>? args, RequestHandlerExtra? extra)`
- `getTask(String taskId, RequestHandlerExtra? extra)`
- `cancelTask(String taskId, RequestHandlerExtra? extra)`
- `getTaskResult(String taskId, RequestHandlerExtra? extra)`

### EventStore (Interface)
Interface for providing resumability in `StreamableHTTPServerTransport`.
- `storeEvent(StreamId streamId, JsonRpcMessage message)`
- `replayEventsAfter(EventId lastEventId, {required Future<void> Function(EventId, JsonRpcMessage) send})`

## 5. Examples

### Basic Tool Registration
```dart
server.registerTool(
  'fetch_data',
  description: 'Fetches data from a remote source',
  inputSchema: ToolInputSchema(
    properties: {
      'url': JsonSchema(type: 'string', description: 'The URL to fetch'),
      'timeout': JsonSchema(type: 'integer', description: 'Timeout in ms'),
    },
    required: ['url'],
  ),
  callback: (args, extra) async {
    final url = args['url'] as String;
    // Implementation...
    return CallToolResult(
      content: [TextContent(text: 'Data from $url')],
    );
  },
);
```

### Resource Template with Completions
```dart
server.registerResourceTemplate(
  'logs',
  ResourceTemplateRegistration(
    'logs://{appId}/{level}',
    listCallback: (extra) => ListResourcesResult(resources: []),
    completeCallbacks: {
      'level': (current) => ['debug', 'info', 'warn', 'error'],
    },
  ),
  const (description: 'Application logs', mimeType: 'text/plain'),
  (uri, vars, extra) {
    final appId = vars['appId'];
    final level = vars['level'];
    return ReadResourceResult(
      contents: [TextResourceContents(uri: uri.toString(), text: 'Logs for $appId at $level')],
    );
  },
);
```

### Using Shelf Adapter
```dart
final transport = StreamableHTTPServerTransport(
  options: StreamableHTTPServerTransportOptions(
    sessionIdGenerator: () => generateUUID(),
  ),
);

// In a shelf handler:
Future<Response> handleMcp(Request request) async {
  return await transport.handleShelfRequest(request);
}
```

### Protobuf Field Naming (camelCase)
When working with types that originate from protobuf definitions (like sampling or elicitation results), always use `camelCase` for Dart field access:

```dart
// Correct: use camelCase fields
final result = await server.elicitInput(ElicitRequest(
  mode: ElicitationMode.form,
  requestedSchema: schema,
));

if (result.accepted) {
  print(result.content); // Accessing fields like dynamicTemplateData or replyToList
}
```

## 6. Installation

```yaml
dependencies:
  mcp_dart:
    git:
      url: https://github.com/pieces-app/mcp_dart.git
```

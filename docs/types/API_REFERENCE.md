# API Reference: Types Module

## Multi-Package Architecture

This module is owned by the core **`mcp_dart`** package. It defines the foundational Model Context Protocol (MCP) data structures, capabilities, and JSON-RPC message formats used across the entire ecosystem.

**Integration:**
- **`mcp_dart`**: The core library uses these types for all internal protocol logic, transport handling, and high-level client/server abstractions.
- **`mcp_dart_cli`**: The CLI package (located in `packages/mcp_dart_cli/`) depends on this module to provide type-safe command-line interfaces for interacting with MCP servers and clients. It utilizes these types for command arguments, result formatting, and configuration.

All protocol messages, arguments, and content types exchanged between clients and servers in this repository are instantiated from this module.

---

## 1. Constants & Type Aliases

### Protocol Constants
- `latestProtocolVersion`: The latest version of the MCP supported (currently "2025-11-25").
- `supportedProtocolVersions`: List of all supported MCP versions.
- `jsonRpcVersion`: Always "2.0".

### Type Aliases (Typedefs)
- `RequestId`: `dynamic` (String or int)
- `ProgressToken`: `dynamic`
- `Cursor`: `String`
- `ElicitationInputSchema`: `JsonSchema`
- `ToolInputSchema`: `JsonObject`
- `ToolOutputSchema`: `JsonObject`
- `DynamicStopReason`: `dynamic` (StopReason or String)
- `TaskStatusString`: `String`

---

## 2. Core JSON-RPC Classes

### Base Messages
- **JsonRpcMessage** -- Base class for all JSON-RPC messages.
  - **Fields**: `jsonrpc` (String)
  - **Constructors**: `JsonRpcMessage.fromJson(Map<String, dynamic> json)`
- **JsonRpcRequest** -- Base class for requests expecting a response.
  - **Fields**: `id` (RequestId), `method` (String), `params` (Map<String, dynamic>?), `meta` (Map<String, dynamic>?)
  - **Getters**: `progressToken`
- **JsonRpcNotification** -- Base class for notifications.
  - **Fields**: `method` (String), `params` (Map<String, dynamic>?), `meta` (Map<String, dynamic>?)
- **JsonRpcResponse** -- Successful response.
  - **Fields**: `id` (RequestId), `result` (Map<String, dynamic>), `meta` (Map<String, dynamic>?)
- **JsonRpcError** -- Error response.
  - **Fields**: `id` (RequestId), `error` (JsonRpcErrorData)

### Error Handling
- **JsonRpcErrorData** -- The `error` object within a `JsonRpcError`.
  - **Fields**: `code` (int), `message` (String), `data` (dynamic)
- **McpError** -- Custom exception for MCP-specific errors.
  - **Fields**: `code` (int), `message` (String), `data` (dynamic)

---

## 3. Initialization & Capabilities

### Implementation Info
- **Implementation** -- Name and version of a client/server.
  - **Fields**: `name` (String), `version` (String), `description` (String?)

### Client Capabilities
- **ClientCapabilities** -- Features supported by a client.
  - **Fields**: `experimental` (Map?), `sampling` (ClientCapabilitiesSampling?), `roots` (ClientCapabilitiesRoots?), `elicitation` (ClientElicitation?), `tasks` (ClientCapabilitiesTasks?), `extensions` (Map?)
- **ClientCapabilitiesSampling** -- `tools` (ClientCapabilitiesSamplingTools?), `context` (ClientCapabilitiesSamplingContext?); both are empty-object markers on the wire, per MCP 2025-11-25
- **ClientCapabilitiesRoots** -- `listChanged` (bool?)
- **ClientElicitation** -- `form` (ClientElicitationForm?), `url` (ClientElicitationUrl?)
- **ClientCapabilitiesTasks** -- `cancel` (bool?), `list` (bool?), `requests` (ClientCapabilitiesTasksRequests?)

### Server Capabilities
- **ServerCapabilities** -- Features supported by a server.
  - **Fields**: `experimental` (Map?), `logging` (Map?), `prompts` (ServerCapabilitiesPrompts?), `resources` (ServerCapabilitiesResources?), `tools` (ServerCapabilitiesTools?), `completions` (ServerCapabilitiesCompletions?), `tasks` (ServerCapabilitiesTasks?), `elicitation` (ServerCapabilitiesElicitation?), `extensions` (Map?)

---

## 4. Content & Resources

### Content Types
- **Content** -- Sealed base class for content parts.
  - **Subclasses**: `TextContent`, `ImageContent`, `AudioContent`, `EmbeddedResource`, `ResourceLink`.
- **TextContent** -- `text` (String)
- **ImageContent** -- `data` (String - Base64), `mimeType` (String), `theme` (String?)
- **AudioContent** -- `data` (String - Base64), `mimeType` (String)
- **EmbeddedResource** -- `resource` (ResourceContents)
- **ResourceLink** -- `uri` (String), `name` (String), `title` (String?), `description` (String?), `mimeType` (String?), `size` (int?), `icons` (List<McpIcon>?), `annotations` (Map?), `meta` (Map?)

### Resource Objects
- **Resource** -- `uri` (String), `name` (String), `description` (String?), `mimeType` (String?), `icon` (ImageContent?), `icons` (List<McpIcon>?), `annotations` (ResourceAnnotations?)
- **ResourceTemplate** -- `uriTemplate` (String), `name` (String), `description` (String?), `mimeType` (String?), `icon` (ImageContent?), `icons` (List<McpIcon>?), `annotations` (ResourceAnnotations?)
- **ResourceContents** -- `uri` (String), `mimeType` (String?)
  - **Subclasses**: `TextResourceContents`, `BlobResourceContents`, `UnknownResourceContents`.
- **McpIcon** -- `src` (String), `mimeType` (String?), `sizes` (List<String>?), `theme` (IconTheme?)

---

## 5. Tools & Prompts

### Tools
- **Tool** -- `name` (String), `description` (String?), `inputSchema` (JsonSchema), `outputSchema` (JsonSchema?), `annotations` (ToolAnnotations?), `meta` (Map?), `execution` (ToolExecution?), `icon` (ImageContent?), `icons` (List<McpIcon>?)
- **ToolAnnotations** -- `title` (String?), `readOnlyHint` (bool), `destructiveHint` (bool), `idempotentHint` (bool), `openWorldHint` (bool), `priority` (double?), `audience` (List<String>?)
- **ToolExecution** -- `taskSupport` (String - "forbidden" | "optional" | "required")

### Prompts
- **Prompt** -- `name` (String), `description` (String?), `arguments` (List<PromptArgument>?), `icon` (ImageContent?), `icons` (List<McpIcon>?)
- **PromptArgument** -- `name` (String), `description` (String?), `required` (bool?)
- **PromptMessage** -- `role` (PromptMessageRole), `content` (Content)

---

## 6. Sampling & Completions

### Sampling
- **CreateMessageRequest** -- `messages` (List<SamplingMessage>), `systemPrompt` (String?), `includeContext` (IncludeContext?), `temperature` (double?), `maxTokens` (int), `stopSequences` (List<String>?), `metadata` (Map?), `modelPreferences` (ModelPreferences?), `tools` (List<Tool>?), `toolChoice` (Map?)
- **ModelPreferences** -- `hints` (List<ModelHint>?), `costPriority` (double?), `speedPriority` (double?), `intelligencePriority` (double?)
- **SamplingContent** -- `type` (String)
  - **Subclasses**: `SamplingTextContent`, `SamplingImageContent`, `SamplingToolUseContent`, `SamplingToolResultContent`.

### Completions
- **Reference** -- Autocompletion target.
  - **Subclasses**: `ResourceReference` (`uri`), `PromptReference` (`name`).
- **ArgumentCompletionInfo** -- `name` (String), `value` (String)
- **CompletionResultData** -- `values` (List<String>), `total` (int?), `hasMore` (bool?)

---

## 7. Tasks & Elicitation

### Tasks
- **Task** -- `taskId` (String), `status` (TaskStatus), `statusMessage` (String?), `ttl` (int?), `pollInterval` (int?), `createdAt` (String?), `lastUpdatedAt` (String?), `meta` (Map?)
- **TaskStreamMessage** -- Stream events for task execution.
  - **Subclasses**: `TaskCreatedMessage`, `TaskStatusMessage`, `TaskResultMessage`, `TaskErrorMessage`.

### Elicitation
- **ElicitRequest** -- Server-initiated input request.
  - **Fields**: `mode` (ElicitationMode?), `message` (String), `requestedSchema` (JsonSchema?), `url` (String?), `elicitationId` (String?)
- **ElicitResult** -- `action` (String - "accept" | "decline" | "cancel"), `content` (Map?), `url` (String?), `elicitationId` (String?)

---

## 8. Enums & Extensions

### Enums
- **IconTheme**: `light`, `dark`
- **ElicitationMode**: `form`, `url`
- **ErrorCode**: Standard JSON-RPC and MCP error codes (e.g., `urlElicitationRequired` = -32042).
- **LoggingLevel**: `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency`
- **PromptMessageRole**: `user`, `assistant`
- **SamplingMessageRole**: `user`, `assistant`
- **IncludeContext**: `none`, `thisServer`, `allServers`
- **StopReason**: `endTurn`, `stopSequence`, `maxTokens`
- **TaskStatus**: `working`, `inputRequired`, `completed`, `failed`, `cancelled`

### Extensions
- **TaskStatusName** on **TaskStatus**:
  - `name`: String representation.
  - `isTerminal`: `true` if completed, failed, or cancelled.
  - `TaskStatusName.fromString(String status)`: Static conversion.

---

## 9. Usage Examples

### Constructing an MCP Tool
```dart
import 'package:mcp_dart/mcp_dart.dart';

final tool = Tool(
  name: 'fetch_stock_price',
  description: 'Retrieves the current stock price for a given ticker symbol.',
  inputSchema: JsonSchema(
    type: SchemaType.object,
    properties: {
      'ticker': JsonSchema(
        type: SchemaType.string,
        description: 'The stock ticker symbol (e.g., AAPL, GOOGL)',
      ),
    },
    required: ['ticker'],
  ),
  annotations: ToolAnnotations(
    title: 'Stock Price Fetcher',
    readOnlyHint: true,
  ),
);
```

### Initializing a Client
```dart
import 'package:mcp_dart/mcp_dart.dart';

final initRequest = InitializeRequest(
  protocolVersion: latestProtocolVersion,
  clientInfo: Implementation(
    name: 'ExampleClient',
    version: '1.0.0',
  ),
  capabilities: ClientCapabilities(
    roots: ClientCapabilitiesRoots(listChanged: true),
    sampling: ClientCapabilitiesSampling(tools: ClientCapabilitiesSamplingTools()),
    elicitation: ClientElicitation.all(),
  ),
);
```

### Handling a Tool Result
```dart
import 'package:mcp_dart/mcp_dart.dart';

// Creating a successful result with text content
final result = CallToolResult(
  content: [
    TextContent(text: 'The current price of AAPL is $150.00'),
  ],
);

// Creating an error result
final errorResult = CallToolResult(
  content: [
    TextContent(text: 'Failed to fetch price: Ticker not found'),
  ],
  isError: true,
);
```

### Creating an Elicitation Request (URL Mode)
```dart
import 'package:mcp_dart/mcp_dart.dart';

final elicitRequest = ElicitRequest.url(
  message: 'Please authorize access to your account.',
  url: 'https://example.com/auth',
  elicitationId: 'auth-task-123',
);
```

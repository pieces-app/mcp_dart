# Types Module Quickstart

## 1. Overview

The **Types** module provides the core data structures and JSON-RPC message definitions for the Model Context Protocol (MCP). It features strongly-typed Dart domain models for initialization, resources, prompts, tools, sampling, tasks, elicitation, and logging, offering robust `fromJson` and `toJson` serialization utilities.

### Owning Package: `mcp_dart`

This module is the foundational layer of the `mcp_dart` package. It acts as the shared vocabulary across the repository, ensuring that every component—from the low-level transports to the high-level CLI—speaks the same language.

### Integration with `mcp_dart_cli`

The `mcp_dart_cli` package (`packages/mcp_dart_cli/`) utilizes these types to:
- Parse incoming JSON-RPC messages from standard I/O.
- Validate command-line arguments against expected MCP schemas.
- Provide a consistent interface for tool and prompt discovery in terminal environments.

## 2. Import

Import the specific domain files or the main `json_rpc.dart` for the message envelopes:

```dart
// Core JSON-RPC structures
import 'package:mcp_dart/src/types/json_rpc.dart';

// Domain-specific types
import 'package:mcp_dart/src/types/initialization.dart';
import 'package:mcp_dart/src/types/tools.dart';
import 'package:mcp_dart/src/types/resources.dart';
import 'package:mcp_dart/src/types/prompts.dart';
import 'package:mcp_dart/src/types/content.dart';
import 'package:mcp_dart/src/types/sampling.dart';
import 'package:mcp_dart/src/types/tasks.dart';
import 'package:mcp_dart/src/types/elicitation.dart';
import 'package:mcp_dart/src/types/logging.dart';
import 'package:mcp_dart/src/types/roots.dart';
import 'package:mcp_dart/src/types/completion.dart';
import 'package:mcp_dart/src/types/misc.dart';
```

## 3. Initialization and Capabilities

MCP connections begin with an `initialize` request where both parties negotiate capabilities.

```dart
import 'package:mcp_dart/src/types/initialization.dart';
import 'package:mcp_dart/src/types/json_rpc.dart';

// Define the client implementation details
final clientInfo = Implementation(
  name: 'my_mcp_client',
  version: '1.0.0',
  description: 'A custom Dart MCP client', // Optional description
);

// Define supported client capabilities
final capabilities = ClientCapabilities(
  roots: ClientCapabilitiesRoots(
    listChanged: true, // Whether the client supports notifications when roots change
  ),
  sampling: ClientCapabilitiesSampling(
    tools: true, // Whether the client supports sampling with tools
  ),
  elicitation: ClientElicitation(
    form: ClientElicitationForm(
      applyDefaults: true, // Support applying default values from requested schema
    ),
    url: ClientElicitationUrl(),
  ),
  tasks: ClientCapabilitiesTasks(
    list: true,
    cancel: true,
    requests: ClientCapabilitiesTasksRequests(
      elicitation: ClientCapabilitiesTasksElicitation(
        create: ClientCapabilitiesTasksElicitationCreate(),
      ),
    ),
  ),
);

// Form the initialization request
final initRequest = InitializeRequest(
  protocolVersion: latestProtocolVersion,
  capabilities: capabilities,
  clientInfo: clientInfo,
);
```

## 4. Core Domain Types

### Tools
Tools allow clients to perform actions via the server.

```dart
import 'package:mcp_dart/src/types/tools.dart';
import 'package:mcp_dart/src/shared/json_schema/json_schema.dart';

final tool = Tool(
  name: 'calculate_sum',
  description: 'Adds two numbers together.',
  inputSchema: JsonSchema.fromJson({
    'type': 'object',
    'properties': {
      'a': {'type': 'number'},
      'b': {'type': 'number'},
    },
    'required': ['a', 'b'],
  }),
  annotations: ToolAnnotations(
    priority: 1.0, // Priority of the tool (0.0 to 1.0)
    readOnlyHint: true, // Hint that the tool does not modify its environment
    destructiveHint: false, // Hint that the tool performs only additive updates
  ),
);

// Responding to a tool call
final result = CallToolResult(
  content: [TextContent(text: 'The result is 15')],
  isError: false, // Whether the tool call returned an error
);
```

### Resources
Resources provide access to files, database records, or other data.

```dart
import 'package:mcp_dart/src/types/resources.dart';

final resource = Resource(
  uri: 'file:///logs/app.log',
  name: 'App Logs',
  mimeType: 'text/plain',
  annotations: ResourceAnnotations(
    title: 'Application Runtime Logs',
    priority: 0.5,
    lastModified: '2026-03-25T12:00:00Z', // ISO 8601 timestamp
  ),
);

// Reading a resource result
final readResult = ReadResourceResult(
  contents: [
    TextResourceContents(
      uri: 'file:///logs/app.log',
      text: 'Starting application...',
    ),
  ],
);
```

### Prompts
Prompts are reusable templates for LLM interactions.

```dart
import 'package:mcp_dart/src/types/prompts.dart';

final prompt = Prompt(
  name: 'summarize_text',
  description: 'Summarizes a given block of text.',
  arguments: [
    PromptArgument(
      name: 'text',
      description: 'The text to summarize',
      required: true, // Whether this argument must be provided
    ),
  ],
);

// Getting prompt messages
final getResult = GetPromptResult(
  description: 'Summarization prompt',
  messages: [
    PromptMessage(
      role: PromptMessageRole.user,
      content: TextContent(text: 'Please summarize: ...'),
    ),
  ],
);
```

### Sampling
Sampling allows the server to request completions from an LLM via the client.

```dart
import 'package:mcp_dart/src/types/sampling.dart';

final samplingRequest = CreateMessageRequest(
  messages: [
    SamplingMessage(
      role: SamplingMessageRole.user,
      content: SamplingTextContent(text: 'What is the weather?'),
    ),
  ],
  maxTokens: 100,
  temperature: 0.7,
  modelPreferences: ModelPreferences(
    costPriority: 0.1, // Prioritize cost (0-1)
    intelligencePriority: 0.9, // Prioritize intelligence (0-1)
  ),
);
```

### Tasks
Tasks represent long-running operations.

```dart
import 'package:mcp_dart/src/types/tasks.dart';

final task = Task(
  taskId: 'task_123',
  status: TaskStatus.working,
  statusMessage: 'Processing data...',
  createdAt: '2026-03-25T10:00:00Z',
  pollInterval: 5000, // Suggested time in ms between status checks
);
```

### Elicitation
Elicitation is used to gather user input, either via forms or external URLs.

```dart
import 'package:mcp_dart/src/types/elicitation.dart';

// Form elicitation
final formRequest = ElicitRequest.form(
  message: 'Please enter your username',
  requestedSchema: JsonSchema.fromJson({'type': 'string'}),
);

// URL elicitation
final urlRequest = ElicitRequest.url(
  message: 'Please authenticate via GitHub',
  url: 'https://github.com/login/oauth/authorize',
  elicitationId: 'auth_session_456',
);
```

### Autocompletion
Provides completion options for prompts and resources.

```dart
import 'package:mcp_dart/src/types/completion.dart';

final completeRequest = CompleteRequest(
  ref: PromptReference(name: 'summarize_text'),
  argument: ArgumentCompletionInfo(
    name: 'text',
    value: 'The quick brown ',
  ),
);

final completeResult = CompleteResult(
  completion: CompletionResultData(
    values: ['fox', 'dog'],
    hasMore: false,
  ),
);
```

## 5. JSON-RPC Messaging

All operations are wrapped in JSON-RPC 2.0 envelopes.

```dart
import 'package:mcp_dart/src/types/json_rpc.dart';

// Generic parsing
void onMessage(Map<String, dynamic> json) {
  final message = JsonRpcMessage.fromJson(json);
  
  switch (message) {
    case JsonRpcRequest():
      print('Received request ${message.method} (ID: ${message.id})');
      if (message.progressToken != null) {
        print('Request supports progress updates');
      }
    case JsonRpcResponse():
      print('Received response for ID ${message.id}');
    case JsonRpcNotification():
      print('Received notification ${message.method}');
    case JsonRpcError():
      print('Error ${message.error.code}: ${message.error.message}');
  }
}

// Creating a specific request
final ping = JsonRpcPingRequest(id: 'ping_1');
print(ping.toJson());
```

## 6. Multi-Package Architecture

As part of the `mcp_dart` workspace, the **Types** module serves as the contract between packages:

- **`mcp_dart`**: The core library implementing the protocol logic.
- **`mcp_dart_cli`**: Uses these types to provide a terminal interface for MCP servers, ensuring that CLI arguments and stdio communication adhere to the protocol.

This architecture ensures that type safety is maintained across the entire repository, from core logic to external interfaces.

import 'dart:async';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:mcp_dart/src/server/mcp_server.dart';
import 'queue.dart';
import 'store.dart';

// FIX 15: Use the package's own logger instead of dart:io's stderr so the
// task session layer stays pure-Dart with no platform dependency.
final _logger = Logger('mcp_dart.server.tasks.session');

// ============================================================================
// Task Session
// ============================================================================

/// Represents a session of a running task, allowing interaction with the server.
class TaskSession {
  final McpServer server;
  final String taskId;
  final InMemoryTaskStore store;
  final InMemoryTaskMessageQueue queue;
  int _requestCounter = 0;

  TaskSession(this.server, this.taskId, this.store, this.queue);

  String _nextRequestId() => 'task-$taskId-${++_requestCounter}';

  Future<void> _sendTaskStatusNotification() async {
    final task = await store.getTask(taskId);
    if (task != null) {
      // FIX 16: Await the notification so task status is actually sent before
      // subsequent operations (like elicit/createMessage) proceed. The
      // previous fire-and-forget `.catchError` meant callers that awaited
      // _sendTaskStatusNotification could race ahead of the send.
      try {
        await server.server.notification(
          JsonRpcTaskStatusNotification(
            statusParams: TaskStatusNotification(
              taskId: taskId,
              status: task.status,
              statusMessage: task.statusMessage,
              ttl: task.ttl,
              pollInterval: task.pollInterval,
              createdAt: task.createdAt,
              lastUpdatedAt: task.lastUpdatedAt,
            ),
          ),
        );
      } catch (e) {
        _logger.warn(
          'Failed to broadcast task status notification '
          'for task $taskId: $e',
        );
      }
    }
  }

  /// Requests input from the client (Elicitation).
  Future<ElicitResult> elicit(String message, ElicitationInputSchema requestedSchema) async {
    await store.updateTaskStatus(taskId, TaskStatus.inputRequired);
    await _sendTaskStatusNotification();

    final requestId = _nextRequestId();
    final params = ElicitRequest.form(message: message, requestedSchema: requestedSchema);

    final jsonRpcRequest = JsonRpcElicitRequest(id: requestId, elicitParams: params);

    final completer = Completer<Map<String, dynamic>>();

    await queue.enqueue(
      taskId,
      ServerQueuedMessage(
        type: 'request',
        message: jsonRpcRequest,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        resolver: completer,
        originalRequestId: requestId,
      ),
      null,
    );

    try {
      final json = await completer.future;
      await store.updateTaskStatus(taskId, TaskStatus.working);
      await _sendTaskStatusNotification();
      return ElicitResult.fromJson(json);
    } catch (e) {
      await store.updateTaskStatus(taskId, TaskStatus.working);
      await _sendTaskStatusNotification();
      rethrow;
    }
  }

  /// Requests an LLM sampling message (Sampling).
  Future<CreateMessageResult> createMessage(List<SamplingMessage> messages, int maxTokens) async {
    await store.updateTaskStatus(taskId, TaskStatus.inputRequired);
    await _sendTaskStatusNotification();

    final requestId = _nextRequestId();
    final params = CreateMessageRequest(messages: messages, maxTokens: maxTokens);

    final jsonRpcRequest = JsonRpcCreateMessageRequest(id: requestId, createParams: params);

    final completer = Completer<Map<String, dynamic>>();

    await queue.enqueue(
      taskId,
      ServerQueuedMessage(
        type: 'request',
        message: jsonRpcRequest,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        resolver: completer,
        originalRequestId: requestId,
      ),
      null,
    );

    try {
      final json = await completer.future;
      await store.updateTaskStatus(taskId, TaskStatus.working);
      await _sendTaskStatusNotification();
      return CreateMessageResult.fromJson(json);
    } catch (e) {
      await store.updateTaskStatus(taskId, TaskStatus.working);
      await _sendTaskStatusNotification();
      rethrow;
    }
  }
}

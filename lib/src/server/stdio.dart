import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/logging.dart';
import 'package:mcp_dart/src/shared/stdio.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

final _logger = Logger("mcp_dart.server.stdio");

/// Server transport for stdio: communicates with a MCP client by reading
/// from the current process's standard input ([io.stdin]) and writing to
/// standard output ([io.stdout]).
///
/// This transport is primarily intended for server processes that are directly
/// invoked by a client managing the process lifecycle.
///
/// Note: This transport assumes exclusive control over stdin/stdout for JSON-RPC
/// communication while active. Other uses of stdin/stdout might interfere.
class StdioServerTransport implements Transport {
  final io.Stdin _stdin;
  final io.IOSink _stdout;

  /// Buffer for incoming data from stdin.
  final ReadBuffer _readBuffer = ReadBuffer();

  /// Flag to prevent multiple starts.
  bool _started = false;

  /// Subscription to stdin data stream.
  StreamSubscription<List<int>>? _stdinSubscription;

  /// Callback for when the connection is closed.
  @override
  void Function()? onclose;

  /// Callback for reporting errors.
  @override
  void Function(Error error)? onerror;

  /// Callback for received messages.
  @override
  void Function(JsonRpcMessage message)? onmessage;

  /// Session ID is not typically applicable to stdio transport.
  @override
  String? get sessionId => null;

  /// Creates a new stdio server transport.
  ///
  /// By default, uses [io.stdin] and [io.stdout] from `dart:io`.
  /// Provide alternative streams for testing or embedding purposes.
  StdioServerTransport({io.Stdin? stdin, io.IOSink? stdout})
    : _stdin = stdin ?? io.stdin,
      _stdout = stdout ?? io.stdout;

  /// Starts listening for messages on stdin.
  ///
  /// Attaches listeners to the stdin stream to process incoming data.
  /// Throws [StateError] if already started.
  @override
  Future<void> start() async {
    if (_started) {
      throw StateError(
        "StdioServerTransport already started! If using Server class, note that connect() calls start() automatically.",
      );
    }
    _started = true;

    _stdinSubscription = _stdin.listen(_ondata, onError: _onErrorCallback, onDone: _onStdinDone, cancelOnError: false);
  }

  /// Internal callback for handling data chunks from stdin.
  void _ondata(List<int> chunk) {
    if (chunk is! Uint8List) {
      chunk = Uint8List.fromList(chunk);
    }
    // FIX: Check append() return value — false means the buffer overflowed
    // its size limit. Report the error and tear down the transport rather
    // than silently processing a cleared (empty) buffer.
    if (!_readBuffer.append(chunk)) {
      onerror?.call(StateError('ReadBuffer overflow: exceeded ${_readBuffer.maxBufferSize} bytes. Closing transport.'));
      close();
      return;
    }
    _processReadBuffer();
  }

  /// Internal callback for handling errors on the stdin stream.
  void _onErrorCallback(dynamic error, StackTrace stackTrace) {
    final Error dartError = (error is Error) ? error : StateError("Stdin error: $error\n$stackTrace");
    try {
      onerror?.call(dartError);
    } catch (e) {
      _logger.warn("Error within onerror handler: $e");
    }
    close();
  }

  /// Internal callback for when the stdin stream is closed.
  void _onStdinDone() {
    _logger.debug("Stdin closed.");
    close();
  }

  /// Processes the internal read buffer, attempting to parse complete messages.
  void _processReadBuffer() {
    while (true) {
      try {
        final message = _readBuffer.readMessage();
        if (message == null) {
          break;
        }
        try {
          onmessage?.call(message);
        } catch (e) {
          _logger.warn("Error within onmessage handler: $e");
          onerror?.call(StateError("Error in onmessage handler: $e"));
        }
        // FIX 13: Catch MalformedLineException separately so a single garbled
        // line (e.g. invalid UTF-8) is logged and skipped without escalating to
        // onerror, which could tear down the transport. ReadBuffer already
        // advances past the bad line, so we just continue to the next iteration.
      } on MalformedLineException catch (e) {
        _logger.warn("Skipping malformed line: $e");
      } catch (error) {
        final Error dartError = (error is Error) ? error : StateError("Message parsing error: $error");
        try {
          onerror?.call(dartError);
        } catch (e) {
          _logger.warn("Error within onerror handler during parsing: $e");
        }
        _logger.warn("StdioServerTransport: Error processing read buffer: $dartError. Attempting to continue.");
        // FIX: readMessage() already advanced the buffer past the bad line
        // before deserializeMessage() threw, so continuing is safe and
        // prevents stranding valid messages that remain in the buffer.
        continue;
      }
    }
  }

  /// Closes the transport by detaching from stdin and invoking [onclose].
  ///
  /// Note: This does not close the actual [io.stdin] or [io.stdout] streams,
  /// as they might be shared by other parts of the application. It only stops
  /// this transport from listening and interacting with them.
  @override
  Future<void> close() async {
    if (!_started) {
      return;
    }

    // Set flag before cancelling subscriptions to prevent double-close race
    // conditions: _onStdinDone or _onErrorCallback may re-enter close() during
    // cancellation. This matches the pattern in client/stdio.dart.
    _started = false;

    // Try-caught so a throwing cancel() (e.g. from an already-errored
    // stream) doesn't prevent the remaining cleanup (buffer clear,
    // onclose) from running.
    try {
      await _stdinSubscription?.cancel();
    } catch (e) {
      _logger.warn('Error cancelling stdin subscription: $e');
    }
    _stdinSubscription = null;

    _readBuffer.clear();

    try {
      onclose?.call();
    } catch (e) {
      _logger.warn("Error within onclose handler: $e");
    }
  }

  /// Sends a [JsonRpcMessage] to the client by writing its serialized form
  /// (JSON string followed by newline) to stdout.
  ///
  /// Returns a Future that completes when the message has been written and
  /// flushed to the output stream.
  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    // Throw rather than silently dropping messages — matches the Transport
    // contract enforced by StdioClientTransport and StreamableHTTPServerTransport.
    if (!_started) {
      throw StateError('Cannot send message: StdioServerTransport is not running.');
    }
    try {
      final jsonString = serializeMessage(message);
      _stdout.write(jsonString);
      await _stdout.flush();
    } catch (error) {
      final Error dartError = (error is Error) ? error : StateError("Failed to send message: $error");
      try {
        onerror?.call(dartError);
      } catch (e) {
        _logger.warn("Error within onerror handler during send: $e");
      }
      throw dartError;
    }
  }
}

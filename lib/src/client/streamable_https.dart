import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:mcp_dart/src/shared/transport.dart';
import 'package:mcp_dart/src/types.dart';

/// Default reconnection options for StreamableHTTP connections
const _defaultStreamableHttpReconnectionOptions = StreamableHttpReconnectionOptions(
  initialReconnectionDelay: 1000,
  maxReconnectionDelay: 30000,
  reconnectionDelayGrowFactor: 1.5,
  maxRetries: 2,
);

/// Error thrown for Streamable HTTP issues
class StreamableHttpError extends Error {
  /// HTTP status code if applicable
  final int? code;

  /// Error message
  final String message;

  StreamableHttpError(this.code, this.message);

  @override
  String toString() => 'Streamable HTTP error: $message';
}

/// Options for starting or authenticating an SSE connection
class StartSseOptions {
  /// The resumption token used to continue long-running requests that were interrupted.
  /// This allows clients to reconnect and continue from where they left off.
  final String? resumptionToken;

  /// A callback that is invoked when the resumption token changes.
  /// This allows clients to persist the latest token for potential reconnection.
  final void Function(String token)? onResumptionToken;

  /// Override Message ID to associate with the replay message
  /// so that response can be associated with the new resumed request.
  final dynamic replayMessageId;

  /// Whether to attempt reconnection when the stream closes.
  /// Default is true.
  final bool shouldReconnect;

  const StartSseOptions({
    this.resumptionToken,
    this.onResumptionToken,
    this.replayMessageId,
    this.shouldReconnect = true,
  });
}

/// Configuration options for reconnection behavior of the StreamableHttpClientTransport.
class StreamableHttpReconnectionOptions {
  /// Maximum backoff time between reconnection attempts in milliseconds.
  /// Default is 30000 (30 seconds).
  final int maxReconnectionDelay;

  /// Initial backoff time between reconnection attempts in milliseconds.
  /// Default is 1000 (1 second).
  final int initialReconnectionDelay;

  /// The factor by which the reconnection delay increases after each attempt.
  /// Default is 1.5.
  final double reconnectionDelayGrowFactor;

  /// Maximum number of reconnection attempts before giving up.
  /// Default is 2.
  final int maxRetries;

  const StreamableHttpReconnectionOptions({
    required this.maxReconnectionDelay,
    required this.initialReconnectionDelay,
    required this.reconnectionDelayGrowFactor,
    required this.maxRetries,
  });
}

/// Configuration options for the `StreamableHttpClientTransport`.
class StreamableHttpClientTransportOptions {
  /// An OAuth client provider to use for authentication.
  ///
  /// When an `authProvider` is specified and the connection is started:
  /// 1. The connection is attempted with any existing access token from the `authProvider`.
  /// 2. If the access token has expired, the `authProvider` is used to refresh the token.
  /// 3. If token refresh fails or no access token exists, and auth is required,
  ///    `OAuthClientProvider.redirectToAuthorization` is called, and an `UnauthorizedError`
  ///    will be thrown from `connect`/`start`.
  ///
  /// After the user has finished authorizing via their user agent, and is redirected
  /// back to the MCP client application, call `StreamableHttpClientTransport.finishAuth`
  /// with the authorization code before retrying the connection.
  ///
  /// If an `authProvider` is not provided, and auth is required, an `UnauthorizedError`
  /// will be thrown.
  ///
  /// `UnauthorizedError` might also be thrown when sending any message over the transport,
  /// indicating that the session has expired, and needs to be re-authed and reconnected.
  final OAuthClientProvider? authProvider;

  /// Customizes HTTP requests to the server.
  final Map<String, dynamic>? requestInit;

  /// Options to configure the reconnection behavior.
  final StreamableHttpReconnectionOptions? reconnectionOptions;

  /// Session ID for the connection. This is used to identify the session on the server.
  /// When not provided and connecting to a server that supports session IDs,
  /// the server will generate a new session ID.
  final String? sessionId;

  /// Maximum duration to wait for any single HTTP request (GET or POST)
  /// before aborting with a [TimeoutException]. Prevents indefinite hangs
  /// when the server is unreachable or unresponsive.
  /// Defaults to 30 seconds. Set to `null` to disable timeouts.
  final Duration? httpTimeout;

  const StreamableHttpClientTransportOptions({
    this.authProvider,
    this.requestInit,
    this.reconnectionOptions,
    this.sessionId,
    this.httpTimeout = const Duration(seconds: 30),
  });
}

/// Client transport for Streamable HTTP: this implements the MCP Streamable HTTP transport specification.
/// It will connect to a server using HTTP POST for sending messages and HTTP GET with Server-Sent Events
/// for receiving messages.
class StreamableHttpClientTransport implements Transport {
  StreamController<bool>? _abortController;
  final Uri _url;
  final Map<String, dynamic>? _requestInit;
  final OAuthClientProvider? _authProvider;
  String? _sessionId;
  final StreamableHttpReconnectionOptions _reconnectionOptions;
  final Duration? _httpTimeout;
  bool _isClosed = false;
  Timer? _reconnectTimer;

  /// Cumulative reconnect attempt counter that persists across
  /// connect-then-drop cycles. Without this, each cycle re-enters
  /// _scheduleReconnection with attemptCount=0, defeating maxRetries.
  int _reconnectAttemptCount = 0;

  /// Guards against concurrent SSE GET streams. Without this, overlapping
  /// calls to _startOrAuthSse (e.g. from reconnection racing with an
  /// initialized notification) open duplicate connections, causing every
  /// server-sent event to be delivered twice.
  bool _sseActive = false;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  final http.Client _httpClient;

  StreamableHttpClientTransport(Uri url, {StreamableHttpClientTransportOptions? opts})
    : _url = url,
      _requestInit = opts?.requestInit,
      _authProvider = opts?.authProvider,
      _sessionId = opts?.sessionId,
      _reconnectionOptions = opts?.reconnectionOptions ?? _defaultStreamableHttpReconnectionOptions,
      _httpTimeout = opts?.httpTimeout ?? const Duration(seconds: 30),
      _httpClient = http.Client();

  Future<void> _authThenStart() async {
    if (_authProvider == null) {
      throw UnauthorizedError("No auth provider");
    }

    AuthResult result;
    try {
      result = await auth(_authProvider, serverUrl: _url);
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(McpError(0, error.toString()));
      }
      rethrow;
    }

    if (result != "AUTHORIZED") {
      throw UnauthorizedError();
    }

    return await _startOrAuthSse(const StartSseOptions());
  }

  Future<Map<String, String>> _commonHeaders() async {
    final headers = <String, String>{};

    if (_authProvider != null) {
      final tokens = await _authProvider.tokens();
      if (tokens != null) {
        headers["Authorization"] = "Bearer ${tokens.accessToken}";
      }
    }

    if (_sessionId != null) {
      headers["mcp-session-id"] = _sessionId!;
    }

    if (_requestInit != null && _requestInit.containsKey('headers')) {
      final requestHeaders = _requestInit['headers'] as Map<String, dynamic>;
      for (final entry in requestHeaders.entries) {
        headers[entry.key] = entry.value.toString();
      }
    }

    return headers;
  }

  /// Sends an HTTP request with the configured [_httpTimeout].
  /// Throws [McpError] if the request exceeds the timeout, preventing
  /// indefinite hangs when the server is unreachable or slow.
  Future<http.StreamedResponse> _sendWithTimeout(http.BaseRequest request) async {
    final future = _httpClient.send(request);
    final timeout = _httpTimeout;
    if (timeout == null) return future;

    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      throw McpError(
        ErrorCode.internalError.value,
        'HTTP ${request.method} request to ${request.url} timed out after ${timeout.inSeconds}s',
      );
    }
  }

  Future<void> _startOrAuthSse(StartSseOptions options) async {
    if (_isClosed) return;

    // Prevent duplicate SSE GET streams; see _sseActive field comment.
    if (_sseActive) return;
    _sseActive = true;

    final resumptionToken = options.resumptionToken;
    try {
      // Try to open an initial SSE stream with GET to listen for server messages
      // This is optional according to the spec - server may not support it
      final headers = await _commonHeaders();
      headers['Accept'] = "text/event-stream";

      // Include Last-Event-ID header for resumable streams if provided
      if (resumptionToken != null) {
        headers['last-event-id'] = resumptionToken;
      }

      final request = http.Request('GET', _url);
      request.headers.addAll(headers);
      final response = await _sendWithTimeout(request);

      if (response.statusCode != 200) {
        _sseActive = false;

        if (response.statusCode == 401 && _authProvider != null) {
          // Need to authenticate
          return await _authThenStart();
        }

        // 405 indicates that the server does not offer an SSE stream at GET endpoint
        // This is an expected case that should not trigger an error
        if (response.statusCode == 405) {
          return;
        }

        throw StreamableHttpError(response.statusCode, "Failed to open SSE stream: ${response.reasonPhrase}");
      }

      _handleSseStream(response, options);
    } catch (error) {
      _sseActive = false;

      if (error is Error) {
        onerror?.call(error);
      } else {
        final err = McpError(0, error.toString());
        onerror?.call(err);
      }
      rethrow;
    }
  }

  /// Calculates the next reconnection delay using backoff algorithm
  ///
  /// @param attempt Current reconnection attempt count for the specific stream
  /// @returns Time to wait in milliseconds before next reconnection attempt
  int _getNextReconnectionDelay(int attempt) {
    // Access default values directly, ensuring they're never undefined
    final initialDelay = _reconnectionOptions.initialReconnectionDelay;
    final growFactor = _reconnectionOptions.reconnectionDelayGrowFactor;
    final maxDelay = _reconnectionOptions.maxReconnectionDelay;

    // Cap at maximum delay
    return (initialDelay * math.pow(growFactor, attempt)).round().clamp(0, maxDelay);
  }

  /// Schedule a reconnection attempt with exponential backoff
  ///
  /// @param options The SSE connection options
  /// @param attemptCount Current reconnection attempt count for this specific stream
  void _scheduleReconnection(StartSseOptions options, [int attemptCount = 0]) {
    // Prevent zombie timers from being created after close() has been called.
    if (_isClosed) return;

    final maxRetries = _reconnectionOptions.maxRetries;

    // Use the cumulative instance counter instead of the local parameter,
    // because the local resets to 0 each time a connect-then-drop cycle
    // re-enters handleReconnection → _scheduleReconnection.
    if (maxRetries >= 0 && _reconnectAttemptCount >= maxRetries) {
      onerror?.call(McpError(0, "Maximum reconnection attempts ($maxRetries) exceeded."));
      return;
    }

    final delay = _getNextReconnectionDelay(_reconnectAttemptCount);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectTimer = null;
      _reconnectAttemptCount++;
      _startOrAuthSse(options).catchError((error) {
        // Do NOT call onerror here — _startOrAuthSse already reports the
        // error via onerror before rethrowing.  Calling it again would
        // double-report to consumers.
        _scheduleReconnection(options, _reconnectAttemptCount);

        return null;
      });
    });
  }

  void _handleSseStream(http.StreamedResponse stream, StartSseOptions options) {
    final onResumptionToken = options.onResumptionToken;
    final replayMessageId = options.replayMessageId;

    String? lastEventId;
    String buffer = '';
    String? eventName;
    String? eventId;
    String? eventData;

    // Function to process a complete SSE event
    void processEvent() {
      if (eventData == null) return;

      // Update last event ID if provided
      if (eventId != null) {
        lastEventId = eventId;
        onResumptionToken?.call(eventId!);
      }

      if (eventName == null || eventName == 'message') {
        try {
          final message = JsonRpcMessage.fromJson(jsonDecode(eventData!));

          if (replayMessageId != null && message is JsonRpcResponse) {
            final newMessage = JsonRpcResponse(id: replayMessageId, result: message.result, meta: message.meta);
            onmessage?.call(newMessage);
          } else if (replayMessageId != null && message is JsonRpcError) {
            // JsonRpcError is a sibling type of JsonRpcResponse, not a subtype.
            // Error responses during replay must also have their IDs remapped
            // so the client can correlate them with the resumed request.
            final newMessage = JsonRpcError(id: replayMessageId, error: message.error);
            onmessage?.call(newMessage);
          } else {
            onmessage?.call(message);
          }
        } catch (error) {
          if (error is Error) {
            onerror?.call(error);
          } else {
            onerror?.call(McpError(0, error.toString()));
          }
        }
      }

      // Reset for next event
      eventName = null;
      eventId = null;
      eventData = null;
    }

    // Helper function to handle reconnection logic
    void handleReconnection(String? eventId, String errorMessage) {
      if (_isClosed || !options.shouldReconnect) return;

      if (_abortController != null && !_abortController!.isClosed) {
        // Reconnection must work even when the server never sent SSE event
        // IDs, because the connection can drop before any events arrive.
        // When eventId is null, _startOrAuthSse simply skips the
        // Last-Event-ID header — no guard needed here.
        try {
          _scheduleReconnection(
            StartSseOptions(
              resumptionToken: eventId,
              onResumptionToken: onResumptionToken,
              replayMessageId: replayMessageId,
              shouldReconnect: options.shouldReconnect,
            ),
          );
        } catch (error) {
          final errorMessage = error is Error ? error.toString() : error.toString();
          onerror?.call(McpError(0, "Failed to reconnect: $errorMessage"));
        }
      }
    }

    // Connection succeeded — reset the cumulative counter so future
    // disconnect cycles get a fresh set of retries.
    _reconnectAttemptCount = 0;

    final broadcastStream = stream.stream;

    StreamSubscription<bool>? abortSubscription;

    // Create a subscription to the stream
    final subscription = broadcastStream
        .transform(utf8.decoder)
        .asBroadcastStream()
        .listen(
          (data) {
            buffer += data;

            // Process the buffer line by line
            while (buffer.contains('\n')) {
              final index = buffer.indexOf('\n');
              var line = buffer.substring(0, index);
              if (line.endsWith('\r')) {
                line = line.substring(0, line.length - 1);
              }
              buffer = buffer.substring(index + 1);

              if (line.isEmpty) {
                // Empty line means end of event
                processEvent();
                continue;
              }

              if (line.startsWith(':')) {
                // Comment line, ignore
                continue;
              }

              final colonIndex = line.indexOf(':');
              if (colonIndex > 0) {
                final field = line.substring(0, colonIndex);
                // The value starts after colon + optional space
                final valueStart =
                    colonIndex + 1 + (line.length > colonIndex + 1 && line[colonIndex + 1] == ' ' ? 1 : 0);
                final value = line.substring(valueStart);

                switch (field) {
                  case 'event':
                    eventName = value;
                    break;
                  case 'id':
                    eventId = value;
                    break;
                  case 'data':
                    eventData = (eventData ?? '') + value;
                    break;
                }
              }
            }
          },
          onDone: () {
            abortSubscription?.cancel();
            _sseActive = false;
            // Process any final event
            processEvent();

            // Handle stream closure - likely a network disconnect
            handleReconnection(lastEventId, "Stream closed");
          },
          onError: (error) {
            abortSubscription?.cancel();
            _sseActive = false;
            final errorMessage = error is Error ? error.toString() : error.toString();
            onerror?.call(McpError(0, "SSE stream disconnected: $errorMessage"));

            // Attempt to reconnect if the stream disconnects unexpectedly
            handleReconnection(lastEventId, errorMessage);
          },
        );

    // Register the subscription cleanup when the abort controller is triggered
    abortSubscription = _abortController?.stream.listen((_) {
      subscription.cancel();
    });
  }

  @override
  Future<void> start() async {
    if (_abortController != null) {
      throw McpError(
        0,
        "StreamableHttpClientTransport already started! If using Client class, note that connect() calls start() automatically.",
      );
    }

    _abortController = StreamController<bool>.broadcast();
  }

  /// Call this method after the user has finished authorizing via their user agent and is redirected
  /// back to the MCP client application. This will exchange the authorization code for an access token,
  /// enabling the next connection attempt to successfully auth.
  Future<void> finishAuth(String authorizationCode) async {
    if (_authProvider == null) {
      throw UnauthorizedError("No auth provider");
    }

    final result = await auth(_authProvider, serverUrl: _url, authorizationCode: authorizationCode);
    if (result != "AUTHORIZED") {
      throw UnauthorizedError("Failed to authorize");
    }
  }

  @override
  Future<void> close() async {
    // Prevent double-close crashes: close() can be triggered by both explicit
    // user calls and internal error/disconnect handlers. Without this guard,
    // the second call attempts to add to an already-closed StreamController
    // (_abortController), throwing a StateError.
    if (_isClosed) return;
    _isClosed = true;
    _sseActive = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _abortController?.add(true);
    _abortController?.close();
    _abortController = null;
    _httpClient.close();

    onclose?.call();
  }

  @override
  Future<void> send(
    JsonRpcMessage message, {
    int? relatedRequestId,
    String? resumptionToken,
    void Function(String)? onResumptionToken,
  }) async {
    // Fail fast if the transport has been closed. Without this guard, send()
    // falls through to _httpClient methods on a closed client, producing
    // opaque errors. This matches the closed-guard pattern used in
    // SseServerTransport.send() and other transports.
    if (_isClosed) {
      throw StateError('Cannot send message: StreamableHttpClientTransport is closed.');
    }
    try {
      if (resumptionToken != null) {
        // If we have a last event ID, we need to reconnect the SSE stream
        final replayId = message is JsonRpcRequest ? message.id : null;
        _startOrAuthSse(
          StartSseOptions(
            resumptionToken: resumptionToken,
            replayMessageId: replayId,
            onResumptionToken: onResumptionToken,
          ),
        ).catchError((err) {
          if (err is Error) {
            onerror?.call(err);
          } else {
            onerror?.call(McpError(0, err.toString()));
          }
        });
        return;
      }

      // Check for authentication first - if we need auth, handle it before proceeding
      if (_authProvider != null) {
        final tokens = await _authProvider.tokens();
        if (tokens == null) {
          // No tokens available - trigger authentication flow
          await _authProvider.redirectToAuthorization();
          throw UnauthorizedError('Authentication required');
        }
      }

      final headers = await _commonHeaders();
      headers['content-type'] = 'application/json';
      headers['accept'] = 'application/json, text/event-stream';

      final request = http.Request('POST', _url);
      request.headers.addAll(headers);
      request.body = jsonEncode(message.toJson());

      final response = await _sendWithTimeout(request);

      // Handle session ID received during initialization
      final sessionId = response.headers['mcp-session-id'];
      if (sessionId != null) {
        _sessionId = sessionId;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 && _authProvider != null) {
          // Authentication failed with the server - try to refresh or redirect
          await _authProvider.redirectToAuthorization();
          throw UnauthorizedError('Authentication failed with the server');
        }

        final text = await response.stream.transform(utf8.decoder).join();
        throw McpError(0, "Error POSTing to endpoint (HTTP ${response.statusCode}): $text");
      }

      // If the response is 202 Accepted, there's no body to process
      if (response.statusCode == 202) {
        // Ensure we drain the stream to release the connection
        await response.stream.drain();

        await Future.delayed(Duration.zero);

        // if the accepted notification is initialized, we start the SSE stream
        // if it's supported by the server
        if (_isInitializedNotification(message)) {
          // Start without a lastEventId since this is a fresh connection
          _startOrAuthSse(const StartSseOptions()).catchError((err) {
            if (err is Error) {
              onerror?.call(err);
            } else {
              onerror?.call(McpError(0, err.toString()));
            }
          });
        }
        return;
      }

      // Start SSE if this was the initialized notification, even if 200 OK
      if (_isInitializedNotification(message)) {
        _startOrAuthSse(const StartSseOptions()).catchError((err) {
          if (err is Error) {
            onerror?.call(err);
          } else {
            onerror?.call(McpError(0, err.toString()));
          }
        });
      }

      // Check if the message is a request that expects a response
      final hasRequests = message is JsonRpcRequest && message.id != null;

      // Check the response type
      final contentType = response.headers['content-type'];

      if (hasRequests) {
        if (contentType?.contains('text/event-stream') ?? false) {
          // Handle SSE stream responses for requests
          _handleSseStream(
            response,
            StartSseOptions(
              onResumptionToken: onResumptionToken,
              shouldReconnect: false, // Do not reconnect for POST responses
            ),
          );
        } else if (contentType?.contains('application/json') ?? false) {
          // For non-streaming servers, we might get direct JSON responses
          final jsonStr = await response.stream.transform(utf8.decoder).join();
          final data = jsonDecode(jsonStr);

          if (data is List) {
            for (final item in data) {
              final msg = JsonRpcMessage.fromJson(item);
              onmessage?.call(msg);
            }
          } else {
            final msg = JsonRpcMessage.fromJson(data);
            onmessage?.call(msg);
          }
        } else {
          throw StreamableHttpError(-1, "Unexpected content type: $contentType");
        }
      }
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(McpError(0, error.toString()));
      }
      rethrow;
    }
  }

  @override
  String? get sessionId => _sessionId;

  /// Terminates the current session by sending a DELETE request to the server.
  ///
  /// Clients that no longer need a particular session
  /// (e.g., because the user is leaving the client application) SHOULD send an
  /// HTTP DELETE to the MCP endpoint with the Mcp-Session-Id header to explicitly
  /// terminate the session.
  ///
  /// The server MAY respond with HTTP 405 Method Not Allowed, indicating that
  /// the server does not allow clients to terminate sessions.
  Future<void> terminateSession() async {
    if (_sessionId == null) {
      return; // No session to terminate
    }

    try {
      final headers = await _commonHeaders();

      final response = await _httpClient.delete(_url, headers: headers);

      // We specifically handle 405 as a valid response according to the spec,
      // meaning the server does not support explicit session termination
      if (response.statusCode < 200 || response.statusCode >= 300 && response.statusCode != 405) {
        throw StreamableHttpError(response.statusCode, "Failed to terminate session: ${response.reasonPhrase}");
      }

      _sessionId = null;
    } catch (error) {
      if (error is Error) {
        onerror?.call(error);
      } else {
        onerror?.call(McpError(0, error.toString()));
      }
      rethrow;
    }
  }

  // Helper method to check if a message is an initialized notification
  bool _isInitializedNotification(JsonRpcMessage message) {
    if (message is JsonRpcNotification) {
      return message.method == "notifications/initialized";
    }
    return false;
  }
}

/// Represents an unauthorized error
class UnauthorizedError extends Error {
  final String? message;

  UnauthorizedError([this.message]);

  @override
  String toString() => 'Unauthorized${message != null ? ': $message' : ''}';
}

/// Represents an OAuth client provider for authentication
abstract class OAuthClientProvider {
  /// Get current tokens if available
  Future<OAuthTokens?> tokens();

  /// Redirect to authorization endpoint
  Future<void> redirectToAuthorization();
}

/// Represents OAuth tokens
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;

  OAuthTokens({required this.accessToken, this.refreshToken});
}

/// Result of an authentication attempt
typedef AuthResult = String; // "AUTHORIZED" or other values

/// Performs authentication with the provided OAuth client
Future<AuthResult> auth(OAuthClientProvider provider, {required Uri serverUrl, String? authorizationCode}) async {
  // Simple implementation that would need to be expanded in a real implementation
  final tokens = await provider.tokens();
  if (tokens != null) {
    return "AUTHORIZED";
  }

  // If we have an authorization code, we'd process it here
  if (authorizationCode != null) {
    // Implementation would include exchanging the code for tokens
    return "AUTHORIZED";
  }

  // Need to redirect for authorization
  await provider.redirectToAuthorization();
  return "NEEDS_AUTH";
}

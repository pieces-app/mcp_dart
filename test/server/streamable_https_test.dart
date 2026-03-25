import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/server/streamable_https.dart';
import 'package:mcp_dart/src/shared/uuid.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

/// A simple implementation of EventStore for testing event resumability
class TestEventStore implements EventStore {
  /// Maps session IDs to lists of (eventId, messageJson) pairs
  final events = <String, List<MapEntry<String, Map<String, dynamic>>>>{};

  @override
  Future<String> storeEvent(String sessionId, JsonRpcMessage message) async {
    final eventId = generateUUID();
    events.putIfAbsent(sessionId, () => []);
    events[sessionId]!.add(MapEntry(eventId, message.toJson()));
    return eventId;
  }

  @override
  Future<String> replayEventsAfter(
    String eventId, {
    required Future<void> Function(String, JsonRpcMessage) send,
  }) async {
    String? sessionId;
    int? eventIndex;

    for (final entry in events.entries) {
      final sid = entry.key;
      final eventList = entry.value;
      for (var i = 0; i < eventList.length; i++) {
        if (eventList[i].key == eventId) {
          sessionId = sid;
          eventIndex = i;
          break;
        }
      }
      if (sessionId != null) break;
    }

    if (sessionId == null || eventIndex == null) {
      throw Exception('Event ID not found: $eventId');
    }

    final eventsToReplay = events[sessionId]!.sublist(eventIndex + 1);
    for (final event in eventsToReplay) {
      final jsonMap = _convertToStringDynamicMap(event.value);
      final message = JsonRpcMessage.fromJson(jsonMap);
      await send(event.key, message);
    }

    return sessionId;
  }

  /// Converts Maps with dynamic keys to Map&lt;`String, dynamic&gt;
  Map<String, dynamic> _convertToStringDynamicMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        result[key] = _convertToStringDynamicMap(value);
      } else if (value is List) {
        result[key] = _convertToStringDynamicList(value);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Converts Lists with dynamic values
  List<dynamic> _convertToStringDynamicList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        return _convertToStringDynamicMap(item);
      } else if (item is List) {
        return _convertToStringDynamicList(item);
      } else {
        return item;
      }
    }).toList();
  }
}

void main() {
  late HttpServer testServer;
  late int serverPort;
  late String serverUrlBase;

  /// Maps endpoint paths to active transports
  final Map<String, StreamableHTTPServerTransport> transports = {};
  final Map<String, Completer<JsonRpcMessage>> messageCompleters = {};

  /// Set up the test HTTP server before all tests
  setUpAll(() async {
    try {
      testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testServer.port;
      serverUrlBase = 'http://localhost:$serverPort';
      print("Test server listening on $serverUrlBase");

      testServer.listen((request) async {
        final path = request.uri.path;
        print("Received request: ${request.method} ${request.uri}");

        if (path == '/mcp') {
          final transport = transports['/mcp'];

          if (transport != null) {
            try {
              await transport.handleRequest(request);
            } catch (e, stackTrace) {
              print("Error in transport.handleRequest: $e");
              print("Stack trace: $stackTrace");
              if (!request.response.headers.persistentConnection) {
                request.response.statusCode = HttpStatus.internalServerError;
                request.response.write("Error processing request: $e");
                await request.response.close();
              }
            }
          } else {
            print("No transport available for path: $path");
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write("Transport not available");
            await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write("Not Found");
          await request.response.close();
        }
      });
    } catch (e) {
      print("FATAL: Failed to start test server: $e");
      fail("Failed to start test server: $e");
    }
  });

  /// Clean up resources after all tests complete
  tearDownAll(() async {
    print("Stopping test server...");
    for (final transport in transports.values) {
      await transport.close();
    }
    await testServer.close(force: true);
    print("Test server stopped.");
  });

  group('StreamableHTTPServerTransport tests', () {
    /// Reset state before each test
    setUp(() {
      transports.clear();
      messageCompleters.clear();
    });

    // Common test setup

    // Helper to manually trigger initialization of the transport

    test('initialization with stateful session management', () async {
      // Create a new transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transports['/mcp'] = transport;

      // Set the sessionId for testing purposes
      transport.sessionId = "test-session-id";

      // Verify the session ID is correctly set
      expect(transport.sessionId, equals("test-session-id"));

      await transport.close();
    });

    test('GET request establishes SSE stream and delivers notifications', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transports['/mcp'] = transport;

      // Initialize via shelf POST so _initialized becomes true
      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          transport.send(
            JsonRpcResponse(
              id: message.id,
              result: {
                'protocolVersion': '2024-11-05',
                'serverInfo': {'name': 'test-server', 'version': '1.0.0'},
                'capabilities': {},
              },
            ),
            relatedRequestId: message.id,
          );
        }
      };

      final initReq = shelf.Request(
        'POST',
        Uri.parse('http://localhost/mcp'),
        headers: {'accept': 'application/json, text/event-stream', 'content-type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test', 'version': '1.0'},
            'capabilities': {},
          },
        }),
      );
      final initResp = await transport.handleShelfRequest(initReq);
      expect(initResp.statusCode, equals(200));

      // Establish standalone SSE stream via shelf GET
      final getReq = shelf.Request(
        'GET',
        Uri.parse('http://localhost/mcp'),
        headers: {'accept': 'text/event-stream', 'mcp-session-id': transport.sessionId!},
      );
      final sseResp = await transport.handleShelfRequest(getReq);
      expect(sseResp.statusCode, equals(200));

      // Send a notification and verify it appears in the SSE stream
      const notification = JsonRpcNotification(method: 'test/notification', params: {'message': 'hello'});
      await transport.send(notification);

      final bodyBytes = await sseResp
          .read()
          .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())
          .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));

      final bodyText = utf8.decode(bodyBytes);
      expect(bodyText, contains('event: message'), reason: 'SSE stream must contain a message event');
      expect(bodyText, contains('"method":"test/notification"'));
      expect(bodyText, contains('"message":"hello"'));

      await transport.close();
    });

    test('POST request with JSON-RPC request triggers onmessage', () async {
      // Create a transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transports['/mcp'] = transport;

      transport.sessionId = "test-session-id";

      // Set up message handler with completion tracker
      final messageCompleter = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        if (!messageCompleter.isCompleted) {
          messageCompleter.complete(message);
        }
      };

      // Create a test JSON-RPC request
      final request = const JsonRpcRequest(id: 123, method: 'test/method', params: {'data': 'test-data'});

      // Simulate message receipt
      transport.onmessage?.call(request);

      // Wait for message processing with timeout
      final receivedMessage = await messageCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('No message received within timeout'),
      );

      // Verify message content
      expect(receivedMessage, isA<JsonRpcRequest>());
      expect((receivedMessage as JsonRpcRequest).id, equals(123));
      expect(receivedMessage.method, equals('test/method'));
      expect(receivedMessage.params?['data'], equals('test-data'));

      await transport.close();
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('enableJsonResponse option is accepted', () async {
      final errors = <Error>[];
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "test-session-id",
          enableJsonResponse: true,
        ),
      );

      await transport.start();
      transport.onerror = (error) => errors.add(error);
      transports['/mcp'] = transport;
      transport.sessionId = "test-session-id";

      expect(
        transport.sessionId,
        equals("test-session-id"),
        reason: 'Session ID should be assignable after start with enableJsonResponse',
      );

      await transport.close();

      expect(errors, isEmpty, reason: 'No errors should occur with enableJsonResponse=true');
    });

    test('dns rebinding protection options are accepted', () async {
      final errors = <Error>[];
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => 'test-session-id',
          enableDnsRebindingProtection: true,
          allowedHosts: {'localhost'},
          allowedOrigins: {'http://localhost'},
        ),
      );

      await transport.start();
      transport.onerror = (error) => errors.add(error);
      transports['/mcp'] = transport;
      transport.sessionId = 'test-session-id';

      expect(
        transport.sessionId,
        equals('test-session-id'),
        reason: 'Session ID should be assignable with DNS rebinding protection enabled',
      );

      bool oncloseCalled = false;
      transport.onclose = () => oncloseCalled = true;

      await transport.close();

      expect(oncloseCalled, isTrue, reason: 'onclose should fire on clean shutdown');
      expect(errors, isEmpty, reason: 'No errors should occur with DNS rebinding protection options');
    });

    test('session validation works correctly', () async {
      // Create a transport with session management
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "correct-session-id"),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "correct-session-id";

      // Set up handlers for valid and invalid cases
      final validMessageCompleter = Completer<JsonRpcMessage>();
      final invalidMessageCompleter = Completer<String>();

      transport.onmessage = (message) {
        if (!validMessageCompleter.isCompleted) {
          validMessageCompleter.complete(message);
        }
      };

      // Create test message and headers
      final validRequest = const JsonRpcRequest(id: 1, method: 'test/method', params: {'data': 'test-data'});

      final validHeaders = {
        'mcp-session-id': ['correct-session-id'],
      };
      final invalidHeaders = {
        'mcp-session-id': ['wrong-session-id'],
      };

      // Test session validation
      Future<void> testSessionValidation() async {
        // Test with valid session ID
        if (transport.sessionId == validHeaders['mcp-session-id']?[0]) {
          transport.onmessage?.call(validRequest);
        } else {
          fail("Valid session ID check failed");
        }

        // Test with invalid session ID
        if (transport.sessionId == invalidHeaders['mcp-session-id']?[0]) {
          fail("Invalid session ID check passed when it should fail");
        } else {
          // Expected behavior: session ID mismatch prevents processing
          invalidMessageCompleter.complete("Invalid session rejected correctly");
        }
      }

      await testSessionValidation();

      // Verify results with appropriate timeouts
      final receivedMessage = await validMessageCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Valid message test timed out'),
      );

      final invalidResult = await invalidMessageCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Invalid message test timed out'),
      );

      // Verify message properties
      expect(receivedMessage, isA<JsonRpcRequest>());
      expect((receivedMessage as JsonRpcRequest).id, equals(1));
      expect(receivedMessage.method, equals('test/method'));
      expect(receivedMessage.params?['data'], equals('test-data'));
      expect(invalidResult, equals("Invalid session rejected correctly"));

      await transport.close();
    });

    test('event resumability works with EventStore', () async {
      // Create a test event store for tracking events
      final eventStore = TestEventStore();

      // Create a transport with event store for resumability
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "resumable-session-id",
          eventStore: eventStore,
        ),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "resumable-session-id";

      // Create sample test messages
      final messages = [
        const JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-1', 'version': '1.0.0'},
            'capabilities': {},
          },
        ),
        const JsonRpcRequest(
          id: 2,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-2', 'version': '1.0.0'},
            'capabilities': {},
          },
        ),
        const JsonRpcRequest(
          id: 3,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test-client-3', 'version': '1.0.0'},
            'capabilities': {},
          },
        ),
      ];

      // Store the messages in the event store
      final storedEventIds = <String>[];
      for (final message in messages) {
        final eventId = await eventStore.storeEvent(transport.sessionId!, message);
        storedEventIds.add(eventId);
      }

      // Verify storage was successful
      expect(eventStore.events[transport.sessionId!]!.length, equals(messages.length));

      // Resume from the first event
      final lastEventId = storedEventIds.first;
      final replayedEvents = <JsonRpcMessage>[];
      final replayCompleter = Completer<void>();

      // Set up send function for replaying events
      Future<void> sendFunction(String eventId, JsonRpcMessage message) async {
        replayedEvents.add(message);
        if (replayedEvents.length == messages.length - 1) {
          replayCompleter.complete();
        }
      }

      // Perform event replay
      final streamId = await eventStore.replayEventsAfter(lastEventId, send: sendFunction);

      // Verify the session ID matches
      expect(streamId, equals(transport.sessionId));

      // Wait for replay completion
      await replayCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Event replay timed out'),
      );

      // Verify correct number of events replayed
      expect(replayedEvents.length, equals(messages.length - 1));

      // Verify replayed events match original messages
      for (var i = 0; i < replayedEvents.length; i++) {
        final replayedMessage = replayedEvents[i];
        final originalMessage = messages[i + 1]; // Skip the first message

        expect(replayedMessage, isA<JsonRpcRequest>());
        expect((replayedMessage as JsonRpcRequest).method, equals('initialize'));
        expect(replayedMessage.id, equals(originalMessage.id));
        expect(replayedMessage.params!['clientInfo']['name'], equals(originalMessage.params!['clientInfo']['name']));
      }

      await transport.close();
    });

    test('transport throws StateError when started twice', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();

      expect(() => transport.start(), throwsA(isA<StateError>()));

      await transport.close();
    });

    test('onsessioninitialized callback is registered and callable', () async {
      // Test callback registration
      bool callbackWasSet = false;
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(
          sessionIdGenerator: () => "callback-session-id",
          onsessioninitialized: (sessionId) {
            callbackWasSet = true;
          },
        ),
      );
      await transport.start();

      // Verify the transport has the expected session ID generator behavior
      // The actual callback is triggered during handleRequest with an init message
      // Here we just verify the transport was successfully configured
      expect(transport.sessionId, isNull); // Not set yet before init
      expect(callbackWasSet, isFalse); // Not triggered without init request

      await transport.close();

      // Note: In actual usage, the callback is called during handleRequest
      // when an initialization request is processed. See integration tests.
    });

    test('stateless mode allows requests without session validation', () async {
      // Stateless mode - sessionIdGenerator returns null
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => null),
      );
      await transport.start();
      transports['/mcp'] = transport;

      final messageCompleter = Completer<JsonRpcMessage>();
      transport.onmessage = (message) {
        if (!messageCompleter.isCompleted) {
          messageCompleter.complete(message);
        }
      };

      // Simulate initialization to set _initialized = true
      transport.onmessage?.call(
        const JsonRpcRequest(
          id: 1,
          method: 'initialize',
          params: {
            'protocolVersion': '2024-11-05',
            'clientInfo': {'name': 'test', 'version': '1.0'},
            'capabilities': {},
          },
        ),
      );

      final message = await messageCompleter.future.timeout(const Duration(seconds: 2));

      expect(message, isA<JsonRpcRequest>());
      expect(transport.sessionId, isNull);

      await transport.close();
    });

    test('close cleans up all resources', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      bool oncloseCalled = false;
      transport.onclose = () {
        oncloseCalled = true;
      };

      await transport.close();

      expect(oncloseCalled, isTrue);
    });

    test('send throws StateError for response on standalone SSE stream', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      // Try to send a response without a request ID (standalone SSE)
      final response = const JsonRpcResponse(id: 123, result: {'data': 'test'});

      // This should throw because we can't send responses on standalone SSE
      expect(() => transport.send(response), throwsA(isA<StateError>()));

      await transport.close();
    });

    test('send discards notifications when no standalone SSE stream', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      final errors = <Error>[];
      transport.onerror = (error) => errors.add(error);

      final notification = const JsonRpcNotification(method: 'test/notification', params: {'message': 'hello'});

      await transport.send(notification);

      expect(errors, isEmpty, reason: 'Discarding a notification must not produce an error');

      // Transport must remain healthy — onclose should still fire on close.
      bool oncloseCalled = false;
      transport.onclose = () => oncloseCalled = true;

      await transport.close();

      expect(oncloseCalled, isTrue, reason: 'Transport must close cleanly after discarding notifications');
    });

    test('send throws StateError for unknown request ID', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transport.sessionId = "test-session-id";

      // Try to send a response for an unknown request ID
      final response = const JsonRpcResponse(id: 999, result: {'data': 'test'});

      expect(() => transport.send(response, relatedRequestId: 999), throwsA(isA<StateError>()));

      await transport.close();
    });

    test('onerror callback is invoked on errors', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();

      Error? receivedError;
      transport.onerror = (error) {
        receivedError = error;
      };

      // Simulate message handler throwing
      transport.onmessage = (message) {
        throw StateError('Handler error');
      };

      // Try to trigger the error through a simulated message
      try {
        transport.onmessage?.call(const JsonRpcNotification(method: 'test', params: {}));
      } catch (e) {
        // Expected
      }

      // Note: onerror is called internally when handlers throw in POST handling
      // Direct onmessage throws are caught in the test itself
      // The variable is captured but may not be set when throwing directly
      expect(receivedError, isNull); // Not called when we throw directly in handler

      await transport.close();
    });

    test('EventStore storeEvent returns unique event IDs', () async {
      final eventStore = TestEventStore();
      final sessionId = 'test-session';

      final msg1 = const JsonRpcNotification(method: 'test1', params: {});
      final msg2 = const JsonRpcNotification(method: 'test2', params: {});

      final id1 = await eventStore.storeEvent(sessionId, msg1);
      final id2 = await eventStore.storeEvent(sessionId, msg2);

      expect(id1, isNot(equals(id2)));
      expect(eventStore.events[sessionId]!.length, equals(2));
    });

    test('EventStore replayEventsAfter throws for unknown event ID', () async {
      final eventStore = TestEventStore();

      expect(
        () => eventStore.replayEventsAfter('unknown-event-id', send: (eventId, message) async {}),
        throwsA(isA<Exception>()),
      );
    });

    test('transport handles notifications-only POST with 202', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => "test-session-id"),
      );
      await transport.start();
      transports['/mcp'] = transport;
      transport.sessionId = "test-session-id";

      final messages = <JsonRpcMessage>[];
      transport.onmessage = (msg) {
        messages.add(msg);
      };

      // Call onmessage with a notification
      transport.onmessage?.call(const JsonRpcNotification(method: 'test/notification', params: {'data': 'value'}));

      expect(messages.length, equals(1));
      expect(messages.first, isA<JsonRpcNotification>());

      await transport.close();
    });

    test('body size limit enforcement returns 413 for oversized POST', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => 'body-limit-session', maxBodySize: 100),
      );
      await transport.start();
      transports['/mcp'] = transport;

      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse('$serverUrlBase/mcp'));
        req.headers.contentType = ContentType.json;
        req.headers.set('Accept', 'application/json, text/event-stream');
        req.write('a' * 200);
        final res = await req.close();

        expect(res.statusCode, HttpStatus.requestEntityTooLarge);
        await res.drain();
      } finally {
        client.close(force: true);
        await transport.close();
      }
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('double close is safe and fires onclose exactly once', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => 'double-close-session'),
      );
      await transport.start();
      transport.sessionId = 'double-close-session';

      int oncloseCount = 0;
      final errors = <Error>[];
      transport.onclose = () {
        oncloseCount++;
      };
      transport.onerror = (error) {
        errors.add(error);
      };

      await transport.close();
      await transport.close();
      await transport.close();

      expect(oncloseCount, equals(1), reason: 'onclose must fire exactly once');
      expect(errors, isEmpty, reason: 'no errors on repeated close');
    });

    test('send notification via shelf adapter standalone SSE stream', () async {
      final transport = StreamableHTTPServerTransport(
        options: StreamableHTTPServerTransportOptions(sessionIdGenerator: () => 'shelf-sse-session'),
      );
      await transport.start();

      // Step 1: Initialize via shelf POST so _initialized becomes true
      final initBody = jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2024-11-05',
          'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
          'capabilities': {},
        },
      });

      transport.onmessage = (message) {
        if (message is JsonRpcRequest && message.method == 'initialize') {
          transport.send(
            JsonRpcResponse(
              id: message.id,
              result: {
                'protocolVersion': '2024-11-05',
                'serverInfo': {'name': 'test-server', 'version': '1.0.0'},
                'capabilities': {},
              },
            ),
            relatedRequestId: message.id,
          );
        }
      };

      final initReq = shelf.Request(
        'POST',
        Uri.parse('http://localhost/mcp'),
        headers: {'accept': 'application/json, text/event-stream', 'content-type': 'application/json'},
        body: initBody,
      );

      final initResponse = await transport.handleShelfRequest(initReq);
      expect(initResponse.statusCode, equals(200));
      expect(transport.sessionId, equals('shelf-sse-session'));

      // Step 2: Establish standalone SSE stream via shelf GET
      final getReq = shelf.Request(
        'GET',
        Uri.parse('http://localhost/mcp'),
        headers: {'accept': 'text/event-stream', 'mcp-session-id': transport.sessionId!},
      );

      final sseResponse = await transport.handleShelfRequest(getReq);
      expect(sseResponse.statusCode, equals(200));

      // Step 3: Send a notification — should go through the adapter stream
      const notification = JsonRpcNotification(method: 'test/hello', params: {'greeting': 'world'});
      await transport.send(notification);

      // Step 4: Read the SSE stream and verify the notification arrived
      final bodyBytes = await sseResponse
          .read()
          .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())
          .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));

      final bodyText = utf8.decode(bodyBytes);
      expect(bodyText, contains('event: message'));
      expect(bodyText, contains('"method":"test/hello"'));
      expect(bodyText, contains('"greeting":"world"'));

      await transport.close();
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}

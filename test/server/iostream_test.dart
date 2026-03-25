import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_dart/src/shared/iostream.dart';
import 'package:mcp_dart/src/shared/stdio.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('ReadBuffer', () {
    test('overflow clears buffer and continues', () {
      final buffer = ReadBuffer(maxBufferSize: 50);

      // 60 bytes, no newline — exceeds the 50-byte limit.
      final big = Uint8List(60)..fillRange(0, 60, 0x41); // 'A' * 60
      final ok = buffer.append(big);

      expect(ok, isFalse, reason: 'append should return false on overflow');
      expect(buffer.readMessage(), isNull, reason: 'buffer should be empty after overflow');

      // A subsequent small valid message should parse normally.
      final msg = '{"jsonrpc":"2.0","method":"ping","id":1}\n';
      expect(buffer.append(Uint8List.fromList(utf8.encode(msg))), isTrue);

      final parsed = buffer.readMessage();
      expect(parsed, isNotNull);
      expect(parsed, isA<JsonRpcPingRequest>());
      expect((parsed as JsonRpcPingRequest).id, 1);
    });

    test('partial message buffered across chunks', () {
      final buffer = ReadBuffer();
      final full = '{"jsonrpc":"2.0","method":"ping","id":99}\n';
      final bytes = utf8.encode(full);
      final mid = bytes.length ~/ 2;

      buffer.append(Uint8List.fromList(bytes.sublist(0, mid)));
      expect(buffer.readMessage(), isNull, reason: 'no newline yet — nothing to return');

      buffer.append(Uint8List.fromList(bytes.sublist(mid)));
      final parsed = buffer.readMessage();
      expect(parsed, isA<JsonRpcPingRequest>());
      expect((parsed as JsonRpcPingRequest).id, 99);
    });

    test('multiple messages in single chunk', () {
      final buffer = ReadBuffer();
      final chunk =
          '{"jsonrpc":"2.0","method":"ping","id":1}\n'
          '{"jsonrpc":"2.0","method":"ping","id":2}\n';
      buffer.append(Uint8List.fromList(utf8.encode(chunk)));

      final first = buffer.readMessage();
      expect(first, isA<JsonRpcPingRequest>());
      expect((first as JsonRpcPingRequest).id, 1);

      final second = buffer.readMessage();
      expect(second, isA<JsonRpcPingRequest>());
      expect((second as JsonRpcPingRequest).id, 2);

      expect(buffer.readMessage(), isNull);
    });

    test('malformed UTF-8 line throws MalformedLineException', () {
      final buffer = ReadBuffer();
      // 0xFF 0xFE are invalid UTF-8 lead bytes followed by a newline.
      buffer.append(Uint8List.fromList([0xFF, 0xFE, 0x0A]));

      expect(() => buffer.readMessage(), throwsA(isA<MalformedLineException>()));

      // Buffer should have advanced past the bad line; a valid message
      // appended afterwards still parses.
      final msg = '{"jsonrpc":"2.0","method":"ping","id":5}\n';
      buffer.append(Uint8List.fromList(utf8.encode(msg)));
      final parsed = buffer.readMessage();
      expect(parsed, isA<JsonRpcPingRequest>());
      expect((parsed as JsonRpcPingRequest).id, 5);
    });

    test('invalid JSON line throws FormatException', () {
      final buffer = ReadBuffer();
      buffer.append(Uint8List.fromList(utf8.encode('not valid json\n')));
      expect(() => buffer.readMessage(), throwsA(isA<FormatException>()));
    });
  });

  group('IOStream Transport Tests', () {
    // Stream controllers for direct communication
    late StreamController<List<int>> clientToServerController;
    late StreamController<List<int>> serverToClientController;

    // Client and server transports
    late IOStreamTransport clientTransport;
    late IOStreamTransport serverTransport;

    // Test state management
    late Completer<void> serverCloseCompleter;
    late Completer<void> clientCloseCompleter;
    late Completer<Error> serverErrorCompleter;
    late Completer<Error> clientErrorCompleter;
    final List<JsonRpcMessage> serverReceivedMessages = [];
    final List<JsonRpcMessage> clientReceivedMessages = [];

    setUp(() {
      // Create fresh stream controllers for each test
      clientToServerController = StreamController<List<int>>.broadcast();
      serverToClientController = StreamController<List<int>>.broadcast();

      // Set up transports
      clientTransport = IOStreamTransport(stream: serverToClientController.stream, sink: clientToServerController.sink);

      serverTransport = IOStreamTransport(stream: clientToServerController.stream, sink: serverToClientController.sink);

      // Reset state tracking
      serverCloseCompleter = Completer<void>();
      clientCloseCompleter = Completer<void>();
      serverErrorCompleter = Completer<Error>();
      clientErrorCompleter = Completer<Error>();
      serverReceivedMessages.clear();
      clientReceivedMessages.clear();

      // Configure callbacks
      serverTransport.onclose = () {
        if (!serverCloseCompleter.isCompleted) {
          serverCloseCompleter.complete();
        }
      };

      serverTransport.onerror = (error) {
        if (!serverErrorCompleter.isCompleted) {
          serverErrorCompleter.complete(error);
        }
      };

      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
      };

      clientTransport.onclose = () {
        if (!clientCloseCompleter.isCompleted) {
          clientCloseCompleter.complete();
        }
      };

      clientTransport.onerror = (error) {
        if (!clientErrorCompleter.isCompleted) {
          clientErrorCompleter.complete(error);
        }
      };

      clientTransport.onmessage = (message) {
        clientReceivedMessages.add(message);
      };
    });

    tearDown(() async {
      // Clean up resources
      await clientTransport.close();
      await serverTransport.close();
      await clientToServerController.close();
      await serverToClientController.close();
    });

    // Helper to send a properly formatted message directly to a stream controller
    void sendRawJsonMessage(StreamController<List<int>> controller, JsonRpcMessage message) {
      final jsonString = "${jsonEncode(message.toJson())}\n";
      controller.add(utf8.encode(jsonString));
    }

    test('Transports start without errors', () async {
      await serverTransport.start();
      await clientTransport.start();

      expect(serverCloseCompleter.isCompleted, isFalse);
      expect(clientCloseCompleter.isCompleted, isFalse);
      expect(serverErrorCompleter.isCompleted, isFalse);
      expect(clientErrorCompleter.isCompleted, isFalse);
    });

    test('Basic message passing - client to server', () async {
      // Start both sides
      await serverTransport.start();
      await clientTransport.start();

      // Setup a completer for server message receipt
      final messageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!messageReceived.isCompleted) {
          messageReceived.complete(message);
        }
      };

      // Send a message via the raw controller (bypassing transport.send())
      final pingMessage = const JsonRpcPingRequest(id: 1);
      sendRawJsonMessage(clientToServerController, pingMessage);

      // Wait for the message to be received
      final receivedMessage = await messageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Message not received'),
      );

      // Verify correct message received
      expect(receivedMessage, isA<JsonRpcPingRequest>());
      expect((receivedMessage as JsonRpcPingRequest).id, 1);
    });

    test('Basic message passing - server to client', () async {
      // Start both sides
      await serverTransport.start();
      await clientTransport.start();

      // Setup a completer for client message receipt
      final messageReceived = Completer<JsonRpcMessage>();
      clientTransport.onmessage = (message) {
        clientReceivedMessages.add(message);
        if (!messageReceived.isCompleted) {
          messageReceived.complete(message);
        }
      };

      // Send a message from server to client
      final pingMessage = const JsonRpcPingRequest(id: 2);
      sendRawJsonMessage(serverToClientController, pingMessage);

      // Wait for the message to be received
      final receivedMessage = await messageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Message not received'),
      );

      // Verify correct message received
      expect(receivedMessage, isA<JsonRpcPingRequest>());
      expect((receivedMessage as JsonRpcPingRequest).id, 2);
    });

    test('Bidirectional communication', () async {
      // Start both sides
      await serverTransport.start();
      await clientTransport.start();

      // Setup completers for message receipt
      final serverReceived = Completer<JsonRpcMessage>();
      final clientReceived = Completer<JsonRpcMessage>();

      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!serverReceived.isCompleted) {
          serverReceived.complete(message);
        }
      };

      clientTransport.onmessage = (message) {
        clientReceivedMessages.add(message);
        if (!clientReceived.isCompleted) {
          clientReceived.complete(message);
        }
      };

      // Send client -> server
      sendRawJsonMessage(clientToServerController, const JsonRpcPingRequest(id: 3));

      // Send server -> client
      sendRawJsonMessage(serverToClientController, const JsonRpcPingRequest(id: 4));

      // Wait for both messages to be received
      final serverMsg = await serverReceived.future.timeout(const Duration(seconds: 2));
      final clientMsg = await clientReceived.future.timeout(const Duration(seconds: 2));

      // Verify both messages
      expect(serverMsg, isA<JsonRpcPingRequest>());
      expect((serverMsg as JsonRpcPingRequest).id, 3);

      expect(clientMsg, isA<JsonRpcPingRequest>());
      expect((clientMsg as JsonRpcPingRequest).id, 4);
    });

    test('Multiple messages can be sent and received', () async {
      await serverTransport.start();
      await clientTransport.start();

      const expectedMessageCount = 5;
      final receivedMessages = <JsonRpcMessage>[];
      final allMessagesReceived = Completer<void>();

      serverTransport.onmessage = (message) {
        receivedMessages.add(message);
        if (receivedMessages.length >= expectedMessageCount) {
          if (!allMessagesReceived.isCompleted) {
            allMessagesReceived.complete();
          }
        }
      };

      // Send multiple messages
      for (int i = 0; i < expectedMessageCount; i++) {
        sendRawJsonMessage(clientToServerController, JsonRpcPingRequest(id: i));
        // Add a small delay to avoid overwhelming the stream
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Wait for all messages to be received
      await allMessagesReceived.future.timeout(const Duration(seconds: 5));

      // Verify messages received
      expect(receivedMessages.length, expectedMessageCount);

      // Check all expected IDs are present
      final receivedIds = receivedMessages.map((msg) => (msg as JsonRpcPingRequest).id).toSet();

      for (int i = 0; i < expectedMessageCount; i++) {
        expect(receivedIds, contains(i));
      }
    });

    test('Transport closes when input stream closes', () async {
      await serverTransport.start();

      // Close the client-to-server controller
      await clientToServerController.close();

      // Wait for server transport to close
      await serverCloseCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Transport not closed'),
      );
    });

    test('Transport handles invalid JSON gracefully', () async {
      await serverTransport.start();

      // Send invalid JSON data
      clientToServerController.add(utf8.encode('not valid json\n'));

      // Wait for error to be reported
      final error = await serverErrorCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Error not reported'),
      );

      // Verify error was reported but transport still works
      expect(error.toString(), contains('Invalid JSON'));

      // Set up a completer for subsequent valid message
      final validMessageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!validMessageReceived.isCompleted) {
          validMessageReceived.complete(message);
        }
      };

      // Send a valid message
      sendRawJsonMessage(clientToServerController, const JsonRpcPingRequest(id: 7));

      // Wait for valid message to be received
      final validMessage = await validMessageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Valid message not received after error'),
      );

      // Verify message received correctly
      expect(validMessage, isA<JsonRpcPingRequest>());
      expect((validMessage as JsonRpcPingRequest).id, 7);
    });

    test('Cannot start transport twice', () async {
      await serverTransport.start();

      // Attempt to start again should throw
      expect(() => serverTransport.start(), throwsA(isA<StateError>()));
    });

    test('Cannot send messages after transport is closed', () async {
      await serverTransport.start();
      await serverTransport.close();

      // Attempt to send message from closed transport should throw
      expect(() => serverTransport.send(const JsonRpcPingRequest(id: 8)), throwsA(isA<StateError>()));
    });

    test('Partial JSON messages are buffered until complete', () async {
      await serverTransport.start();

      // Setup a completer for message receipt
      final messageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!messageReceived.isCompleted) {
          messageReceived.complete(message);
        }
      };

      // Create a message and encode it
      final message = const JsonRpcPingRequest(id: 9);
      final jsonString = "${jsonEncode(message.toJson())}\n";
      final bytes = utf8.encode(jsonString);

      // Split the message into multiple parts
      final partOne = bytes.sublist(0, bytes.length ~/ 2);
      final partTwo = bytes.sublist(bytes.length ~/ 2);

      // Send first part and check no message is received yet
      clientToServerController.add(partOne);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(serverReceivedMessages.isEmpty, isTrue);

      // Send second part and wait for complete message
      clientToServerController.add(partTwo);
      final receivedMessage = await messageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Complete message not received'),
      );

      // Verify message was received correctly
      expect(receivedMessage, isA<JsonRpcPingRequest>());
      expect((receivedMessage as JsonRpcPingRequest).id, 9);
    });

    test('Error in onmessage handler is caught and reported', () async {
      await serverTransport.start();

      // Set up a completer to capture the reported error
      final errorReported = Completer<Error>();

      // Set up an onmessage handler that throws an error
      serverTransport.onmessage = (message) {
        throw StateError('Intentional error in onmessage handler');
      };

      // Set up an onerror handler to capture the error
      serverTransport.onerror = (error) {
        if (!errorReported.isCompleted) {
          errorReported.complete(error);
        }
      };

      // Send a message to trigger the error
      sendRawJsonMessage(clientToServerController, const JsonRpcPingRequest(id: 10));

      // Wait for the error to be reported
      final reportedError = await errorReported.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Error not reported'),
      );

      // Verify the error was reported with the correct message
      expect(reportedError, isA<StateError>());
      expect(reportedError.toString(), contains('onmessage handler'));
    });

    test('Error in onerror handler is handled gracefully', () async {
      await serverTransport.start();

      // Set up an onerror handler that throws another error
      serverTransport.onerror = (error) {
        throw StateError('Intentional error in onerror handler');
      };

      // Send invalid JSON data to trigger an error
      clientToServerController.add(utf8.encode('invalid json\n'));

      // Wait a moment to allow error processing
      await Future.delayed(const Duration(milliseconds: 100));

      // We can't easily assert what happens here, but the transport should remain functional
      // and not crash. Let's send another valid message and make sure it works.

      // Reset the onerror handler so it doesn't throw again
      serverTransport.onerror = null;

      // Set up a completer for subsequent valid message
      final validMessageReceived = Completer<JsonRpcMessage>();
      serverTransport.onmessage = (message) {
        serverReceivedMessages.add(message);
        if (!validMessageReceived.isCompleted) {
          validMessageReceived.complete(message);
        }
      };

      // Send a valid message
      sendRawJsonMessage(clientToServerController, const JsonRpcPingRequest(id: 11));

      // Wait for valid message to be received, showing transport still works
      final validMessage = await validMessageReceived.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Valid message not received after error'),
      );

      // Verify message received correctly
      expect(validMessage, isA<JsonRpcPingRequest>());
      expect((validMessage as JsonRpcPingRequest).id, 11);
    });

    test('Transport handles incomplete message at end of stream', () async {
      await serverTransport.start();

      // Create a message but don't add the newline terminator
      final message = const JsonRpcPingRequest(id: 12);
      final jsonString = jsonEncode(message.toJson()); // No newline at the end

      // Send the incomplete message
      clientToServerController.add(utf8.encode(jsonString));

      // Wait a moment to allow processing
      await Future.delayed(const Duration(milliseconds: 100));

      // No message should be received since it's incomplete
      expect(serverReceivedMessages.isEmpty, isTrue);

      // Now close the stream
      await clientToServerController.close();

      // Wait for the transport to close
      await serverCloseCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Transport not closed'),
      );

      // Verify no message was extracted from the incomplete data
      expect(serverReceivedMessages.isEmpty, isTrue);
    });
  });

  group('IOStreamTransport edge cases', () {
    test('malformed UTF-8 line is skipped, valid message still delivered', () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final transport = IOStreamTransport(stream: input.stream, sink: output.sink);

      final messages = <JsonRpcMessage>[];
      final errors = <Error>[];
      final messageReceived = Completer<void>();

      transport.onmessage = (m) {
        messages.add(m);
        if (!messageReceived.isCompleted) messageReceived.complete();
      };
      transport.onerror = (e) => errors.add(e);

      await transport.start();

      // Invalid UTF-8 line followed by a valid JSON-RPC line.
      final invalidUtf8 = [0xFF, 0xFE, 0x0A]; // bad bytes + \n
      final validLine = utf8.encode('{"jsonrpc":"2.0","method":"ping","id":20}\n');
      input.add(Uint8List.fromList([...invalidUtf8, ...validLine]));

      await messageReceived.future.timeout(const Duration(seconds: 2));

      // MalformedLineException is caught internally and logged — it should
      // NOT propagate to onerror.
      expect(errors, isEmpty);
      expect(messages, hasLength(1));
      expect(messages.first, isA<JsonRpcPingRequest>());
      expect((messages.first as JsonRpcPingRequest).id, 20);

      await transport.close();
      await input.close();
      await output.close();
    });

    test('FormatException fires onerror but continues to next message', () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final transport = IOStreamTransport(stream: input.stream, sink: output.sink);

      final messages = <JsonRpcMessage>[];
      final errors = <Error>[];
      final messageReceived = Completer<void>();

      transport.onmessage = (m) {
        messages.add(m);
        if (!messageReceived.isCompleted) messageReceived.complete();
      };
      transport.onerror = (e) => errors.add(e);

      await transport.start();

      // Invalid JSON line + valid JSON-RPC line in one chunk.
      final chunk = utf8.encode(
        'not valid json\n'
        '{"jsonrpc":"2.0","method":"ping","id":30}\n',
      );
      input.add(chunk);

      await messageReceived.future.timeout(const Duration(seconds: 2));

      expect(errors, hasLength(1), reason: 'invalid JSON should fire onerror');
      expect(errors.first.toString(), contains('Invalid JSON'));
      expect(messages, hasLength(1));
      expect((messages.first as JsonRpcPingRequest).id, 30);

      await transport.close();
      await input.close();
      await output.close();
    });

    test('multiple messages in single chunk are all delivered', () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final transport = IOStreamTransport(stream: input.stream, sink: output.sink);

      final messages = <JsonRpcMessage>[];
      final allReceived = Completer<void>();

      transport.onmessage = (m) {
        messages.add(m);
        if (messages.length >= 2 && !allReceived.isCompleted) {
          allReceived.complete();
        }
      };

      await transport.start();

      input.add(
        utf8.encode(
          '{"jsonrpc":"2.0","method":"ping","id":40}\n'
          '{"jsonrpc":"2.0","method":"ping","id":41}\n',
        ),
      );

      await allReceived.future.timeout(const Duration(seconds: 2));

      expect(messages, hasLength(2));
      expect((messages[0] as JsonRpcPingRequest).id, 40);
      expect((messages[1] as JsonRpcPingRequest).id, 41);

      await transport.close();
      await input.close();
      await output.close();
    });

    test('partial message buffered across chunks', () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final transport = IOStreamTransport(stream: input.stream, sink: output.sink);

      final messages = <JsonRpcMessage>[];
      final received = Completer<void>();

      transport.onmessage = (m) {
        messages.add(m);
        if (!received.isCompleted) received.complete();
      };

      await transport.start();

      final full = utf8.encode('{"jsonrpc":"2.0","method":"ping","id":50}\n');
      final mid = full.length ~/ 2;

      // First chunk: no newline yet.
      input.add(full.sublist(0, mid));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(messages, isEmpty);

      // Second chunk: completes the line.
      input.add(full.sublist(mid));
      await received.future.timeout(const Duration(seconds: 2));

      expect(messages, hasLength(1));
      expect((messages.first as JsonRpcPingRequest).id, 50);

      await transport.close();
      await input.close();
      await output.close();
    });

    test('buffer overflow fires onerror and closes transport', () async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();

      // Construct a transport that wraps a tiny ReadBuffer. The default
      // constructor uses ReadBuffer() internally, but _onStreamData checks
      // append() return value. We feed >default-max bytes, but that's huge.
      // Instead, we rely on the IOStreamTransport code path by sending a
      // chunk that exceeds the default 10 MB — impractical. So we test the
      // ReadBuffer directly for the size-limited case (covered in the
      // ReadBuffer group) and here verify the transport's reaction to a
      // stream error triggered by the overflow path.
      //
      // To actually hit the overflow in IOStreamTransport we'd need to
      // supply a custom ReadBuffer, which the constructor doesn't expose.
      // Instead, we verify the contract: if the stream itself errors, the
      // transport fires onerror and closes.
      final transport = IOStreamTransport(stream: input.stream, sink: output.sink);

      final errors = <Error>[];
      final closed = Completer<void>();

      transport.onerror = (e) => errors.add(e);
      transport.onclose = () {
        if (!closed.isCompleted) closed.complete();
      };

      await transport.start();

      // Simulate a stream error (analogous to what the OS would emit on a
      // broken pipe, which exercises the same onerror + close path as the
      // buffer overflow branch).
      input.addError(StateError('simulated overflow / broken pipe'));

      await closed.future.timeout(const Duration(seconds: 2));

      expect(errors, hasLength(1));
      expect(errors.first, isA<StateError>());
      expect(errors.first.toString(), contains('simulated overflow'));

      await input.close();
      await output.close();
    });
  });
}

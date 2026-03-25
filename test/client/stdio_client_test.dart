import 'dart:async';
import 'dart:io' as io;

import 'package:mcp_dart/src/client/stdio.dart';
import 'package:mcp_dart/src/types.dart';
import 'package:test/test.dart';

void main() {
  group('StdioClientTransport', () {
    test('throws StateError when process fails to start', () async {
      // Use a command that doesn't exist
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'nonexistent_command_that_does_not_exist_12345', args: ['arg1']),
      );

      expect(() => transport.start(), throwsA(isA<StateError>()));
    });

    test('throws StateError when started twice', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'sleep', args: ['5'], stderrMode: io.ProcessStartMode.normal),
      );

      await transport.start();

      expect(() => transport.start(), throwsA(isA<StateError>()));

      await transport.close();
    });

    test('send throws StateError when not started', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'echo', args: ['test'], stderrMode: io.ProcessStartMode.normal),
      );

      expect(() => transport.send(const JsonRpcNotification(method: 'test', params: {})), throwsA(isA<StateError>()));
    });

    test('send throws StateError after close', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'sleep', args: ['5'], stderrMode: io.ProcessStartMode.normal),
      );

      await transport.start();
      await transport.close();

      expect(() => transport.send(const JsonRpcNotification(method: 'test', params: {})), throwsA(isA<StateError>()));
    });

    test('onclose callback is called when closing', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'sleep', args: ['5'], stderrMode: io.ProcessStartMode.normal),
      );

      bool oncloseCalled = false;
      transport.onclose = () {
        oncloseCalled = true;
      };

      await transport.start();
      await transport.close();

      expect(oncloseCalled, isTrue);
    });

    test('sessionId is always null for stdio transport', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'sleep', args: ['5'], stderrMode: io.ProcessStartMode.normal),
      );

      expect(transport.sessionId, isNull);

      await transport.start();
      expect(transport.sessionId, isNull);

      await transport.close();
    });

    test('close does nothing if not started', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'echo', args: ['test'], stderrMode: io.ProcessStartMode.normal),
      );

      bool oncloseCalled = false;
      transport.onclose = () {
        oncloseCalled = true;
      };

      await transport.close();

      expect(oncloseCalled, isFalse, reason: 'onclose must not fire when transport was never started');
    });

    test('stderr is accessible when stderrMode is normal', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'bash',
          args: ['-c', 'echo err >&2; sleep 2'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      await transport.start();

      expect(transport.stderr, isNotNull);

      final stderrCompleter = Completer<String>();
      final stderrData = StringBuffer();
      transport.stderr!.listen(
        (data) {
          stderrData.write(String.fromCharCodes(data));
          if (stderrData.toString().contains('err') && !stderrCompleter.isCompleted) {
            stderrCompleter.complete(stderrData.toString());
          }
        },
        onDone: () {
          if (!stderrCompleter.isCompleted) stderrCompleter.complete(stderrData.toString());
        },
      );

      final output = await stderrCompleter.future.timeout(const Duration(seconds: 5));
      expect(output.trim(), contains('err'));

      await transport.close();
    });

    test('multiple close calls are safe', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'sleep', args: ['5'], stderrMode: io.ProcessStartMode.normal),
      );

      int oncloseCount = 0;
      transport.onclose = () {
        oncloseCount++;
      };

      await transport.start();
      await transport.close();
      await transport.close();
      await transport.close();

      expect(oncloseCount, equals(1));
    });

    test('send writes message to process stdin and onmessage receives echo', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'cat', stderrMode: io.ProcessStartMode.normal),
      );

      final messageCompleter = Completer<JsonRpcMessage>();
      transport.onmessage = (msg) {
        if (!messageCompleter.isCompleted) messageCompleter.complete(msg);
      };

      await transport.start();

      final notification = const JsonRpcNotification(method: 'notifications/initialized');
      await transport.send(notification);

      final received = await messageCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('onmessage was not called — cat did not echo the message'),
      );

      expect(received, isA<JsonRpcNotification>());
      expect((received as JsonRpcNotification).method, equals('notifications/initialized'));

      await transport.close();
    });

    test('onerror fires when process exits unexpectedly during send', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'bash',
          args: ['-c', 'read line; exit 1'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      final errorCompleter = Completer<Error>();
      transport.onerror = (error) {
        if (!errorCompleter.isCompleted) errorCompleter.complete(error);
      };

      final oncloseCompleter = Completer<void>();
      transport.onclose = () {
        if (!oncloseCompleter.isCompleted) oncloseCompleter.complete();
      };

      await transport.start();

      final notification = const JsonRpcNotification(method: 'notifications/initialized');
      await transport.send(notification);

      await oncloseCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('onclose was not called after process exited'),
      );
    });

    test('onmessage delivers parsed messages from stdout', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'cat', stderrMode: io.ProcessStartMode.normal),
      );

      final messages = <JsonRpcMessage>[];
      final twoReceived = Completer<void>();
      transport.onmessage = (msg) {
        messages.add(msg);
        if (messages.length == 2 && !twoReceived.isCompleted) twoReceived.complete();
      };

      await transport.start();

      await transport.send(const JsonRpcNotification(method: 'notifications/initialized'));
      await transport.send(const JsonRpcPingRequest(id: 1));

      await twoReceived.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('Did not receive 2 messages back from cat'),
      );

      expect(messages.length, equals(2));
      expect(messages[0], isA<JsonRpcNotification>());
      expect(messages[1], isA<JsonRpcPingRequest>());
      expect((messages[1] as JsonRpcPingRequest).id, equals(1));

      await transport.close();
    });

    test('stdout close triggers onclose', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'echo', args: ['hello'], stderrMode: io.ProcessStartMode.normal),
      );

      final oncloseCompleter = Completer<void>();
      transport.onclose = () {
        if (!oncloseCompleter.isCompleted) oncloseCompleter.complete();
      };

      await transport.start();

      await oncloseCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('onclose was not called after process exited'),
      );
    });

    test('restart after close', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'sleep', args: ['5'], stderrMode: io.ProcessStartMode.normal),
      );

      int oncloseCount = 0;
      transport.onclose = () {
        oncloseCount++;
      };

      await transport.start();
      await transport.close();
      expect(oncloseCount, equals(1));

      await transport.start();
      await transport.close();
      expect(oncloseCount, equals(2));
    });

    test('send after process exit throws StateError and onclose fires', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(command: 'echo', args: ['hello'], stderrMode: io.ProcessStartMode.normal),
      );

      final oncloseCompleter = Completer<void>();
      transport.onclose = () {
        if (!oncloseCompleter.isCompleted) oncloseCompleter.complete();
      };

      await transport.start();

      await oncloseCompleter.future.timeout(const Duration(seconds: 5));

      expect(() => transport.send(const JsonRpcNotification(method: 'test', params: {})), throwsA(isA<StateError>()));
    });

    test('transport closes when process is killed with SIGKILL', () async {
      final transport = StdioClientTransport(
        const StdioServerParameters(
          command: 'bash',
          args: ['-c', r'sleep 0.5; kill -9 $$'],
          stderrMode: io.ProcessStartMode.normal,
        ),
      );

      final oncloseCompleter = Completer<void>();
      final errors = <Error>[];

      transport.onclose = () {
        if (!oncloseCompleter.isCompleted) oncloseCompleter.complete();
      };
      transport.onerror = errors.add;

      await transport.start();

      // Process self-SIGKILLs after ~500ms; stdout closes → transport tears down
      await oncloseCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('onclose was not called after SIGKILL'),
      );

      expect(() => transport.send(const JsonRpcNotification(method: 'test', params: {})), throwsA(isA<StateError>()));
    });
  });
}

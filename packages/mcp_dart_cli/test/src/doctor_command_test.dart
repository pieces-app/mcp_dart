import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:mcp_dart_cli/src/doctor_command.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('DoctorCommand', () {
    late Logger logger;
    late DoctorCommand command;
    late Directory tempDir;
    late Directory originalCwd;

    setUp(() {
      logger = MockLogger();
      command = DoctorCommand(logger: logger);
      originalCwd = Directory.current;
      tempDir = Directory.systemTemp.createTempSync('doctor_test_');
      tempDir = Directory(tempDir.resolveSymbolicLinksSync());
      Directory.current = tempDir;
    });

    tearDown(() {
      try {
        Directory.current = originalCwd;
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('can be instantiated', () {
      expect(command, isA<DoctorCommand>());
    });

    test('static checks passed', () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
dependencies:
  mcp: ^0.1.0
''');
      Directory(p.join(tempDir.path, 'lib', 'mcp')).createSync(recursive: true);
      File(p.join(tempDir.path, 'lib', 'mcp', 'mcp.dart')).writeAsStringSync('void main() {}');
      File(p.join(tempDir.path, 'analysis_options.yaml')).writeAsStringSync('');

      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);
      // Static checks pass but dynamic verification will fail (dummy project with
      // no real MCP server). The connection attempt can be slow on ARM emulation
      // runners, so use a generous timeout.
      await runner.run(['doctor']);

      verify(() => logger.success('[✓] pubspec.yaml exists')).called(1);
      verify(() => logger.success('[✓] mcp dependency found')).called(1);
      verify(() => logger.success('[✓] lib/mcp/mcp.dart exists')).called(1);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('fails if pubspec.yaml is missing', () async {
      final runner = CommandRunner<int>('mcp_dart', 'CLI')..addCommand(command);
      await runner.run(['doctor']);
      verify(() => logger.err('[x] pubspec.yaml not found')).called(1);
    });
  });
}

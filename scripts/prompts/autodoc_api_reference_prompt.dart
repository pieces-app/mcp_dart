// ignore_for_file: avoid_print

import 'dart:io';

import '_ci_config.dart';

/// Autodoc: API_REFERENCE.md generator for a proto module.
///
/// Usage:
///   dart run scripts/prompts/autodoc_api_reference_prompt.dart <module_name> <source_dir> <lib_dir>

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: autodoc_api_reference_prompt.dart <module_name> <source_dir> [lib_dir]');
    exit(1);
  }

  final pkg = CiConfig.current.packageName;
  final moduleName = args[0];
  final sourceDir = args[1];
  final libDir = args.length > 2 ? args[2] : '';

  // Gather all proto content (truncated if massive)
  final protoFiles = _runSync('find $sourceDir -name "*.proto" -type f 2>/dev/null');
  final allProtoContent = StringBuffer();
  for (final file in protoFiles.split('\n').where((f) => f.isNotEmpty)) {
    allProtoContent.writeln('// === $file ===');
    allProtoContent.writeln(_truncate(_runSync('cat "$file"'), 20000));
    allProtoContent.writeln();
  }

  final protoContent = _truncate(allProtoContent.toString(), 60000);

  // Check for generated Dart code
  String dartPreview = '';
  if (libDir.isNotEmpty && Directory(libDir).existsSync()) {
    final generatedFiles = _runSync('find $libDir -name "*.pb.dart" -o -name "*.pbgrpc.dart" 2>/dev/null | head -5');
    if (generatedFiles.isNotEmpty) {
      final buf = StringBuffer();
      for (final file in generatedFiles.split('\n').where((f) => f.isNotEmpty)) {
        buf.writeln('// === $file ===');
        buf.writeln(_truncate(_runSync('cat "$file"'), 10000));
        buf.writeln();
      }
      dartPreview = _truncate(buf.toString(), 30000);
    }
  }

  print('''
You are a documentation writer generating an API reference for the
**$moduleName** module of the $pkg Dart package.

## Proto Definitions

```protobuf
$protoContent
```

${dartPreview.isNotEmpty ? '## Generated Dart Code\n\n```dart\n$dartPreview\n```' : ''}

## Instructions

Generate an API_REFERENCE.md with these sections:

### 1. Messages
For EACH message type in the proto files:
- **MessageName** -- one-line description (from proto comments or inferred)
  - List all fields with types and descriptions
  - Note required vs optional fields
  - Document any oneof groups

### 2. Services (if any)
For EACH service:
- **ServiceName** -- what it does
  - List all RPC methods with input/output types
  - Note streaming methods (client/server/bidi)

### 3. Enums
For EACH enum:
- **EnumName** -- what it represents
  - List all values with descriptions

### 4. Dart Usage
For key message types, show the Dart class name and basic usage:
```dart
final msg = MessageName()
  ..field1 = value1
  ..field2 = value2;
```

### 5. Installation
```yaml
dependencies:
  $pkg:
    git:
      url: git@github.com:${CiConfig.current.repoOwner}/$pkg.git
      tag_pattern: v{{version}}
```

## Rules
- Use ONLY names that appear in the proto definitions above
- Do NOT fabricate fields, methods, or enum values
- Group related messages together
- Keep descriptions concise but informative
- Use the proto field names (the Dart names are camelCase equivalents)

## Strict Output Constraints
- Output ONLY the requested `.md` content.
- Write ONLY the target markdown file selected by the calling command.
- Do NOT create helper scripts, temp programs, generated code, or any non-Markdown artifacts.
- Do NOT use shell commands to write files or run code-generation scripts.

Generate the complete API_REFERENCE.md content. Write it ONLY to the exact
`.md` path provided by the calling command, and do not create any other files.
''');
}

String _runSync(String command) {
  try {
    final result = Process.runSync('sh', ['-c', command], workingDirectory: Directory.current.path);
    if (result.exitCode == 0) return (result.stdout as String).trim();
    return '';
  } catch (_) {
    return '';
  }
}

String _truncate(String input, int maxChars) {
  if (input.length <= maxChars) return input;
  return '${input.substring(0, maxChars)}\n\n... [TRUNCATED]\n';
}

// ignore_for_file: avoid_print

import 'dart:io';

import '_ci_config.dart';

/// Autodoc: EXAMPLES.md generator for a proto module.
///
/// Usage:
///   dart run scripts/prompts/autodoc_examples_prompt.dart <module_name> <source_dir> <lib_dir>

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: autodoc_examples_prompt.dart <module_name> <source_dir> [lib_dir]');
    exit(1);
  }

  final pkg = CiConfig.current.packageName;
  final moduleName = args[0];
  final sourceDir = args[1];
  final libDir = args.length > 2 ? args[2] : '';

  // Gather proto services and messages
  final services = _runSync('grep -rn "^service\\|^  rpc" $sourceDir 2>/dev/null');
  final messages = _runSync('grep -rn "^message" $sourceDir 2>/dev/null | head -30');
  final enums = _runSync('grep -rn "^enum" $sourceDir 2>/dev/null');

  // Look for test files
  String testContent = '(no tests found)';
  final testDir = libDir.isNotEmpty ? libDir.replaceFirst('lib/', 'test/') : '';
  if (testDir.isNotEmpty && Directory(testDir).existsSync()) {
    testContent = _truncate(_runSync('find $testDir -name "*_test.dart" -exec head -50 {} \\; 2>/dev/null'), 10000);
  }

  // Look for extension files (usage patterns)
  String extensionContent = '';
  if (libDir.isNotEmpty) {
    extensionContent = _truncate(
      _runSync('find $libDir -name "*extensions*" -o -name "*helpers*" | head -3 | xargs head -40 2>/dev/null'),
      5000,
    );
  }

  print('''
You are writing practical code examples for the **$moduleName** module
of the $pkg Dart package.

## Available Services and RPCs
```
$services
```

## Key Message Types
```
$messages
```

## Enums
```
$enums
```

${testContent != '(no tests found)' ? '## Existing Test Patterns\n```dart\n$testContent\n```' : ''}

${extensionContent.isNotEmpty ? '## Extension/Helper Patterns\n```dart\n$extensionContent\n```' : ''}

## Instructions

Generate an EXAMPLES.md with practical, copy-paste-ready code examples:

### 1. Basic Usage
- Create and populate the most common message types
- Show the builder pattern if available

### 2. Service Calls (if services exist)
- Set up a gRPC channel and client
- Make a unary call with error handling
- Handle streaming responses (if server/client streaming RPCs exist)

### 3. Data Conversion
- Convert messages to/from JSON
- Work with maps and lists of messages
- Handle oneof fields with pattern matching

### 4. Integration Patterns
- How this module connects to other modules in the library
- Common workflows (e.g., create request → send → process response)

### 5. Error Handling
- gRPC error codes and what they mean for this service
- Retry patterns for transient failures

## Rules
- Use ONLY real class/method names from the proto definitions
- Every code block must be valid, compilable Dart
- Import from package:$pkg/...
- Show complete, runnable examples (not fragments)
- Include comments explaining what each step does

## Strict Output Constraints
- Output ONLY the requested `.md` content.
- Write ONLY the target markdown file selected by the calling command.
- Do NOT create helper scripts, temp programs, generated code, or any non-Markdown artifacts.
- Do NOT use shell commands to write files or run code-generation scripts.

Generate the complete EXAMPLES.md content. Write it ONLY to the exact `.md`
path provided by the calling command, and do not create any other files.
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

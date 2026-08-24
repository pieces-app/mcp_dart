// ignore_for_file: avoid_print

import 'dart:io';

import '_ci_config.dart';

/// Autodoc: QUICKSTART.md generator for a proto module.
///
/// Usage:
///   dart run scripts/prompts/autodoc_quickstart_prompt.dart <module_name> <source_dir> <lib_dir> <output_path>

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: autodoc_quickstart_prompt.dart <module_name> <source_dir> [lib_dir]');
    exit(1);
  }

  final pkg = CiConfig.current.packageName;
  final moduleName = args[0];
  final sourceDir = args[1];
  final libDir = args.length > 2 ? args[2] : '';

  final protoTree = _runSync(
    'tree $sourceDir -L 3 --dirsfirst 2>/dev/null || find $sourceDir -name "*.proto" | head -30',
  );
  final protoFiles = _runSync('find $sourceDir -name "*.proto" -type f 2>/dev/null');
  final protoCount = _runSync('find $sourceDir -name "*.proto" -type f 2>/dev/null | wc -l');

  // Read first proto file for service/message overview
  final firstProto = _runSync('find $sourceDir -name "*.proto" -type f 2>/dev/null | head -1');
  final protoPreview = firstProto.isNotEmpty ? _truncate(_runSync('cat "$firstProto"'), 15000) : '(no proto files)';

  // Check for existing generated Dart code
  String libTree = '(no lib directory)';
  String dartPreview = '';
  if (libDir.isNotEmpty && Directory(libDir).existsSync()) {
    libTree = _runSync(
      'tree $libDir -L 2 --dirsfirst -I "*.pb.dart|*.pbenum.dart|*.pbjson.dart|*.pbgrpc.dart|*.enhance.*" 2>/dev/null || echo "(no tree)"',
    );
    final firstDart = _runSync(
      'find $libDir -name "*.dart" -not -name "*.pb.*" -not -name "*.enhance.*" -type f 2>/dev/null | head -1',
    );
    if (firstDart.isNotEmpty) {
      dartPreview = _truncate(_runSync('cat "$firstDart"'), 5000);
    }
  }

  // Check for gRPC services
  final services = _runSync('grep -r "^service " $sourceDir 2>/dev/null || echo "(no services)"');
  final messages = _runSync('grep -rn "^message " $sourceDir 2>/dev/null | head -30');

  // --- Changelog context for "What's New" section ---
  String changelogPreview = '';
  final changelogFile = File('CHANGELOG.md');
  if (changelogFile.existsSync()) {
    final changelog = changelogFile.readAsStringSync();
    final versionPattern = RegExp(r'^## .*$', multiLine: true);
    final matches = versionPattern.allMatches(changelog).toList();
    if (matches.isNotEmpty) {
      final firstEnd = matches.length > 1 ? matches[1].start : changelog.length;
      changelogPreview = _truncate(changelog.substring(matches[0].start, firstEnd), 3000);
    }
  }

  print('''
You are a documentation writer for the **$moduleName** module of the
$pkg Dart package.

Your job is to write a QUICKSTART.md that helps a developer get started
with this module in under 5 minutes.

## Module Structure

### Proto Files ($protoCount files)
```
$protoTree
```

### Proto File List
```
$protoFiles
```

### Generated Dart Code
```
$libTree
```

### Services Defined
```
$services
```

### Key Message Types
```
$messages
```

## Proto File Preview (first file)
```protobuf
$protoPreview
```

${dartPreview.isNotEmpty ? '## Dart Code Preview\n```dart\n$dartPreview\n```' : ''}

${changelogPreview.isNotEmpty ? '## Recent Changes (CHANGELOG)\n```markdown\n$changelogPreview\n```\n' : ''}

## Instructions

Write a QUICKSTART.md with these sections:

### 1. Overview
- What this module does (2-3 sentences)
- What APIs/services it provides
${changelogPreview.isNotEmpty ? '\n### 1a. What\'s New\nIf the CHANGELOG above contains notable changes for this module,\nadd a brief "What\'s New" subsection highlighting the most impactful 2-3 changes.\nOnly include this if there are genuinely relevant recent changes.' : ''}

### 2. Installation
Add `$pkg` to your `pubspec.yaml`:
```yaml
dependencies:
  $pkg:
    git:
      url: git@github.com:${CiConfig.current.repoOwner}/$pkg.git
      tag_pattern: v{{version}}
```
Then run `dart pub get`.

### 3. Import
```dart
import 'package:$pkg/...';
```
Use the REAL import paths based on the lib directory structure.

### 3. Setup
Show how to create a client/channel (if gRPC service) or instantiate key messages.
Use REAL class names from the proto definitions.

### 4. Common Operations
3-5 code examples showing the most useful operations:
- Creating and populating key messages
- Making service calls (if applicable)
- Handling responses
- Working with enums and oneof fields

### 5. Error Handling
Common error patterns and how to handle them.

### 6. Related Modules
List any related modules in the $pkg.

## Rules
- Use ONLY real class/method/field names from the proto definitions
- Do NOT fabricate API names or import paths
- Code examples must be valid Dart that would compile
- Keep it concise -- this is a QUICKSTART, not a full reference
- Use the package import style: package:$pkg/...

## Strict Output Constraints
- Output ONLY the requested `.md` content.
- Write ONLY the target markdown file selected by the calling command.
- Do NOT create helper scripts, temp programs, generated code, or any non-Markdown artifacts.
- Do NOT use shell commands to write files or run code-generation scripts.

Generate the complete QUICKSTART.md content. Write it ONLY to the exact `.md`
path provided by the calling command, and do not create any other files.
''');
}

String _runSync(String command) {
  try {
    final result = Process.runSync('sh', ['-c', command], workingDirectory: Directory.current.path);
    if (result.exitCode == 0) return (result.stdout as String).trim();
    return '(command failed)';
  } catch (_) {
    return '(unavailable)';
  }
}

String _truncate(String input, int maxChars) {
  if (input.length <= maxChars) return input;
  return '${input.substring(0, maxChars)}\n\n... [TRUNCATED: ${input.length - maxChars} chars omitted]\n';
}

import 'dart:convert';
import 'dart:io';

/// Reads package name and repo owner from `.runtime_ci/config.json`.
///
/// Falls back to `runtime_isomorphic_library` / `open-runtime` when
/// config is unavailable — e.g. when running locally outside a
/// properly initialised repo.
class CiConfig {
  CiConfig._({required this.packageName, required this.repoOwner, required this.language});

  final String packageName;
  final String repoOwner;
  final String language;

  /// Fully-qualified npm package specifier used for install/import examples.
  ///
  /// When `repository.name` is already scoped (for example,
  /// `@open-runtime/runtime-isomorphic-library-ts`), preserve it as-is.
  /// Otherwise synthesize the published GitHub Packages name from the repo
  /// owner and a kebab-cased package name.
  String get npmPackageSpecifier {
    final trimmedName = packageName.trim();
    if (_isScopedPackageSpecifier(trimmedName)) return trimmedName;
    return '@$repoOwner/${_normalizeUnscopedPackageName(trimmedName)}';
  }

  /// Scope used in `.npmrc`, including the `@` prefix.
  String get npmRegistryScope => '@$npmPackageScope';

  /// Organization/user scope used by GitHub Packages URLs.
  String get npmPackageScope {
    final specifier = npmPackageSpecifier;
    if (_isScopedPackageSpecifier(specifier)) {
      return specifier.split('/').first.substring(1);
    }
    return repoOwner;
  }

  /// Unscoped npm package slug used by GitHub Packages URLs.
  String get npmPackageName {
    final specifier = npmPackageSpecifier;
    if (_isScopedPackageSpecifier(specifier)) {
      return specifier.split('/').last;
    }
    return specifier;
  }

  static CiConfig? _instance;

  /// Singleton that reads the config once and caches it.
  static CiConfig get current => _instance ??= _load();

  static CiConfig _load() {
    const fallbackName = 'runtime_isomorphic_library';
    const fallbackOwner = 'open-runtime';

    // Walk upward from CWD to find .runtime_ci/config.json (up to 5 levels).
    var dir = Directory.current;
    for (var i = 0; i < 5; i++) {
      final configFile = File('${dir.path}/.runtime_ci/config.json');
      if (configFile.existsSync()) {
        try {
          final json_ = json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
          final repo = json_['repository'] as Map<String, dynamic>? ?? {};
          final ci = json_['ci'] as Map<String, dynamic>? ?? {};
          return CiConfig._(
            packageName: (repo['name'] as String?) ?? fallbackName,
            repoOwner: (repo['owner'] as String?) ?? fallbackOwner,
            language: _resolveLanguage(ci),
          );
        } catch (_) {
          break;
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    return CiConfig._(packageName: fallbackName, repoOwner: fallbackOwner, language: 'dart');
  }

  static String _resolveLanguage(Map<String, dynamic> ci) {
    final language = (ci['language'] as String?)?.trim().toLowerCase();
    if (language != null && language.isNotEmpty) {
      return language;
    }

    final languages = ci['languages'];
    if (languages is List) {
      final normalized = languages
          .whereType<String>()
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toList();
      if (normalized.contains('typescript')) return 'typescript';
      if (normalized.contains('flutter')) return 'flutter';
      if (normalized.contains('dart')) return 'dart';
      if (normalized.isNotEmpty) return normalized.first;
    }

    return 'dart';
  }

  static bool _isScopedPackageSpecifier(String value) => value.startsWith('@') && value.split('/').length == 2;

  static String _normalizeUnscopedPackageName(String value) => value.replaceAll('_', '-');
}

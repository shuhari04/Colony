import 'dart:io';

class ColonyBinaryLocator {
  const ColonyBinaryLocator();

  Future<String?> discover() async {
    const define = String.fromEnvironment('COLONY_BIN');
    if (define.isNotEmpty && File(define).existsSync()) return define;

    final env = Platform.environment['COLONY_BIN'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;

    final bundled = _bundledBinary();
    if (bundled != null) return bundled;

    final candidates = <String>{};
    for (final root in _searchRoots()) {
      for (final suffix in const [
        '.build/release/colony',
        '.build/debug/colony',
        '.build/arm64-apple-macosx/release/colony',
        '.build/arm64-apple-macosx/debug/colony',
        '.build/x86_64-apple-macosx/release/colony',
        '.build/x86_64-apple-macosx/debug/colony',
      ]) {
        candidates.add('${root.path}/$suffix');
      }
    }

    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) return file.absolute.path;
    }

    return 'colony';
  }

  String? _bundledBinary() {
    final executableDir = File(Platform.resolvedExecutable).parent;
    final bundled = File('${executableDir.parent.path}/Resources/colony');
    return bundled.existsSync() ? bundled.path : null;
  }

  Iterable<Directory> _searchRoots() sync* {
    final seen = <String>{};
    for (final start in <Directory>[
      Directory.current.absolute,
      File(Platform.resolvedExecutable).parent.absolute,
    ]) {
      var dir = start;
      while (true) {
        final path = dir.path;
        if (!seen.add(path)) break;
        yield dir;
        final parent = dir.parent;
        if (parent.path == path) break;
        dir = parent;
      }
    }
  }
}

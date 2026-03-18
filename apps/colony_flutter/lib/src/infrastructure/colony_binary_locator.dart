import 'dart:io';

class ColonyBinaryLocator {
  const ColonyBinaryLocator();

  Future<String?> discover() async {
    const define = String.fromEnvironment('COLONY_BIN');
    if (define.isNotEmpty && File(define).existsSync()) return define;

    final env = Platform.environment['COLONY_BIN'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;

    final candidates = <String>[
      '.build/release/colony',
      '../.build/release/colony',
      '../../.build/release/colony',
      '../../../.build/release/colony',
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) return file.absolute.path;
    }

    return 'colony';
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ColonyCli {
  final String binPath;

  ColonyCli(this.binPath);

  static Future<String?> discoverBin() async {
    const define = String.fromEnvironment('COLONY_BIN');
    if (define.isNotEmpty && File(define).existsSync()) return define;

    final env = Platform.environment['COLONY_BIN'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;

    // Try a few common dev locations relative to current directory.
    final candidates = <String>[
      '.build/release/colony',
      '../.build/release/colony',
      '../../.build/release/colony',
      '../../../.build/release/colony',
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f.absolute.path;
    }

    // Fallback: rely on PATH.
    return 'colony';
  }

  Future<List<String>> listSessions({String target = 'local', Map<String, String>? env}) async {
    final res = await Process.run(binPath, ['list', target], environment: env);
    if (res.exitCode != 0) {
      throw Exception('colony list failed: ${res.stderr}');
    }
    final out = (res.stdout as String).trim();
    if (out.isEmpty) return [];
    return out.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  Future<void> startSession(String address, List<String> command, {Map<String, String>? env}) async {
    final args = ['start', address, '--', ...command];
    final res = await Process.run(binPath, args, environment: env);
    if (res.exitCode != 0) throw Exception('colony start failed: ${res.stderr}');
  }

  Future<void> stopSession(String address, {Map<String, String>? env}) async {
    final res = await Process.run(binPath, ['stop', address], environment: env);
    if (res.exitCode != 0) throw Exception('colony stop failed: ${res.stderr}');
  }

  Future<void> send(String address, String text, {Map<String, String>? env}) async {
    final res = await Process.run(binPath, ['send', address, text], environment: env);
    if (res.exitCode != 0) throw Exception('colony send failed: ${res.stderr}');
  }

  Future<Map<String, dynamic>> codexRateLimitJson() async {
    final res = await Process.run(binPath, ['codex-rate-limit', '--json']);
    if (res.exitCode != 0) throw Exception('colony codex-rate-limit failed: ${res.stderr}');
    return jsonDecode(res.stdout as String) as Map<String, dynamic>;
  }

  Future<Process> watch(String address, {int lines = 220, int intervalMs = 300, Map<String, String>? env}) {
    final args = [
      'watch',
      address,
      '--lines',
      '$lines',
      '--interval-ms',
      '$intervalMs',
    ];
    return Process.start(binPath, args, runInShell: false, environment: env);
  }
}

class LogStream {
  final Process _proc;
  final Stream<String> lines;
  LogStream(this._proc, this.lines);

  void stop() {
    _proc.kill(ProcessSignal.sigterm);
  }
}

Future<LogStream> startLogStream(ColonyCli cli, String address, {Map<String, String>? env}) async {
  final proc = await cli.watch(address, env: env);
  final controller = StreamController<String>();
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(controller.add);
  proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
    controller.add('[stderr] $l');
  });
  proc.exitCode.then((code) {
    controller.add('[process exited $code]');
    controller.close();
  });
  return LogStream(proc, controller.stream);
}

import 'dart:convert';
import 'dart:io';

import 'colony_log_stream.dart';

abstract class ColonyCommandAdapter {
  String get binPath;

  Future<List<String>> listSessions({
    String target = 'local',
    Map<String, String>? env,
  });

  Future<List<String>> listProviders({
    String target = 'local',
    Map<String, String>? env,
  });

  Future<void> startSession(
    String address,
    List<String> command, {
    Map<String, String>? env,
  });

  Future<void> stopSession(String address, {Map<String, String>? env});

  Future<void> send(
    String address,
    String text, {
    Map<String, String>? env,
  });

  Future<Map<String, dynamic>> codexRateLimitJson();

  Future<Process> watch(
    String address, {
    int lines = 220,
    int intervalMs = 300,
    Map<String, String>? env,
  });

  Future<ColonyLogStream> startLogStream(
    String address, {
    int lines = 220,
    int intervalMs = 300,
    Map<String, String>? env,
  });
}

class ProcessColonyCommandAdapter implements ColonyCommandAdapter {
  @override
  final String binPath;

  ProcessColonyCommandAdapter(this.binPath);

  @override
  Future<List<String>> listSessions({
    String target = 'local',
    Map<String, String>? env,
  }) async {
    final res = await Process.run(binPath, ['list', target], environment: env);
    if (res.exitCode != 0) {
      throw Exception('colony list failed: ${res.stderr}');
    }
    final out = (res.stdout as String).trim();
    if (out.isEmpty) return [];
    return out.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  }

  @override
  Future<List<String>> listProviders({
    String target = 'local',
    Map<String, String>? env,
  }) async {
    final args = <String>['providers', target];
    final res = await Process.run(binPath, args, environment: env);
    if (res.exitCode != 0) {
      throw Exception('colony providers failed: ${res.stderr}');
    }
    final out = (res.stdout as String).trim();
    if (out.isEmpty) return [];
    return out.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
  }

  @override
  Future<void> startSession(
    String address,
    List<String> command, {
    Map<String, String>? env,
  }) async {
    final args = ['start', address, '--', ...command];
    final res = await Process.run(binPath, args, environment: env);
    if (res.exitCode != 0) {
      final stderr = (res.stderr as String).trim();
      final stdout = (res.stdout as String).trim();
      final detail = [
        if (stderr.isNotEmpty) stderr,
        if (stdout.isNotEmpty) 'stdout: $stdout',
      ].join('\n');
      throw Exception('colony start failed for $address: ${detail.isEmpty ? 'unknown error' : detail}');
    }
  }

  @override
  Future<void> stopSession(String address, {Map<String, String>? env}) async {
    final res = await Process.run(binPath, ['stop', address], environment: env);
    if (res.exitCode != 0) throw Exception('colony stop failed: ${res.stderr}');
  }

  @override
  Future<void> send(
    String address,
    String text, {
    Map<String, String>? env,
  }) async {
    final res = await Process.run(binPath, ['send', address, text], environment: env);
    if (res.exitCode != 0) throw Exception('colony send failed: ${res.stderr}');
  }

  @override
  Future<Map<String, dynamic>> codexRateLimitJson() async {
    final res = await Process.run(binPath, ['codex-rate-limit', '--json']);
    if (res.exitCode != 0) throw Exception('colony codex-rate-limit failed: ${res.stderr}');
    return jsonDecode(res.stdout as String) as Map<String, dynamic>;
  }

  @override
  Future<Process> watch(
    String address, {
    int lines = 220,
    int intervalMs = 300,
    Map<String, String>? env,
  }) {
    final args = <String>[
      'watch',
      address,
      '--json',
      '--lines',
      '$lines',
      '--interval-ms',
      '$intervalMs',
    ];
    return Process.start(binPath, args, runInShell: false, environment: env);
  }

  @override
  Future<ColonyLogStream> startLogStream(
    String address, {
    int lines = 220,
    int intervalMs = 300,
    Map<String, String>? env,
  }) async {
    final proc = await watch(
      address,
      lines: lines,
      intervalMs: intervalMs,
      env: env,
    );
    return ColonyLogStream.fromProcess(proc);
  }
}

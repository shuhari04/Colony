import 'dart:convert';
import 'dart:io';

import 'colony_log_stream.dart';

class ColonySessionSummary {
  final String address;
  final String node;
  final String name;
  final String provider;
  final String kind;
  final String? model;
  final String state;
  final String backend;

  const ColonySessionSummary({
    required this.address,
    required this.node,
    required this.name,
    required this.provider,
    required this.kind,
    required this.state,
    required this.backend,
    this.model,
  });

  factory ColonySessionSummary.fromJson(Map<String, dynamic> json) {
    return ColonySessionSummary(
      address: '${json['address'] ?? ''}',
      node: '${json['node'] ?? 'local'}',
      name: '${json['name'] ?? ''}',
      provider: '${json['provider'] ?? 'generic'}',
      kind: '${json['kind'] ?? 'generic'}',
      model: (json['model'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['model'] as String?)?.trim(),
      state: '${json['state'] ?? 'unknown'}',
      backend: '${json['backend'] ?? 'local_tmux'}',
    );
  }
}

class ColonyProviderSummary {
  final String id;
  final String displayName;
  final bool available;
  final String? defaultModel;
  final List<String>? supportedModels;

  const ColonyProviderSummary({
    required this.id,
    required this.displayName,
    required this.available,
    this.defaultModel,
    this.supportedModels,
  });

  factory ColonyProviderSummary.fromJson(Map<String, dynamic> json) {
    return ColonyProviderSummary(
      id: '${json['id'] ?? ''}',
      displayName: '${json['displayName'] ?? json['id'] ?? ''}',
      available: json['available'] == true,
      defaultModel: (json['defaultModel'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['defaultModel'] as String?)?.trim(),
      supportedModels: (json['supportedModels'] as List?)
          ?.map((item) => '$item')
          .toList(growable: false),
    );
  }
}

abstract class ColonyCommandAdapter {
  String get binPath;

  Future<List<ColonySessionSummary>> listSessions({
    String target = 'local',
    Map<String, String>? env,
  });

  Future<List<ColonyProviderSummary>> listProviders({
    String target = 'local',
    Map<String, String>? env,
  });

  Future<ColonySessionSummary> createSession({
    required String nodeId,
    required String name,
    required String provider,
    String? model,
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
  Future<List<ColonySessionSummary>> listSessions({
    String target = 'local',
    Map<String, String>? env,
  }) async {
    final res = await Process.run(
      binPath,
      ['session', 'list', target, '--json'],
      environment: env,
    );
    if (res.exitCode != 0) {
      throw Exception('colony list failed: ${res.stderr}');
    }
    final decoded = jsonDecode((res.stdout as String).trim());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((json) => ColonySessionSummary.fromJson(Map<String, dynamic>.from(json)))
        .toList(growable: false);
  }

  @override
  Future<List<ColonyProviderSummary>> listProviders({
    String target = 'local',
    Map<String, String>? env,
  }) async {
    final args = <String>['providers', 'list', target, '--json'];
    final res = await Process.run(binPath, args, environment: env);
    if (res.exitCode != 0) {
      throw Exception('colony providers failed: ${res.stderr}');
    }
    final decoded = jsonDecode((res.stdout as String).trim());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((json) => ColonyProviderSummary.fromJson(Map<String, dynamic>.from(json)))
        .toList(growable: false);
  }

  @override
  Future<ColonySessionSummary> createSession({
    required String nodeId,
    required String name,
    required String provider,
    String? model,
    Map<String, String>? env,
  }) async {
    final args = <String>[
      'session',
      'create',
      '--provider',
      provider,
      '--node',
      nodeId,
      '--name',
      name,
      if (model != null && model.trim().isNotEmpty) ...['--model', model.trim()],
      '--json',
    ];
    final res = await Process.run(binPath, args, environment: env);
    if (res.exitCode != 0) {
      final stderr = (res.stderr as String).trim();
      final stdout = (res.stdout as String).trim();
      final detail = [
        if (stderr.isNotEmpty) stderr,
        if (stdout.isNotEmpty) 'stdout: $stdout',
      ].join('\n');
      throw Exception('colony session create failed: ${detail.isEmpty ? 'unknown error' : detail}');
    }
    return ColonySessionSummary.fromJson(
      jsonDecode(res.stdout as String) as Map<String, dynamic>,
    );
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
      'session',
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

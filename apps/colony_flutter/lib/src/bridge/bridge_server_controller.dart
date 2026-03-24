import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'bridge_discovery_channel.dart';
import 'bridge_models.dart';

enum BridgeLifecycle { stopped, starting, running, stopping, failed }

class BridgeServerController extends ChangeNotifier {
  String workspacePath = '';
  String bridgePort = '8787';
  String bridgeToken = '';
  String advertisedAddress = '127.0.0.1';
  String statusNote = 'Ready';
  BridgeLifecycle lifecycle = BridgeLifecycle.stopped;
  bool bridgeReachable = false;
  bool codexAvailable = false;
  List<String> logs = const [];

  Process? _process;
  Timer? _healthTimer;
  bool _shutdownRequested = false;
  String? _serverScriptPath;

  Future<void> bootstrap() async {
    workspacePath = Directory.current.path;
    bridgePort = '8787';
    bridgeToken = _makeToken();
    advertisedAddress = await _resolvePrimaryIPv4Address() ?? '127.0.0.1';
    await _ensureServerScript();
    await refreshHealth();
    notifyListeners();
  }

  String get localBridgeUrl => 'http://$advertisedAddress:$normalizedPort';
  String get loopbackBridgeUrl => 'http://127.0.0.1:$normalizedPort';
  int get normalizedPort => int.tryParse(bridgePort.trim()) ?? 8787;
  String get serviceName => Platform.localHostname;

  BridgePairingPayload get pairingPayload => BridgePairingPayload(
        name: serviceName,
        url: localBridgeUrl,
        token: bridgeToken,
        workspace: workspacePath,
        bonjourType: '_colonybridge._tcp.',
      );

  Future<void> persistSettings() async {
    advertisedAddress = await _resolvePrimaryIPv4Address() ?? '127.0.0.1';
    notifyListeners();
  }

  Future<void> generateBridgeToken() async {
    bridgeToken = _makeToken();
    await persistSettings();
    _appendLog('Generated a new pairing token.');
  }

  Future<void> startBridge() async {
    if (!Platform.isMacOS) return;
    if (_process != null) {
      _appendLog('Bridge is already running.');
      return;
    }

    final nodePath = await _resolveNodePath();
    if (nodePath == null) {
      lifecycle = BridgeLifecycle.failed;
      statusNote = 'Node.js not found.';
      _appendLog('Unable to resolve node executable.');
      notifyListeners();
      return;
    }

    await _ensureServerScript();
    if (_serverScriptPath == null) {
      lifecycle = BridgeLifecycle.failed;
      statusNote = 'Bridge script unavailable.';
      notifyListeners();
      return;
    }

    await persistSettings();
    lifecycle = BridgeLifecycle.starting;
    statusNote = 'Starting bridge...';
    bridgeReachable = false;
    _shutdownRequested = false;
    notifyListeners();

    final env = Map<String, String>.from(Platform.environment)
      ..['BRIDGE_HOST'] = '0.0.0.0'
      ..['BRIDGE_PORT'] = '$normalizedPort'
      ..['BRIDGE_WORKDIR'] = workspacePath;
    if (bridgeToken.trim().isNotEmpty) {
      env['BRIDGE_TOKEN'] = bridgeToken.trim();
    }

    final process = await Process.start(
      nodePath,
      [_serverScriptPath!],
      environment: env,
      workingDirectory: workspacePath,
      runInShell: false,
    );
    _process = process;
    lifecycle = BridgeLifecycle.running;
    statusNote = 'Bridge launched. Waiting for health check...';
    notifyListeners();

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      _appendLog(line);
    });
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      _appendLog(line);
    });
    process.exitCode.then((code) async {
      _process = null;
      _stopHealthTimer();
      await BridgeDiscoveryChannel.unpublish().catchError((_) {});
      bridgeReachable = false;
      if (_shutdownRequested || code == 0) {
        lifecycle = BridgeLifecycle.stopped;
        statusNote = 'Bridge stopped.';
      } else {
        lifecycle = BridgeLifecycle.failed;
        statusNote = 'Bridge exited unexpectedly.';
      }
      _appendLog('Bridge exited with code $code');
      notifyListeners();
      await refreshHealth();
    });

    _startHealthTimer();
    await BridgeDiscoveryChannel.publish(
      name: serviceName,
      type: pairingPayload.bonjourType ?? '_colonybridge._tcp.',
      port: normalizedPort,
      txt: {
        'workspace': workspacePath.split(Platform.pathSeparator).where((part) => part.isNotEmpty).lastOrNull ?? workspacePath,
        'token': bridgeToken.trim().isEmpty ? '0' : '1',
      },
    ).catchError((_) {});
    await refreshHealth();
  }

  Future<void> stopBridge() async {
    final process = _process;
    if (process == null) return;
    _shutdownRequested = true;
    lifecycle = BridgeLifecycle.stopping;
    statusNote = 'Stopping bridge...';
    notifyListeners();
    await BridgeDiscoveryChannel.unpublish().catchError((_) {});
    process.kill();
  }

  Future<void> refreshHealth() async {
    try {
      final response = await http.get(Uri.parse('$loopbackBridgeUrl/health')).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) {
        bridgeReachable = false;
        statusNote = lifecycle == BridgeLifecycle.running ? 'Bridge is starting.' : 'Bridge is offline.';
        notifyListeners();
        return;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      bridgeReachable = json['ok'] as bool? ?? false;
      codexAvailable = json['codexAvailable'] as bool? ?? false;
      statusNote = bridgeReachable ? 'Bridge is online.' : 'Bridge is offline.';
    } catch (_) {
      bridgeReachable = false;
      if (lifecycle == BridgeLifecycle.running) {
        statusNote = 'Bridge launch is in progress.';
      } else if (lifecycle != BridgeLifecycle.failed) {
        statusNote = 'Bridge is offline.';
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopHealthTimer();
    _process?.kill();
    super.dispose();
  }

  Future<void> _ensureServerScript() async {
    if (_serverScriptPath != null && File(_serverScriptPath!).existsSync()) {
      return;
    }
    final dir = await Directory.systemTemp.createTemp('colony-bridge');
    final target = File('${dir.path}/colony_bridge_server.mjs');
    await target.parent.create(recursive: true);
    final contents = await rootBundle.loadString('assets/bridge/colony_bridge_server.mjs');
    await target.writeAsString(contents);
    _serverScriptPath = target.path;
  }

  Future<String?> _resolveNodePath() async {
    const candidates = [
      '/opt/homebrew/bin/node',
      '/usr/local/bin/node',
      '/opt/local/bin/node',
      '/usr/bin/node',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    try {
      final result = await Process.run('/usr/bin/env', ['which', 'node']);
      final output = (result.stdout as String).trim();
      if (result.exitCode == 0 && output.isNotEmpty) {
        return output;
      }
    } catch (_) {}
    return null;
  }

  void _startHealthTimer() {
    _stopHealthTimer();
    _healthTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      refreshHealth();
    });
  }

  void _stopHealthTimer() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  void _appendLog(String line) {
    logs = [...logs, line];
    if (logs.length > 300) {
      logs = logs.sublist(logs.length - 300);
    }
    notifyListeners();
  }

  String _makeToken() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(24, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  Future<String?> _resolvePrimaryIPv4Address() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final interface in interfaces) {
        if (interface.name == 'en0' || interface.name == 'en1' || interface.name.startsWith('bridge')) {
          final address = interface.addresses.where((address) => !address.isLoopback).firstOrNull;
          if (address != null) return address.address;
        }
      }
      final first = interfaces.expand((interface) => interface.addresses).where((address) => !address.isLoopback).firstOrNull;
      return first?.address;
    } catch (_) {
      return null;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}

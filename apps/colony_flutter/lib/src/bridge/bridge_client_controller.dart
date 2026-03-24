import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'bridge_discovery_channel.dart';
import 'bridge_models.dart';

class BridgeClientController extends ChangeNotifier {
  String baseUrlString = '';
  String workingDirectory = '';
  String token = '';
  BridgeExecutionMode executionMode = BridgeExecutionMode.balanced;

  List<BridgeChatMessage> messages = const [];
  List<DiscoveredBridge> discoveredBridges = const [];
  bool isRunning = false;
  String? sessionId;
  String? lastError;
  String? bannerText;
  String connectionLabel = 'Disconnected';
  bool isDiscovering = false;

  Timer? _poller;

  Future<void> bootstrap() async {
    _showPlaceholder();
    notifyListeners();
  }

  bool get canSend => sessionId != null && isRunning == false;

  String get composerPlaceholder => canSend ? 'Send to your Mac Colony bridge' : 'Connect to your Mac first';

  Future<void> applyPairingCode(String rawValue) async {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final payload = BridgePairingPayload.fromJson(decoded);
        baseUrlString = payload.url;
        if ((payload.token ?? '').isNotEmpty) token = payload.token!;
        if ((payload.workspace ?? '').isNotEmpty) workingDirectory = payload.workspace!;
        bannerText = 'Imported pairing for ${payload.name ?? "Mac Colony"}.';
        lastError = null;
        notifyListeners();
        return;
      }
    } catch (_) {}

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      baseUrlString = trimmed;
      bannerText = 'Imported bridge URL.';
      lastError = null;
      notifyListeners();
      return;
    }

    lastError = 'Unsupported QR payload.';
    notifyListeners();
  }

  void applyDiscoveredBridge(DiscoveredBridge bridge) {
    baseUrlString = bridge.urlString;
    if ((bridge.workspaceHint ?? '').isNotEmpty && workingDirectory.isEmpty) {
      workingDirectory = bridge.workspaceHint!;
    }
    bannerText = 'Selected ${bridge.name}.';
    notifyListeners();
  }

  Future<void> discoverBridges() async {
    isDiscovering = true;
    lastError = null;
    notifyListeners();
    try {
      final results = await BridgeDiscoveryChannel.browse(type: '_colonybridge._tcp.');
      discoveredBridges = results.map(DiscoveredBridge.fromJson).toList(growable: false);
    } catch (e) {
      lastError = '$e';
    } finally {
      isDiscovering = false;
      notifyListeners();
    }
  }

  Future<void> refreshSession({required bool forceReconnect}) async {
    if (baseUrlString.trim().isEmpty) {
      lastError = 'Bridge URL is required.';
      notifyListeners();
      return;
    }

    if (forceReconnect) {
      sessionId = null;
    }

    try {
      final snapshot = sessionId == null
          ? await _createSession()
          : await _fetchSession(sessionId!);
      _applySnapshot(snapshot);
      _startPolling();
    } catch (e) {
      connectionLabel = 'Offline';
      lastError = '$e';
      bannerText = 'Unable to connect to the Mac bridge.';
      _showPlaceholder();
      _stopPolling();
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text) async {
    final currentSessionId = sessionId;
    if (currentSessionId == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    try {
      final snapshot = await _perform(
        path: '/api/sessions/$currentSessionId/messages',
        method: 'POST',
        body: {'content': trimmed},
      );
      _applySnapshot(snapshot);
    } catch (e) {
      lastError = '$e';
      bannerText = 'Message delivery failed.';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    sessionId = null;
    _stopPolling();
    _showPlaceholder();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<BridgeSnapshot> _createSession() {
    return _perform(
      path: '/api/sessions',
      method: 'POST',
      body: {
        'workingDirectory': workingDirectory,
        'executionMode': bridgeExecutionModeName(executionMode),
      },
    );
  }

  Future<BridgeSnapshot> _fetchSession(String id) {
    return _perform(path: '/api/sessions/$id', method: 'GET');
  }

  Future<BridgeSnapshot> _perform({
    required String path,
    required String method,
    Object? body,
  }) async {
    final base = Uri.parse(baseUrlString.trim());
    final uri = base.resolve(path);
    final headers = <String, String>{'Accept': 'application/json'};
    if (token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    late http.Response response;
    switch (method) {
      case 'POST':
        response = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 120));
        break;
      case 'GET':
        response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 120));
        break;
      default:
        throw UnsupportedError('Unsupported method $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(response.body.isEmpty ? 'HTTP ${response.statusCode}' : response.body);
    }

    return BridgeSnapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  void _applySnapshot(BridgeSnapshot snapshot) {
    sessionId = snapshot.session.id;
    messages = snapshot.session.messages;
    isRunning = snapshot.session.isRunning;
    lastError = snapshot.session.lastError;
    workingDirectory = snapshot.session.workingDirectory;
    connectionLabel = snapshot.session.isRunning ? 'Running' : 'Connected';
    bannerText = snapshot.server.codexAvailable
        ? 'Connected to ${snapshot.server.name}'
        : 'Bridge is reachable, but codex is unavailable on the Mac.';
    notifyListeners();
  }

  void _showPlaceholder() {
    messages = [
      BridgeChatMessage(
        id: 'placeholder',
        role: BridgeRole.assistant,
        content: 'Scan the QR code from Colony on your Mac, then connect to start remote turns.',
        createdAt: DateTime.now().toIso8601String(),
        metadata: 'Colony Bridge v1',
      ),
    ];
  }

  void _startPolling() {
    _stopPolling();
    final currentSessionId = sessionId;
    if (currentSessionId == null) return;
    _poller = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final snapshot = await _fetchSession(currentSessionId);
        _applySnapshot(snapshot);
      } catch (e) {
        connectionLabel = 'Retrying';
        lastError = '$e';
        notifyListeners();
      }
    });
  }

  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }
}

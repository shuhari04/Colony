import 'package:flutter/services.dart';

class BridgeDiscoveryChannel {
  static const _channel = MethodChannel('colony/bridge_discovery');

  static Future<void> publish({
    required String name,
    required String type,
    required int port,
    required Map<String, String> txt,
  }) async {
    await _channel.invokeMethod<void>('publish', {
      'name': name,
      'type': type,
      'port': port,
      'txt': txt,
    });
  }

  static Future<void> unpublish() async {
    await _channel.invokeMethod<void>('unpublish');
  }

  static Future<List<Map<String, dynamic>>> browse({
    required String type,
    int timeoutMs = 3000,
  }) async {
    final result = await _channel.invokeListMethod<dynamic>('browse', {
      'type': type,
      'timeoutMs': timeoutMs,
    });
    if (result == null) return const [];
    return result.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList(growable: false);
  }
}

import 'package:flutter/services.dart';

class QrScanChannel {
  static const _channel = MethodChannel('colony/qr_scanner');

  static Future<String?> scan() async {
    final result = await _channel.invokeMethod<String>('scan');
    return result;
  }
}

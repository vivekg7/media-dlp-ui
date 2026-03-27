import 'dart:io';

import 'package:flutter/services.dart';

/// Receives URLs shared from other Android apps via intent.
class ShareReceiver {
  static const _channel = MethodChannel('com.crylo.media_dl/share');

  void Function(String url)? onUrlReceived;

  ShareReceiver() {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedUrl' && call.arguments is String) {
        onUrlReceived?.call(call.arguments as String);
      }
    });
  }

  /// Returns a URL if the app was launched via a share intent.
  Future<String?> getInitialUrl() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getSharedUrl');
    } catch (_) {
      return null;
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Sends desktop notifications using platform-native commands.
/// Zero external dependencies.
class NotificationService {
  /// Show a notification with the given title and body.
  Future<void> show({
    required String title,
    required String body,
  }) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('osascript', [
          '-e',
          'display notification "$body" with title "$title"',
        ]);
      } else if (Platform.isLinux) {
        await Process.run('notify-send', [
          '--app-name=Media DL',
          title,
          body,
        ]);
      } else if (Platform.isWindows) {
        await Process.run('powershell', [
          '-Command',
          '[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null; '
              r'$n = New-Object System.Windows.Forms.NotifyIcon; '
              r'$n.Icon = [System.Drawing.SystemIcons]::Information; '
              r'$n.Visible = $true; '
              '\$n.ShowBalloonTip(5000, "$title", "$body", '
              '"Info"); '
              'Start-Sleep -Seconds 6; '
              r'$n.Dispose()',
        ]);
      }
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }

  /// Notify that a download completed.
  Future<void> downloadComplete(String name) {
    return show(
      title: 'Download complete',
      body: name,
    );
  }

  /// Notify that a download failed.
  Future<void> downloadFailed(String name, String? error) {
    return show(
      title: 'Download failed',
      body: error != null ? '$name — $error' : name,
    );
  }
}

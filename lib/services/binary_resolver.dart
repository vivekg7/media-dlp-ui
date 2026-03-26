import 'dart:io';

import 'package:flutter/foundation.dart';

/// Resolves the path to a binary (yt-dlp, gallery-dl, ffmpeg) per platform.
///
/// Search order:
/// 1. App-support directory (where we'd place bundled/updated binaries)
/// 2. System PATH
class BinaryResolver {
  BinaryResolver({required this.appSupportDir});

  final String appSupportDir;

  /// Returns the absolute path to the binary, or null if not found.
  Future<String?> resolve(String binaryName) async {
    // On Windows, executables have .exe extension
    final name = Platform.isWindows ? '$binaryName.exe' : binaryName;

    // 1. Check app-support directory
    final bundledPath = '$appSupportDir${Platform.pathSeparator}bin${Platform.pathSeparator}$name';
    final bundledFile = File(bundledPath);
    if (await bundledFile.exists()) {
      return bundledPath;
    }

    // 2. Fall back to system PATH
    return _findInPath(name);
  }

  Future<String?> _findInPath(String name) async {
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('where', [name]);
      } else {
        result = await Process.run('which', [name]);
      }
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first;
        if (path.isNotEmpty) return path;
      }
    } catch (e) {
      debugPrint('Failed to find $name in PATH: $e');
    }
    return null;
  }
}

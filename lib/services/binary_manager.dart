import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_dl/services/binary_resolver.dart';

class BinaryInfo {
  const BinaryInfo({
    required this.name,
    this.path,
    this.version,
    this.error,
  });

  final String name;
  final String? path;
  final String? version;
  final String? error;

  bool get isAvailable => path != null && version != null;
}

class BinaryManager extends ChangeNotifier {
  BinaryManager({required this.resolver});

  final BinaryResolver resolver;

  BinaryInfo _ytDlp = const BinaryInfo(name: 'yt-dlp');
  BinaryInfo get ytDlp => _ytDlp;

  bool _checking = false;
  bool get checking => _checking;

  /// Detect yt-dlp binary and fetch its version.
  Future<void> detect() async {
    _checking = true;
    notifyListeners();

    _ytDlp = await _detectBinary('yt-dlp');

    _checking = false;
    notifyListeners();
  }

  Future<BinaryInfo> _detectBinary(String name) async {
    final path = await resolver.resolve(name);
    if (path == null) {
      return BinaryInfo(
        name: name,
        error: '$name not found. Install it or place it in the app bin directory.',
      );
    }

    try {
      final result = await Process.run(path, ['--version']);
      if (result.exitCode == 0) {
        final version = (result.stdout as String).trim();
        return BinaryInfo(name: name, path: path, version: version);
      }
      return BinaryInfo(
        name: name,
        path: path,
        error: 'Failed to get version (exit code ${result.exitCode})',
      );
    } catch (e) {
      return BinaryInfo(name: name, path: path, error: 'Error running $name: $e');
    }
  }
}

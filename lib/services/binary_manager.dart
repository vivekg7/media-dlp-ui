import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_dl/services/binary_resolver.dart';
import 'package:media_dl/services/update_checker.dart';

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
  BinaryManager({required this.resolver, required this.updateChecker});

  final BinaryResolver resolver;
  final UpdateChecker updateChecker;

  BinaryInfo _ytDlp = const BinaryInfo(name: 'yt-dlp');
  BinaryInfo get ytDlp => _ytDlp;

  bool _checking = false;
  bool get checking => _checking;

  bool _updating = false;
  bool get updating => _updating;

  /// Detect yt-dlp binary and fetch its version.
  Future<void> detect() async {
    _checking = true;
    notifyListeners();

    _ytDlp = await _detectBinary('yt-dlp');

    _checking = false;
    notifyListeners();
  }

  /// Download and install the latest yt-dlp binary from GitHub Releases.
  /// Returns null on success, or an error message on failure.
  Future<String?> updateYtDlp(String assetUrl) async {
    _updating = true;
    notifyListeners();

    try {
      final name = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
      final destPath =
          '${resolver.appSupportDir}${Platform.pathSeparator}bin${Platform.pathSeparator}$name';

      final error = await updateChecker.downloadBinary(assetUrl, destPath);
      if (error != null) return error;

      // Re-detect to pick up new version
      await detect();
      return null;
    } catch (e) {
      return 'Update failed: $e';
    } finally {
      _updating = false;
      notifyListeners();
    }
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

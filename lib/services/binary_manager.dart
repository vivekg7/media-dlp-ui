import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  static const _ytdlpChannel = MethodChannel('com.crylo.media_dl/ytdlp');

  BinaryInfo _ytDlp = const BinaryInfo(name: 'yt-dlp');
  BinaryInfo get ytDlp => _ytDlp;

  BinaryInfo _ffmpeg = const BinaryInfo(name: 'ffmpeg');
  BinaryInfo get ffmpeg => _ffmpeg;

  /// youtubedl-android library version (Android only).
  String? _libraryVersion;
  String? get libraryVersion => _libraryVersion;

  bool _checking = false;
  bool get checking => _checking;

  bool _updating = false;
  bool get updating => _updating;

  /// Detect yt-dlp and ffmpeg binaries and fetch their versions.
  Future<void> detect() async {
    _checking = true;
    notifyListeners();

    if (Platform.isAndroid) {
      _ytDlp = await _detectAndroidBinary();
      _ffmpeg = await _detectAndroidFfmpeg();
      _libraryVersion = await _getAndroidLibraryVersion();
    } else {
      _ytDlp = await _detectBinary('yt-dlp');
      _ffmpeg = await _detectFfmpeg();
    }

    _checking = false;
    notifyListeners();
  }

  /// Download and install the latest yt-dlp binary.
  /// Returns null on success, or an error message on failure.
  Future<String?> updateYtDlp(String assetUrl) async {
    _updating = true;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        await _ytdlpChannel.invokeMethod('updateYtDlp');
        await detect();
        return null;
      }

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

  Future<BinaryInfo> _detectAndroidBinary() async {
    try {
      await _ytdlpChannel.invokeMethod('init');

      // Try library's version file first (set after updateYoutubeDL)
      var version = await _ytdlpChannel.invokeMethod<String>('version');

      // If null (fresh install), get version by running yt-dlp --version
      if (version == null) {
        final result = await _ytdlpChannel.invokeMethod<Map>('executeSync', {
          'arguments': ['--version'],
        });
        if (result != null && result['exitCode'] == 0) {
          version = (result['stdout'] as String?)?.trim();
        }
      }

      if (version == null || version.isEmpty) {
        return const BinaryInfo(
          name: 'yt-dlp',
          error: 'yt-dlp initialized but version unknown',
        );
      }

      return BinaryInfo(
        name: 'yt-dlp',
        path: 'android-embedded',
        version: version,
      );
    } catch (e) {
      return BinaryInfo(
        name: 'yt-dlp',
        error: 'Failed to initialize yt-dlp: $e',
      );
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

  /// Detect ffmpeg on desktop by running `ffmpeg -version`.
  Future<BinaryInfo> _detectFfmpeg() async {
    final name = 'ffmpeg';
    final path = await resolver.resolve(name);
    if (path == null) {
      return BinaryInfo(name: name, error: 'ffmpeg not found');
    }

    try {
      final result = await Process.run(path, ['-version']);
      if (result.exitCode == 0) {
        // First line: "ffmpeg version 7.0.1 Copyright ..."
        final firstLine = (result.stdout as String).split('\n').first.trim();
        final match = RegExp(r'ffmpeg version (\S+)').firstMatch(firstLine);
        final version = match?.group(1) ?? firstLine;
        return BinaryInfo(name: name, path: path, version: version);
      }
      return BinaryInfo(name: name, path: path, error: 'Exit code ${result.exitCode}');
    } catch (e) {
      return BinaryInfo(name: name, path: path, error: 'Error: $e');
    }
  }

  /// Get ffmpeg version on Android via the library.
  Future<BinaryInfo> _detectAndroidFfmpeg() async {
    try {
      final result = await _ytdlpChannel.invokeMethod<String>('ffmpegVersion');
      return BinaryInfo(
        name: 'ffmpeg',
        path: 'android-embedded',
        version: result ?? 'bundled',
      );
    } catch (_) {
      return const BinaryInfo(
        name: 'ffmpeg',
        path: 'android-embedded',
        version: 'bundled',
      );
    }
  }

  /// Get the youtubedl-android library version on Android.
  Future<String?> _getAndroidLibraryVersion() async {
    try {
      return await _ytdlpChannel.invokeMethod<String>('libraryVersion');
    } catch (_) {
      return null;
    }
  }
}

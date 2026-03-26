import 'dart:convert';
import 'dart:io';

import 'package:media_dl/core/models.dart';
import 'package:media_dl/services/binary_manager.dart';

/// Extracts media metadata by running `yt-dlp -j` on a URL.
class YtDlpInfoExtractor {
  YtDlpInfoExtractor({required this.binaryManager});

  final BinaryManager binaryManager;

  /// Fetch metadata for a URL. Returns MediaInfo or throws on failure.
  Future<MediaInfo> extract(String url) async {
    final binaryPath = binaryManager.ytDlp.path;
    if (binaryPath == null) {
      throw Exception('yt-dlp not found');
    }

    final result = await Process.run(
      binaryPath,
      ['-j', '--no-warnings', url],
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw Exception(stderr.isNotEmpty ? stderr : 'yt-dlp exited with code ${result.exitCode}');
    }

    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) {
      throw Exception('No output from yt-dlp');
    }

    final json = jsonDecode(stdout) as Map<String, dynamic>;
    return MediaInfo.fromJson(json);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:media_dl/core/models.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/services/binary_manager.dart';

/// Result of probing a URL — either a single video or a playlist.
class ExtractResult {
  const ExtractResult.single(this.mediaInfo)
      : playlistInfo = null,
        isPlaylist = false;
  const ExtractResult.playlist(this.playlistInfo)
      : mediaInfo = null,
        isPlaylist = true;

  final bool isPlaylist;
  final MediaInfo? mediaInfo;
  final PlaylistInfo? playlistInfo;
}

/// Extracts media metadata by running `yt-dlp -j` on a URL.
/// Caches results in memory so repeated probes for the same URL are instant.
class YtDlpInfoExtractor {
  YtDlpInfoExtractor({
    required this.binaryManager,
    required this.settings,
  });

  final BinaryManager binaryManager;
  final SettingsNotifier settings;
  final Map<String, ExtractResult> _cache = {};

  String get _binaryPath {
    final path = binaryManager.ytDlp.path;
    if (path == null) throw Exception('yt-dlp not found');
    return path;
  }

  List<String> get _cookieArgs {
    final path = settings.cookieFilePath;
    if (path == null) return const [];
    return ['--cookies', path];
  }

  /// Clear the in-memory cache.
  void clearCache() => _cache.clear();

  /// Probe a URL to determine if it is a playlist or single video,
  /// and return the appropriate metadata. Results are cached in memory.
  Future<ExtractResult> probe(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;

    // Try flat-playlist first — fast, returns one JSON per entry
    final result = await Process.run(
      _binaryPath,
      ['--flat-playlist', '-j', '--no-warnings', ..._cookieArgs, url],
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw Exception(
          stderr.isNotEmpty ? stderr : 'yt-dlp exited with code ${result.exitCode}');
    }

    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) {
      throw Exception('No output from yt-dlp');
    }

    final lines = stdout.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final ExtractResult extractResult;

    if (lines.length == 1) {
      // Single video — use full metadata extraction
      final json = jsonDecode(lines.first) as Map<String, dynamic>;
      if (json.containsKey('formats')) {
        extractResult = ExtractResult.single(MediaInfo.fromJson(json));
      } else {
        extractResult = ExtractResult.single(await extract(url));
      }
    } else {
      // Multiple entries — it's a playlist
      extractResult = ExtractResult.playlist(_parsePlaylistLines(lines));
    }

    _cache[url] = extractResult;
    return extractResult;
  }

  /// Fetch full metadata for a single video URL.
  Future<MediaInfo> extract(String url) async {
    final result = await Process.run(
      _binaryPath,
      ['-j', '--no-warnings', ..._cookieArgs, url],
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw Exception(
          stderr.isNotEmpty ? stderr : 'yt-dlp exited with code ${result.exitCode}');
    }

    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) {
      throw Exception('No output from yt-dlp');
    }

    final json = jsonDecode(stdout) as Map<String, dynamic>;
    return MediaInfo.fromJson(json);
  }

  /// Fetch playlist listing via --flat-playlist.
  Future<PlaylistInfo> extractPlaylist(String url) async {
    final result = await Process.run(
      _binaryPath,
      ['--flat-playlist', '-j', '--no-warnings', ..._cookieArgs, url],
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw Exception(
          stderr.isNotEmpty ? stderr : 'yt-dlp exited with code ${result.exitCode}');
    }

    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) {
      throw Exception('No output from yt-dlp');
    }

    final lines = stdout.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return _parsePlaylistLines(lines);
  }

  PlaylistInfo _parsePlaylistLines(List<String> lines) {
    String? title;
    String? uploader;
    final entries = <PlaylistEntry>[];

    for (var i = 0; i < lines.length; i++) {
      final json = jsonDecode(lines[i]) as Map<String, dynamic>;

      // Extract playlist-level metadata from the first entry
      if (i == 0) {
        title = json['playlist_title'] as String? ??
            json['playlist'] as String? ??
            'Playlist';
        uploader = json['playlist_uploader'] as String? ??
            json['playlist_channel'] as String?;
      }

      entries.add(PlaylistEntry.fromJson(json, i + 1));
    }

    return PlaylistInfo(
      title: title ?? 'Playlist',
      uploader: uploader,
      entries: entries,
    );
  }
}

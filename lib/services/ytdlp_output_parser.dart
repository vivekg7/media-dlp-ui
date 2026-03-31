import 'package:media_dl/core/models.dart';

/// Parses yt-dlp stdout/stderr lines into structured [ParsedLine] objects.
class YtDlpOutputParser {
  // [download]  45.2% of  150.23MiB at    5.23MiB/s ETA 00:12
  // [download]  45.2% of ~  150.23MiB at    5.23MiB/s ETA 00:12
  // [download] 100% of  150.23MiB in 00:03:12
  static final _progressRegex = RegExp(
    r'\[download\]\s+'
    r'(\d+(?:\.\d+)?)%\s+'
    r'of\s+~?\s*(\S+)\s+'
    r'(?:at\s+(\S+)\s+ETA\s+(\S+)|in\s+\S+)',
  );

  // [download] Destination: /path/to/file.mp4
  static final _destinationRegex = RegExp(
    r'\[download\]\s+Destination:\s+(.+)$',
  );

  // [download] Downloading item 3 of 15
  static final _playlistItemRegex = RegExp(
    r'\[download\]\s+Downloading item\s+(\d+)\s+of\s+(\d+)',
  );

  // [download] /path/to/file.mp4 has already been downloaded
  static final _alreadyDownloadedRegex = RegExp(
    r'\[download\]\s+(.+)\s+has already been downloaded',
  );

  // [Merger] Merging formats into "/path/to/file.mkv"
  static final _mergingRegex = RegExp(
    r'\[Merger\]\s+Merging formats into\s+"(.+)"',
  );

  // Fallback for other [Merger] lines
  static final _mergingFallbackRegex = RegExp(
    r'\[Merger\]',
  );

  // [ExtractAudio] Destination: /path/to/file.mp3
  // Post-processing that produces a new file destination.
  static final _postProcessDestRegex = RegExp(
    r'\[(ExtractAudio|Fixup[^\]]*)\]\s+Destination:\s+(.+)$',
  );

  // [ExtractAudio], [EmbedThumbnail], [SponsorBlock], etc.
  static final _postProcessRegex = RegExp(
    r'\[(ExtractAudio|EmbedThumbnail|EmbedSubtitle|SponsorBlock|Metadata|ThumbnailsConvertor|ModifyChapters|Fixup[^\]]*)\]',
  );

  // WARNING: ...
  static final _warningRegex = RegExp(
    r'WARNING:\s+(.+)',
  );

  // ERROR: ...
  static final _errorRegex = RegExp(
    r'ERROR:\s+(.+)',
  );

  /// Parse a single line of yt-dlp output into a [ParsedLine].
  ParsedLine parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return const ParsedLine(type: ParsedLineType.other, message: '');
    }

    // Playlist item line (must check before progress)
    final playlistMatch = _playlistItemRegex.firstMatch(trimmed);
    if (playlistMatch != null) {
      return ParsedLine(
        type: ParsedLineType.playlistItem,
        playlistItemIndex: int.parse(playlistMatch.group(1)!),
        playlistItemTotal: int.parse(playlistMatch.group(2)!),
        message: trimmed,
      );
    }

    // Progress line
    final progressMatch = _progressRegex.firstMatch(trimmed);
    if (progressMatch != null) {
      final percent = double.tryParse(progressMatch.group(1)!) ?? 0.0;
      return ParsedLine(
        type: ParsedLineType.progress,
        progress: DownloadProgress(
          percent: percent,
          totalSize: progressMatch.group(2),
          speed: progressMatch.group(3),
          eta: progressMatch.group(4),
        ),
      );
    }

    // Destination line
    final destMatch = _destinationRegex.firstMatch(trimmed);
    if (destMatch != null) {
      return ParsedLine(
        type: ParsedLineType.destination,
        destinationPath: destMatch.group(1),
        message: trimmed,
      );
    }

    // Already downloaded
    final alreadyMatch = _alreadyDownloadedRegex.firstMatch(trimmed);
    if (alreadyMatch != null) {
      return ParsedLine(
        type: ParsedLineType.alreadyDownloaded,
        destinationPath: alreadyMatch.group(1),
        message: trimmed,
      );
    }

    // Error
    final errorMatch = _errorRegex.firstMatch(trimmed);
    if (errorMatch != null) {
      return ParsedLine(
        type: ParsedLineType.error,
        message: errorMatch.group(1),
      );
    }

    // Warning
    final warningMatch = _warningRegex.firstMatch(trimmed);
    if (warningMatch != null) {
      return ParsedLine(
        type: ParsedLineType.warning,
        message: warningMatch.group(1),
      );
    }

    // Merging (with path extraction)
    final mergeMatch = _mergingRegex.firstMatch(trimmed);
    if (mergeMatch != null) {
      return ParsedLine(
        type: ParsedLineType.merging,
        destinationPath: mergeMatch.group(1),
        message: trimmed,
      );
    }
    if (_mergingFallbackRegex.hasMatch(trimmed)) {
      return ParsedLine(
        type: ParsedLineType.merging,
        message: trimmed,
      );
    }

    // Post-processing with destination (e.g. [ExtractAudio] Destination: ...)
    final ppDestMatch = _postProcessDestRegex.firstMatch(trimmed);
    if (ppDestMatch != null) {
      return ParsedLine(
        type: ParsedLineType.postProcess,
        destinationPath: ppDestMatch.group(2),
        message: trimmed,
      );
    }

    // Post-processing (generic)
    if (_postProcessRegex.hasMatch(trimmed)) {
      return ParsedLine(
        type: ParsedLineType.postProcess,
        message: trimmed,
      );
    }

    // Generic info lines (yt-dlp prefixed)
    if (trimmed.startsWith('[')) {
      return ParsedLine(
        type: ParsedLineType.info,
        message: trimmed,
      );
    }

    return ParsedLine(type: ParsedLineType.other, message: trimmed);
  }
}

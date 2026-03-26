/// Progress data extracted from a yt-dlp download line.
class DownloadProgress {
  const DownloadProgress({
    required this.percent,
    this.totalSize,
    this.speed,
    this.eta,
  });

  /// Download percentage (0.0 to 100.0).
  final double percent;

  /// Total file size string, e.g. "150.23MiB".
  final String? totalSize;

  /// Download speed string, e.g. "5.23MiB/s".
  final String? speed;

  /// Estimated time remaining string, e.g. "00:12".
  final String? eta;

  @override
  String toString() =>
      'DownloadProgress($percent%, size: $totalSize, speed: $speed, eta: $eta)';
}

/// Types of parsed output lines from yt-dlp.
enum ParsedLineType {
  progress,
  info,
  warning,
  error,
  merging,
  postProcess,
  destination,
  alreadyDownloaded,
  other,
}

/// A single parsed line from yt-dlp output.
class ParsedLine {
  const ParsedLine({
    required this.type,
    this.message,
    this.progress,
    this.destinationPath,
  });

  final ParsedLineType type;

  /// Raw message content (for info, warning, error, other lines).
  final String? message;

  /// Parsed progress data (only for [ParsedLineType.progress] lines).
  final DownloadProgress? progress;

  /// Output file path (only for [ParsedLineType.destination] lines).
  final String? destinationPath;

  @override
  String toString() => 'ParsedLine($type, $message)';
}

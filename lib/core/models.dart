/// Status of a download task.
enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  cancelled,
}

/// A single download task tracked by the DownloadManager.
class DownloadTask {
  DownloadTask({
    required this.url,
    this.formatId,
    this.status = DownloadStatus.queued,
    this.progress,
    this.fileName,
    this.outputPath,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String url;
  final String? formatId;
  final DateTime createdAt;
  DownloadStatus status;
  DownloadProgress? progress;
  String? fileName;
  String? outputPath;
  String? error;

  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.downloading;

  Map<String, dynamic> toJson() => {
        'url': url,
        'formatId': formatId,
        'status': status.name,
        'fileName': fileName,
        'outputPath': outputPath,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        url: json['url'] as String,
        formatId: json['formatId'] as String?,
        status: DownloadStatus.values.byName(json['status'] as String),
        fileName: json['fileName'] as String?,
        outputPath: json['outputPath'] as String?,
        error: json['error'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

/// A media format available for download.
class MediaFormat {
  const MediaFormat({
    required this.formatId,
    this.extension,
    this.resolution,
    this.filesize,
    this.filesizeApprox,
    this.vcodec,
    this.acodec,
    this.fps,
    this.abr,
    this.formatNote,
  });

  final String formatId;
  final String? extension;
  final String? resolution;
  final int? filesize;
  final int? filesizeApprox;
  final String? vcodec;
  final String? acodec;
  final double? fps;
  final double? abr;
  final String? formatNote;

  bool get hasVideo => vcodec != null && vcodec != 'none';
  bool get hasAudio => acodec != null && acodec != 'none';
  bool get isVideoAndAudio => hasVideo && hasAudio;
  bool get isAudioOnly => hasAudio && !hasVideo;
  bool get isVideoOnly => hasVideo && !hasAudio;

  String get sizeString {
    final bytes = filesize ?? filesizeApprox;
    if (bytes == null) return '';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '$bytes B';
  }

  factory MediaFormat.fromJson(Map<String, dynamic> json) => MediaFormat(
        formatId: json['format_id']?.toString() ?? '',
        extension: json['ext'] as String?,
        resolution: json['resolution'] as String?,
        filesize: json['filesize'] as int?,
        filesizeApprox: json['filesize_approx'] is num
            ? (json['filesize_approx'] as num).toInt()
            : null,
        vcodec: json['vcodec'] as String?,
        acodec: json['acodec'] as String?,
        fps: (json['fps'] as num?)?.toDouble(),
        abr: (json['abr'] as num?)?.toDouble(),
        formatNote: json['format_note'] as String?,
      );
}

/// Metadata about a media URL extracted via yt-dlp -j.
class MediaInfo {
  const MediaInfo({
    required this.title,
    this.uploader,
    this.duration,
    this.thumbnailUrl,
    this.formats = const [],
  });

  final String title;
  final String? uploader;
  final double? duration;
  final String? thumbnailUrl;
  final List<MediaFormat> formats;

  String get durationString {
    if (duration == null) return '';
    final total = duration!.toInt();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    final formatsList = (json['formats'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(MediaFormat.fromJson)
            .toList() ??
        [];
    return MediaInfo(
      title: json['title'] as String? ?? 'Unknown',
      uploader: json['uploader'] as String? ?? json['channel'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
      thumbnailUrl: json['thumbnail'] as String?,
      formats: formatsList,
    );
  }
}

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

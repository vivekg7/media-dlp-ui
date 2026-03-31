/// Status of a download task.
enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

// ---------------------------------------------------------------------------
// Download entries (sealed base for single + playlist)
// ---------------------------------------------------------------------------

/// Base type for items in the download list.
sealed class DownloadEntry {
  DownloadStatus get status;
  set status(DownloadStatus value);
  DateTime get createdAt;
  String? get error;
  set error(String? value);
  bool get isActive;
  Map<String, dynamic> toJson();

  static DownloadEntry fromJson(Map<String, dynamic> json) {
    if (json['type'] == 'playlist') {
      return PlaylistDownloadTask.fromJson(json);
    }
    return DownloadTask.fromJson(json);
  }
}

/// A single download task.
class DownloadTask extends DownloadEntry {
  DownloadTask({
    required this.url,
    this.formatId,
    this.isAudioOnly = false,
    this.status = DownloadStatus.queued,
    this.progress,
    this.fileName,
    this.outputPath,
    this.fileSize,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String url;
  final String? formatId;
  final bool isAudioOnly;
  @override
  final DateTime createdAt;
  @override
  DownloadStatus status;
  DownloadProgress? progress;
  String? fileName;
  String? outputPath;
  /// Final file size string, e.g. "150.23MiB".
  String? fileSize;
  @override
  String? error;

  /// All file paths seen during download (intermediate streams, temp files).
  /// Not serialized — only populated during the active download session.
  final Set<String> tempPaths = {};

  @override
  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.downloading;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'single',
        'url': url,
        'formatId': formatId,
        'status': status.name,
        'fileName': fileName,
        'outputPath': outputPath,
        'fileSize': fileSize,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        url: json['url'] as String,
        formatId: json['formatId'] as String?,
        status: DownloadStatus.values.byName(json['status'] as String),
        fileName: json['fileName'] as String?,
        outputPath: json['outputPath'] as String?,
        fileSize: json['fileSize'] as String?,
        error: json['error'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

// ---------------------------------------------------------------------------
// Playlist models
// ---------------------------------------------------------------------------

/// A single entry in a playlist listing (from --flat-playlist).
class PlaylistEntry {
  const PlaylistEntry({
    required this.id,
    required this.title,
    required this.url,
    this.duration,
    this.thumbnailUrl,
    required this.index,
  });

  final String id;
  final String title;
  final String url;
  final double? duration;
  final String? thumbnailUrl;

  /// 1-based index within the playlist.
  final int index;

  String get durationString {
    if (duration == null) return '';
    final total = duration!.toInt();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  factory PlaylistEntry.fromJson(Map<String, dynamic> json, int index) {
    final id = json['id']?.toString() ?? '';
    final url = json['url'] as String? ?? json['webpage_url'] as String? ?? '';
    return PlaylistEntry(
      id: id,
      title: json['title'] as String? ?? 'Item $index',
      url: url,
      duration: (json['duration'] as num?)?.toDouble(),
      thumbnailUrl: json['thumbnail'] as String?,
      index: index,
    );
  }
}

/// Metadata about a playlist extracted via yt-dlp --flat-playlist.
class PlaylistInfo {
  const PlaylistInfo({
    required this.title,
    this.uploader,
    required this.entries,
  });

  final String title;
  final String? uploader;
  final List<PlaylistEntry> entries;
  int get itemCount => entries.length;
}

/// A playlist download task containing child tasks for each selected item.
class PlaylistDownloadTask extends DownloadEntry {
  PlaylistDownloadTask({
    required this.playlistUrl,
    required this.playlistTitle,
    this.uploader,
    required this.items,
    this.formatId,
    this.selectedIndices,
    this.status = DownloadStatus.queued,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String playlistUrl;
  final String playlistTitle;
  final String? uploader;
  final String? formatId;

  /// 1-based playlist indices that were selected.
  final List<int>? selectedIndices;

  final List<DownloadTask> items;

  @override
  final DateTime createdAt;
  @override
  DownloadStatus status;
  @override
  String? error;

  /// Index of the item currently being downloaded (0-based into [items]).
  int currentItemIndex = 0;

  int get completedCount =>
      items.where((t) => t.status == DownloadStatus.completed).length;
  int get totalCount => items.length;

  double get overallPercent {
    if (items.isEmpty) return 0;
    double sum = 0;
    for (final item in items) {
      if (item.status == DownloadStatus.completed) {
        sum += 100;
      } else if (item.progress != null) {
        sum += item.progress!.percent;
      }
    }
    return sum / items.length;
  }

  @override
  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.downloading;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'playlist',
        'playlistUrl': playlistUrl,
        'playlistTitle': playlistTitle,
        'uploader': uploader,
        'formatId': formatId,
        'selectedIndices': selectedIndices,
        'status': status.name,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((t) => t.toJson()).toList(),
      };

  factory PlaylistDownloadTask.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(DownloadTask.fromJson)
            .toList() ??
        [];
    return PlaylistDownloadTask(
      playlistUrl: json['playlistUrl'] as String,
      playlistTitle: json['playlistTitle'] as String,
      uploader: json['uploader'] as String?,
      formatId: json['formatId'] as String?,
      selectedIndices: (json['selectedIndices'] as List?)?.cast<int>(),
      status: DownloadStatus.values.byName(json['status'] as String),
      error: json['error'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      items: itemsList,
    );
  }
}

// ---------------------------------------------------------------------------
// Media format & info (for single-video metadata extraction)
// ---------------------------------------------------------------------------

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
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
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

// ---------------------------------------------------------------------------
// Parser output types
// ---------------------------------------------------------------------------

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
  playlistItem,
  tempFile,
  other,
}

/// A single parsed line from yt-dlp output.
class ParsedLine {
  const ParsedLine({
    required this.type,
    this.message,
    this.progress,
    this.destinationPath,
    this.playlistItemIndex,
    this.playlistItemTotal,
  });

  final ParsedLineType type;

  /// Raw message content (for info, warning, error, other lines).
  final String? message;

  /// Parsed progress data (only for [ParsedLineType.progress] lines).
  final DownloadProgress? progress;

  /// Output file path (only for [ParsedLineType.destination] lines).
  final String? destinationPath;

  /// 1-based current item number (only for [ParsedLineType.playlistItem]).
  final int? playlistItemIndex;

  /// Total item count (only for [ParsedLineType.playlistItem]).
  final int? playlistItemTotal;

  @override
  String toString() => 'ParsedLine($type, $message)';
}

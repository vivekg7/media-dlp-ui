import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/notification_service.dart';
import 'package:media_dl/services/process_runner.dart';
import 'package:media_dl/services/ytdlp_output_parser.dart';

/// Manages downloads with queuing, concurrency control, and persistence.
/// Supports both single-video and playlist downloads.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.binaryManager,
    required this.settings,
    required this.historyPath,
    ProcessRunner? processRunner,
    NotificationService? notificationService,
    this.maxConcurrent = 1,
  })  : _processRunner = processRunner ?? ProcessRunner(),
        _notifications = notificationService ?? NotificationService();

  final BinaryManager binaryManager;
  final SettingsNotifier settings;
  final String historyPath;
  final int maxConcurrent;
  final ProcessRunner _processRunner;
  final NotificationService _notifications;
  final YtDlpOutputParser _parser = YtDlpOutputParser();

  final List<DownloadEntry> _entries = [];
  List<DownloadEntry> get entries => List.unmodifiable(_entries);

  final Map<DownloadEntry, RunningProcess> _activeProcesses = {};
  int get _activeCount =>
      _entries.where((e) => e.status == DownloadStatus.downloading).length;

  bool get isReady => binaryManager.ytDlp.isAvailable;

  // ---------------------------------------------------------------------------
  // History persistence
  // ---------------------------------------------------------------------------

  Future<void> loadHistory() async {
    final file = File(historyPath);
    if (!await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      final list = (json as List).cast<Map<String, dynamic>>();
      for (final item in list) {
        final entry = DownloadEntry.fromJson(item);
        if (entry.status == DownloadStatus.downloading ||
            entry.status == DownloadStatus.queued) {
          entry.status = DownloadStatus.paused;
          entry.error = null;
        }
        _entries.add(entry);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final json = _entries.map((e) => e.toJson()).toList();
      await File(historyPath).writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Failed to save history: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Single download
  // ---------------------------------------------------------------------------

  Future<String?> download(String url, {String? formatId, bool isAudioOnly = false}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (!isReady) return 'yt-dlp not found. Check Settings → Tools.';

    final task = DownloadTask(url: trimmed, formatId: formatId, isAudioOnly: isAudioOnly);
    _entries.insert(0, task);
    notifyListeners();
    _saveHistory();
    _processQueue();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Playlist download
  // ---------------------------------------------------------------------------

  Future<String?> downloadPlaylist({
    required String url,
    required String playlistTitle,
    String? uploader,
    required List<PlaylistEntry> selectedEntries,
    String? formatId,
  }) async {
    if (!isReady) return 'yt-dlp not found. Check Settings → Tools.';
    if (selectedEntries.isEmpty) return 'No items selected.';

    final items = selectedEntries.map((e) => DownloadTask(
          url: e.url,
          fileName: e.title,
        )).toList();

    final indices = selectedEntries.map((e) => e.index).toList();

    final task = PlaylistDownloadTask(
      playlistUrl: url,
      playlistTitle: playlistTitle,
      uploader: uploader,
      items: items,
      formatId: formatId,
      selectedIndices: indices,
    );

    _entries.insert(0, task);
    notifyListeners();
    _saveHistory();
    _processQueue();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Queue control
  // ---------------------------------------------------------------------------

  void retry(DownloadEntry entry) {
    if (entry.status == DownloadStatus.failed ||
        entry.status == DownloadStatus.cancelled) {
      entry.status = DownloadStatus.queued;
      entry.error = null;
      if (entry case DownloadTask task) {
        task.progress = null;
        task.fileName = null;
        task.outputPath = null;
      } else if (entry case PlaylistDownloadTask playlist) {
        playlist.currentItemIndex = 0;
        for (final item in playlist.items) {
          if (item.status != DownloadStatus.completed) {
            item.status = DownloadStatus.queued;
            item.progress = null;
            item.error = null;
          }
        }
      }
      notifyListeners();
      _processQueue();
    }
  }

  void pause(DownloadEntry entry) {
    if (entry.status == DownloadStatus.downloading) {
      _activeProcesses[entry]?.kill();
      _activeProcesses.remove(entry);
      entry.status = DownloadStatus.paused;
      if (entry case PlaylistDownloadTask playlist) {
        for (final item in playlist.items) {
          if (item.status == DownloadStatus.downloading) {
            item.status = DownloadStatus.paused;
          }
        }
      }
      notifyListeners();
      _saveHistory();
      _processQueue();
    }
  }

  void resume(DownloadEntry entry) {
    if (entry.status == DownloadStatus.paused) {
      entry.status = DownloadStatus.queued;
      if (entry case PlaylistDownloadTask playlist) {
        for (final item in playlist.items) {
          if (item.status == DownloadStatus.paused) {
            item.status = DownloadStatus.queued;
          }
        }
      }
      notifyListeners();
      _saveHistory();
      _processQueue();
    }
  }

  void cancel(DownloadEntry entry) {
    if (entry.status == DownloadStatus.downloading) {
      _activeProcesses[entry]?.kill();
      _activeProcesses.remove(entry);
      entry.status = DownloadStatus.cancelled;
      // Mark in-progress child items as cancelled too
      if (entry case PlaylistDownloadTask playlist) {
        for (final item in playlist.items) {
          if (item.isActive) item.status = DownloadStatus.cancelled;
        }
      }
      notifyListeners();
      _saveHistory();
      _processQueue();
    } else if (entry.status == DownloadStatus.queued ||
        entry.status == DownloadStatus.paused) {
      entry.status = DownloadStatus.cancelled;
      if (entry case PlaylistDownloadTask playlist) {
        for (final item in playlist.items) {
          if (item.status == DownloadStatus.queued ||
              item.status == DownloadStatus.paused) {
            item.status = DownloadStatus.cancelled;
          }
        }
      }
      notifyListeners();
      _saveHistory();
    }
  }

  /// Remove a download entry. If [deleteFile] is true, also delete the
  /// file(s) from disk. Incomplete downloads always have their partial
  /// files cleaned up.
  void remove(DownloadEntry entry, {bool deleteFile = false}) {
    if (entry.isActive) return;
    if (entry.status != DownloadStatus.completed) {
      // Incomplete: clean up all files (output, intermediate streams, .part, .ytdl)
      _deleteFiles(entry);
    } else if (deleteFile) {
      // Completed + user chose to delete: only need the final output
      // (yt-dlp cleans intermediates on success)
      _deleteOutputFiles(entry);
    }
    _entries.remove(entry);
    notifyListeners();
    _saveHistory();
  }

  void clearCompleted() {
    _entries.removeWhere((e) => e.status == DownloadStatus.completed);
    notifyListeners();
    _saveHistory();
  }

  void _deleteOutputFiles(DownloadEntry entry) {
    if (entry is DownloadTask) {
      _tryDeleteFile(entry.outputPath);
    } else if (entry is PlaylistDownloadTask) {
      for (final item in entry.items) {
        _tryDeleteFile(item.outputPath);
      }
    }
  }

  void _deleteFiles(DownloadEntry entry) {
    final isIncomplete = entry.status != DownloadStatus.completed;
    if (entry is DownloadTask) {
      _cleanupTask(entry, deleteOutput: true, deleteTemp: isIncomplete);
    } else if (entry is PlaylistDownloadTask) {
      for (final item in entry.items) {
        _cleanupTask(item, deleteOutput: true, deleteTemp: isIncomplete);
      }
    }
  }

  /// Clean up files for a single task.
  /// [deleteOutput] removes the final output file.
  /// [deleteTemp] removes intermediate stream files and temp files
  /// (streams, thumbnails, .part/.ytdl variants).
  static void _cleanupTask(
    DownloadTask task, {
    required bool deleteOutput,
    required bool deleteTemp,
  }) {
    if (deleteTemp) {
      for (final path in task.tempPaths) {
        if (path == task.outputPath) continue;
        _tryDeleteFile(path);
      }
    }
    if (deleteOutput) {
      _tryDeleteFile(task.outputPath);
    }
  }

  /// Delete a file and its yt-dlp temp variants (.part, .ytdl).
  static void _tryDeleteFile(String? path) {
    if (path == null) return;
    for (final suffix in ['', '.part', '.ytdl']) {
      try {
        final file = File('$path$suffix');
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Queue processing
  // ---------------------------------------------------------------------------

  void _processQueue() {
    final binaryPath = binaryManager.ytDlp.path;
    if (binaryPath == null) return;

    while (_activeCount < maxConcurrent) {
      final next = _entries.cast<DownloadEntry?>().firstWhere(
            (e) => e!.status == DownloadStatus.queued,
            orElse: () => null,
          );
      if (next == null) break;

      switch (next) {
        case DownloadTask task:
          _runSingleDownload(task, binaryPath);
        case PlaylistDownloadTask playlist:
          _runPlaylistDownload(playlist, binaryPath);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Single download execution
  // ---------------------------------------------------------------------------

  Future<void> _runSingleDownload(
      DownloadTask task, String binaryPath) async {
    task.status = DownloadStatus.downloading;
    notifyListeners();

    await _ensureOutputDir();

    try {
      final outDir = settings.outputDir;
      final template = settings.filenameTemplate;
      // When an audio-only format is selected and thumbnail embedding is on,
      // extract audio to a compatible container (mp3/opus/m4a etc).
      final needsAudioExtract = task.isAudioOnly &&
          settings.embedThumbnail &&
          !settings.extractAudio;
      final args = [
        '--newline',
        '-o', '$outDir/$template',
        ..._settingsArgs,
        if (needsAudioExtract) ...['-x', '--audio-format', settings.audioFormat],
        if (task.formatId != null) ...['-f', task.formatId!],
        task.url,
      ];
      final process = await _processRunner.start(binaryPath, args);
      _activeProcesses[task] = process;

      final stdoutSub = process.stdout.listen((line) {
        _handleSingleLine(task, line);
      });
      final stderrSub = process.stderr.listen((line) {
        _handleSingleLine(task, line);
      });

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      _activeProcesses.remove(task);

      if (task.status == DownloadStatus.cancelled ||
          task.status == DownloadStatus.paused) {
        return;
      }

      if (exitCode == 0) {
        task.status = DownloadStatus.completed;
        task.fileSize = await _readFileSize(task.outputPath)
            ?? task.progress?.totalSize;
        task.progress = const DownloadProgress(percent: 100.0);
        _notifications.downloadComplete(task.fileName ?? task.url);
      } else {
        task.status = DownloadStatus.failed;
        task.error ??= 'yt-dlp exited with code $exitCode';
        _notifications.downloadFailed(task.fileName ?? task.url, task.error);
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      _notifications.downloadFailed(task.fileName ?? task.url, task.error);
    }

    notifyListeners();
    _saveHistory();
    _processQueue();
  }

  void _handleSingleLine(DownloadTask task, String line) {
    final parsed = _parser.parseLine(line);
    switch (parsed.type) {
      case ParsedLineType.progress:
        task.progress = parsed.progress;
        notifyListeners();
      case ParsedLineType.destination:
        if (parsed.destinationPath != null) {
          task.tempPaths.add(parsed.destinationPath!);
          task.outputPath = parsed.destinationPath;
          task.fileName =
              parsed.destinationPath!.split(Platform.pathSeparator).last;
        }
        notifyListeners();
      case ParsedLineType.alreadyDownloaded:
        task.outputPath = parsed.destinationPath;
        if (parsed.destinationPath != null) {
          task.fileName =
              parsed.destinationPath!.split(Platform.pathSeparator).last;
        }
        notifyListeners();
      case ParsedLineType.merging:
      case ParsedLineType.postProcess:
        if (parsed.destinationPath != null) {
          task.tempPaths.add(parsed.destinationPath!);
          task.outputPath = parsed.destinationPath;
          task.fileName =
              parsed.destinationPath!.split(Platform.pathSeparator).last;
          notifyListeners();
        }
      case ParsedLineType.tempFile:
        if (parsed.destinationPath != null) {
          task.tempPaths.add(parsed.destinationPath!);
        }
      case ParsedLineType.error:
        task.error = parsed.message;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Playlist download execution
  // ---------------------------------------------------------------------------

  Future<void> _runPlaylistDownload(
      PlaylistDownloadTask playlist, String binaryPath) async {
    playlist.status = DownloadStatus.downloading;
    notifyListeners();

    await _ensureOutputDir();

    try {
      final outDir = settings.outputDir;
      final template = settings.playlistTemplate;
      final args = [
        '--newline',
        '-o',
        '$outDir/$template',
        ..._settingsArgs,
        if (playlist.selectedIndices != null)
          ...['--playlist-items', playlist.selectedIndices!.join(',')],
        if (playlist.formatId != null) ...['-f', playlist.formatId!],
        playlist.playlistUrl,
      ];

      final process = await _processRunner.start(binaryPath, args);
      _activeProcesses[playlist] = process;

      // Track which child item we're on (0-based into playlist.items)
      playlist.currentItemIndex = 0;
      if (playlist.items.isNotEmpty) {
        playlist.items[0].status = DownloadStatus.downloading;
      }

      final stdoutSub = process.stdout.listen((line) {
        _handlePlaylistLine(playlist, line);
      });
      final stderrSub = process.stderr.listen((line) {
        _handlePlaylistLine(playlist, line);
      });

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      _activeProcesses.remove(playlist);

      if (playlist.status == DownloadStatus.cancelled ||
          playlist.status == DownloadStatus.paused) {
        return;
      }

      if (exitCode == 0) {
        // Mark any remaining items as completed and read actual file sizes
        for (final item in playlist.items) {
          if (item.status == DownloadStatus.downloading) {
            item.status = DownloadStatus.completed;
            item.progress = const DownloadProgress(percent: 100.0);
          }
          if (item.status == DownloadStatus.completed) {
            item.fileSize = await _readFileSize(item.outputPath)
                ?? item.progress?.totalSize;
          }
        }
        playlist.status = DownloadStatus.completed;
        _notifications.downloadComplete(
            '${playlist.playlistTitle} (${playlist.completedCount} items)');
      } else {
        // Mark unfinished items as failed
        for (final item in playlist.items) {
          if (item.isActive) {
            item.status = DownloadStatus.failed;
            item.error ??= 'yt-dlp exited with code $exitCode';
          }
        }
        playlist.status = playlist.items.any(
                (i) => i.status == DownloadStatus.completed)
            ? DownloadStatus.completed
            : DownloadStatus.failed;
        playlist.error ??= 'yt-dlp exited with code $exitCode';
        _notifications.downloadFailed(
            playlist.playlistTitle, playlist.error);
      }
    } catch (e) {
      playlist.status = DownloadStatus.failed;
      playlist.error = e.toString();
      _notifications.downloadFailed(playlist.playlistTitle, playlist.error);
    }

    notifyListeners();
    _saveHistory();
    _processQueue();
  }

  void _handlePlaylistLine(PlaylistDownloadTask playlist, String line) {
    final parsed = _parser.parseLine(line);
    final currentItem = playlist.currentItemIndex < playlist.items.length
        ? playlist.items[playlist.currentItemIndex]
        : null;

    switch (parsed.type) {
      case ParsedLineType.playlistItem:
        // Advance to next item. "Downloading item X of Y" means item X
        // (1-based sequential number). Map to 0-based index.
        final newIndex = (parsed.playlistItemIndex ?? 1) - 1;

        // Mark previous item as completed if it was downloading
        if (playlist.currentItemIndex < playlist.items.length) {
          final prev = playlist.items[playlist.currentItemIndex];
          if (prev.status == DownloadStatus.downloading) {
            prev.status = DownloadStatus.completed;
            prev.progress = const DownloadProgress(percent: 100.0);
          }
        }

        playlist.currentItemIndex = newIndex;
        if (newIndex < playlist.items.length) {
          playlist.items[newIndex].status = DownloadStatus.downloading;
        }
        notifyListeners();

      case ParsedLineType.progress:
        if (currentItem != null) {
          currentItem.progress = parsed.progress;
          notifyListeners();
        }

      case ParsedLineType.destination:
        if (currentItem != null && parsed.destinationPath != null) {
          currentItem.tempPaths.add(parsed.destinationPath!);
          currentItem.outputPath = parsed.destinationPath;
          currentItem.fileName =
              parsed.destinationPath!.split(Platform.pathSeparator).last;
          notifyListeners();
        }

      case ParsedLineType.alreadyDownloaded:
        if (currentItem != null) {
          currentItem.outputPath = parsed.destinationPath;
          if (parsed.destinationPath != null) {
            currentItem.fileName =
                parsed.destinationPath!.split(Platform.pathSeparator).last;
          }
          currentItem.status = DownloadStatus.completed;
          currentItem.progress = const DownloadProgress(percent: 100.0);
          notifyListeners();
        }

      case ParsedLineType.merging:
      case ParsedLineType.postProcess:
        if (currentItem != null && parsed.destinationPath != null) {
          currentItem.tempPaths.add(parsed.destinationPath!);
          currentItem.outputPath = parsed.destinationPath;
          currentItem.fileName =
              parsed.destinationPath!.split(Platform.pathSeparator).last;
          notifyListeners();
        }

      case ParsedLineType.tempFile:
        if (currentItem != null && parsed.destinationPath != null) {
          currentItem.tempPaths.add(parsed.destinationPath!);
        }

      case ParsedLineType.error:
        if (currentItem != null) {
          currentItem.error = parsed.message;
          currentItem.status = DownloadStatus.failed;
          notifyListeners();
        }

      default:
        break;
    }
  }

  /// Returns common args from settings (post-processing, cookies).
  List<String> get _settingsArgs {
    return [
      if (settings.embedThumbnail) '--embed-thumbnail',
      if (settings.embedMetadata) '--embed-metadata',
      if (settings.embedSubs) ...[
        '--embed-subs',
        '--sub-langs', settings.subLangs,
        '--postprocessor-args', 'ffmpeg:-disposition:s:0 default',
      ],
      if (settings.sponsorBlock) '--sponsorblock-remove',
      if (settings.extractAudio) ...[
        '-x',
        '--audio-format', settings.audioFormat,
      ],
      if (!settings.extractAudio && settings.videoFormat != null) ...[
        '--remux-video', settings.videoFormat!,
      ],
      if (settings.cookieFilePath != null) ...[
        '--cookies', settings.cookieFilePath!,
      ],
      if (settings.proxyUrl != null) ...[
        '--proxy', settings.proxyUrl!,
      ],
      if (settings.rateLimit != null) ...[
        '--limit-rate', settings.rateLimit!,
      ],
      if (settings.sourceAddress != null) ...[
        '--source-address', settings.sourceAddress!,
      ],
    ];
  }

  /// Read the actual file size from disk and return a human-readable string.
  Future<String?> _readFileSize(String? path) async {
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.length();
      return _formatBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  }

  Future<void> _ensureOutputDir() async {
    final dir = Directory(settings.outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}

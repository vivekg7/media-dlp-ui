import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/services/binary_manager.dart';
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
    this.maxConcurrent = 1,
  }) : _processRunner = processRunner ?? ProcessRunner();

  final BinaryManager binaryManager;
  final SettingsNotifier settings;
  final String historyPath;
  final int maxConcurrent;
  final ProcessRunner _processRunner;
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
          entry.status = DownloadStatus.failed;
          entry.error = 'Interrupted by app restart';
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

  Future<String?> download(String url, {String? formatId}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (!isReady) return 'yt-dlp not found. Check Settings → Tools.';

    final task = DownloadTask(url: trimmed, formatId: formatId);
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
    } else if (entry.status == DownloadStatus.queued) {
      entry.status = DownloadStatus.cancelled;
      notifyListeners();
      _saveHistory();
    }
  }

  void remove(DownloadEntry entry) {
    if (!entry.isActive) {
      _entries.remove(entry);
      notifyListeners();
      _saveHistory();
    }
  }

  void clearCompleted() {
    _entries.removeWhere((e) => e.status == DownloadStatus.completed);
    notifyListeners();
    _saveHistory();
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
      final args = [
        '--newline',
        '-o', '$outDir/$template',
        '--embed-thumbnail',
        '--embed-metadata',
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

      if (task.status == DownloadStatus.cancelled) return;

      if (exitCode == 0) {
        task.status = DownloadStatus.completed;
        task.progress = const DownloadProgress(percent: 100.0);
      } else {
        task.status = DownloadStatus.failed;
        task.error ??= 'yt-dlp exited with code $exitCode';
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
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
        task.outputPath = parsed.destinationPath;
        if (parsed.destinationPath != null) {
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
        '--embed-thumbnail',
        '--embed-metadata',
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

      if (playlist.status == DownloadStatus.cancelled) return;

      if (exitCode == 0) {
        // Mark any remaining items as completed
        for (final item in playlist.items) {
          if (item.status == DownloadStatus.downloading) {
            item.status = DownloadStatus.completed;
            item.progress = const DownloadProgress(percent: 100.0);
          }
        }
        playlist.status = DownloadStatus.completed;
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
      }
    } catch (e) {
      playlist.status = DownloadStatus.failed;
      playlist.error = e.toString();
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
        if (currentItem != null) {
          currentItem.outputPath = parsed.destinationPath;
          if (parsed.destinationPath != null) {
            currentItem.fileName =
                parsed.destinationPath!.split(Platform.pathSeparator).last;
          }
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

  Future<void> _ensureOutputDir() async {
    final dir = Directory(settings.outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/process_runner.dart';
import 'package:media_dl/services/ytdlp_output_parser.dart';

/// Manages downloads with queuing, concurrency control, and persistence.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.binaryManager,
    required this.outputDir,
    required this.historyPath,
    ProcessRunner? processRunner,
    this.maxConcurrent = 1,
  }) : _processRunner = processRunner ?? ProcessRunner();

  final BinaryManager binaryManager;
  final String outputDir;
  final String historyPath;
  final int maxConcurrent;
  final ProcessRunner _processRunner;
  final YtDlpOutputParser _parser = YtDlpOutputParser();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  final Map<DownloadTask, RunningProcess> _activeProcesses = {};
  int get _activeCount =>
      _tasks.where((t) => t.status == DownloadStatus.downloading).length;

  /// Whether yt-dlp is available for downloads.
  bool get isReady => binaryManager.ytDlp.isAvailable;

  /// Load download history from disk.
  Future<void> loadHistory() async {
    final file = File(historyPath);
    if (!await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      final list = (json as List).cast<Map<String, dynamic>>();
      for (final item in list) {
        final task = DownloadTask.fromJson(item);
        // Restore only finished tasks; in-progress ones become failed
        if (task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.queued) {
          task.status = DownloadStatus.failed;
          task.error = 'Interrupted by app restart';
        }
        _tasks.add(task);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load history: $e');
    }
  }

  /// Persist download history to disk.
  Future<void> _saveHistory() async {
    try {
      final json = _tasks.map((t) => t.toJson()).toList();
      await File(historyPath).writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Failed to save history: $e');
    }
  }

  /// Add a URL to the queue. Starts immediately if slots are available.
  /// Optionally specify a [formatId] to download a specific format.
  /// Returns null on success, or an error string if the download can't start.
  Future<String?> download(String url, {String? formatId}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (!isReady) {
      return 'yt-dlp not found. Check Settings → Tools.';
    }

    final task = DownloadTask(url: trimmed, formatId: formatId);
    _tasks.insert(0, task);
    notifyListeners();
    _saveHistory();

    _processQueue();
    return null;
  }

  /// Retry a failed or cancelled download.
  void retry(DownloadTask task) {
    if (task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.cancelled) {
      task.status = DownloadStatus.queued;
      task.error = null;
      task.progress = null;
      notifyListeners();
      _processQueue();
    }
  }

  /// Cancel an active or queued download.
  void cancel(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      _activeProcesses[task]?.kill();
      _activeProcesses.remove(task);
      task.status = DownloadStatus.cancelled;
      notifyListeners();
      _saveHistory();
      _processQueue();
    } else if (task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.cancelled;
      notifyListeners();
      _saveHistory();
    }
  }

  /// Remove a finished task from the list.
  void remove(DownloadTask task) {
    if (!task.isActive) {
      _tasks.remove(task);
      notifyListeners();
      _saveHistory();
    }
  }

  /// Clear all completed downloads from the list.
  void clearCompleted() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    notifyListeners();
    _saveHistory();
  }

  /// Start queued downloads up to the concurrency limit.
  void _processQueue() {
    final binaryPath = binaryManager.ytDlp.path;
    if (binaryPath == null) return;

    while (_activeCount < maxConcurrent) {
      final next = _tasks.cast<DownloadTask?>().firstWhere(
            (t) => t!.status == DownloadStatus.queued,
            orElse: () => null,
          );
      if (next == null) break;
      _runDownload(next, binaryPath);
    }
  }

  Future<void> _runDownload(DownloadTask task, String binaryPath) async {
    task.status = DownloadStatus.downloading;
    notifyListeners();

    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    try {
      final args = [
        '--newline',
        '-o', '$outputDir/%(title)s.%(ext)s',
        '--embed-thumbnail',
        '--embed-metadata',
        if (task.formatId != null) ...['-f', task.formatId!],
        task.url,
      ];
      final process = await _processRunner.start(binaryPath, args);
      _activeProcesses[task] = process;

      final stdoutSub = process.stdout.listen((line) {
        _handleLine(task, line);
      });
      final stderrSub = process.stderr.listen((line) {
        _handleLine(task, line);
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

  void _handleLine(DownloadTask task, String line) {
    final parsed = _parser.parseLine(line);

    switch (parsed.type) {
      case ParsedLineType.progress:
        task.progress = parsed.progress;
        notifyListeners();
      case ParsedLineType.destination:
        task.outputPath = parsed.destinationPath;
        final path = parsed.destinationPath;
        if (path != null) {
          task.fileName = path.split(Platform.pathSeparator).last;
        }
        notifyListeners();
      case ParsedLineType.alreadyDownloaded:
        task.outputPath = parsed.destinationPath;
        final path = parsed.destinationPath;
        if (path != null) {
          task.fileName = path.split(Platform.pathSeparator).last;
        }
        notifyListeners();
      case ParsedLineType.error:
        task.error = parsed.message;
      default:
        break;
    }
  }
}

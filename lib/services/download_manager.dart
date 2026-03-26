import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/process_runner.dart';
import 'package:media_dl/services/ytdlp_output_parser.dart';

/// Manages downloads by coordinating ProcessRunner, parser, and task state.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.binaryManager,
    required this.outputDir,
    ProcessRunner? processRunner,
  }) : _processRunner = processRunner ?? ProcessRunner();

  final BinaryManager binaryManager;
  final String outputDir;
  final ProcessRunner _processRunner;
  final YtDlpOutputParser _parser = YtDlpOutputParser();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  RunningProcess? _activeProcess;

  /// Whether yt-dlp is available for downloads.
  bool get isReady => binaryManager.ytDlp.isAvailable;

  /// Add a URL and start downloading immediately.
  /// Returns null on success, or an error string if the download can't start.
  Future<String?> download(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final binaryPath = binaryManager.ytDlp.path;
    if (binaryPath == null) {
      return 'yt-dlp not found. Check Settings → Tools.';
    }

    final task = DownloadTask(url: trimmed);
    _tasks.insert(0, task);
    notifyListeners();

    await _runDownload(task, binaryPath);
    return null;
  }

  /// Cancel the currently active download.
  void cancel(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      _activeProcess?.kill();
      task.status = DownloadStatus.cancelled;
      notifyListeners();
    }
  }

  /// Remove a completed/failed/cancelled task from the list.
  void remove(DownloadTask task) {
    if (!task.isActive) {
      _tasks.remove(task);
      notifyListeners();
    }
  }

  Future<void> _runDownload(DownloadTask task, String binaryPath) async {
    task.status = DownloadStatus.downloading;
    notifyListeners();

    // Ensure output directory exists
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    try {
      final process = await _processRunner.start(
        binaryPath,
        [
          '--newline', // Force progress on new lines (not carriage return)
          '-o', '$outputDir/%(title)s.%(ext)s',
          task.url,
        ],
      );
      _activeProcess = process;

      // Listen to stdout for progress
      final stdoutSub = process.stdout.listen((line) {
        _handleLine(task, line);
      });

      // Listen to stderr (yt-dlp writes some output here)
      final stderrSub = process.stderr.listen((line) {
        _handleLine(task, line);
      });

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      _activeProcess = null;

      if (task.status == DownloadStatus.cancelled) {
        // Already marked cancelled by cancel()
        return;
      }

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
  }

  void _handleLine(DownloadTask task, String line) {
    final parsed = _parser.parseLine(line);

    switch (parsed.type) {
      case ParsedLineType.progress:
        task.progress = parsed.progress;
        notifyListeners();
      case ParsedLineType.destination:
        task.outputPath = parsed.destinationPath;
        // Extract filename from path
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
      case ParsedLineType.merging:
        // Keep showing progress during merge
        break;
      default:
        break;
    }
  }
}

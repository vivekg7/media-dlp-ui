import 'package:flutter/material.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/features/download/format_sheet.dart';
import 'package:media_dl/features/download/playlist_sheet.dart';
import 'package:media_dl/features/settings/settings_page.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/download_manager.dart';
import 'package:media_dl/services/share_receiver.dart';
import 'package:media_dl/services/update_checker.dart';
import 'package:media_dl/services/ytdlp_info_extractor.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({
    super.key,
    required this.downloadManager,
    required this.infoExtractor,
    required this.settings,
    required this.binaryManager,
    required this.updateChecker,
    this.shareReceiver,
  });

  final DownloadManager downloadManager;
  final YtDlpInfoExtractor infoExtractor;
  final SettingsNotifier settings;
  final BinaryManager binaryManager;
  final UpdateChecker updateChecker;
  final ShareReceiver? shareReceiver;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _urlController = TextEditingController();
  bool _fetching = false;

  DownloadManager get _dm => widget.downloadManager;

  @override
  void initState() {
    super.initState();
    _initShareReceiver();
  }

  Future<void> _initShareReceiver() async {
    final receiver = widget.shareReceiver;
    if (receiver == null) return;

    receiver.onUrlReceived = _handleSharedUrl;

    final initialUrl = await receiver.getInitialUrl();
    if (initialUrl != null && mounted) {
      _handleSharedUrl(initialUrl);
    }
  }

  void _handleSharedUrl(String url) {
    _urlController.text = url.trim();
    _fetchAndChooseFormat();
  }

  /// Fetch info, auto-detect playlist vs single, show appropriate sheet.
  Future<void> _fetchAndChooseFormat() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (!_dm.isReady) {
      _showError('yt-dlp not found. Check Settings → Tools.');
      return;
    }

    setState(() => _fetching = true);
    try {
      final result = await widget.infoExtractor.probe(url);
      if (!mounted) return;

      if (result.isPlaylist) {
        final selection =
            await showPlaylistSheet(context, result.playlistInfo!);
        if (selection == null || !mounted) return;
        _urlController.clear();
        final error = await _dm.downloadPlaylist(
          url: url,
          playlistTitle: result.playlistInfo!.title,
          uploader: result.playlistInfo!.uploader,
          selectedEntries: selection.selectedEntries,
          formatId: selection.formatId,
        );
        if (error != null && mounted) _showError(error);
      } else {
        final selection = await showFormatSheet(context, result.mediaInfo!);
        if (selection == null || !mounted) return;
        _urlController.clear();
        final error =
            await _dm.download(url, formatId: selection.formatId);
        if (error != null && mounted) _showError(error);
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// Quick download with best format (no info fetch).
  Future<void> _quickDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    _urlController.clear();
    final error = await _dm.download(url);
    if (error != null && mounted) _showError(error);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Media DL'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(
                  settings: widget.settings,
                  binaryManager: widget.binaryManager,
                  updateChecker: widget.updateChecker,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'Paste URL here...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                    onSubmitted: (_) => _fetchAndChooseFormat(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _fetching ? null : _fetchAndChooseFormat,
                  icon: _fetching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Download'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _fetching ? null : _quickDownload,
                  icon: const Icon(Icons.bolt),
                  tooltip: 'Quick download (best quality)',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _dm,
              builder: (context, _) {
                final entries = _dm.entries;
                if (entries.isEmpty) {
                  return const _EmptyState();
                }
                final hasCompleted =
                    entries.any((e) => e.status == DownloadStatus.completed);
                return Column(
                  children: [
                    if (hasCompleted)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _dm.clearCompleted,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear completed'),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return switch (entry) {
                            DownloadTask task => _DownloadCard(
                                task: task,
                                onCancel: () => _dm.cancel(task),
                                onPause: () => _dm.pause(task),
                                onResume: () => _dm.resume(task),
                                onRetry: () => _dm.retry(task),
                                onRemove: () => _dm.remove(task),
                              ),
                            PlaylistDownloadTask playlist =>
                              _PlaylistCard(
                                playlist: playlist,
                                onCancel: () => _dm.cancel(playlist),
                                onPause: () => _dm.pause(playlist),
                                onResume: () => _dm.resume(playlist),
                                onRetry: () => _dm.retry(playlist),
                                onRemove: () => _dm.remove(playlist),
                              ),
                          };
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('No downloads yet',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          SizedBox(height: 8),
          Text('Paste a URL above to get started',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single download card
// ---------------------------------------------------------------------------

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.task,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onRemove,
  });

  final DownloadTask task;
  final VoidCallback onCancel;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusIcon(task.status, colorScheme),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.fileName ?? task.url,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _actionButtons(task.status),
              ],
            ),
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.paused) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: task.progress != null
                    ? task.progress!.percent / 100.0
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              task.status == DownloadStatus.paused
                  ? Text('Paused${task.progress != null ? '  ·  ${task.progress!.percent.toStringAsFixed(1)}%' : ''}',
                      style: theme.textTheme.bodySmall)
                  : _progressText(theme, task.progress),
            ],
            if (task.status == DownloadStatus.completed &&
                task.fileSize != null) ...[
              const SizedBox(height: 4),
              Text(task.fileSize!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.outline)),
            ],
            if (task.status == DownloadStatus.failed &&
                task.error != null) ...[
              const SizedBox(height: 8),
              Text(task.error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButtons(DownloadStatus status) {
    return switch (status) {
      DownloadStatus.downloading => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: onPause,
                icon: const Icon(Icons.pause),
                tooltip: 'Pause'),
            IconButton(
                onPressed: onCancel,
                icon: const Icon(Icons.close),
                tooltip: 'Cancel'),
          ],
        ),
      DownloadStatus.queued => IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
        ),
      DownloadStatus.paused => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Resume'),
            IconButton(
                onPressed: onCancel,
                icon: const Icon(Icons.close),
                tooltip: 'Cancel'),
          ],
        ),
      DownloadStatus.failed || DownloadStatus.cancelled => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                tooltip: 'Retry'),
            IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove'),
          ],
        ),
      _ => IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove',
        ),
    };
  }
}

// ---------------------------------------------------------------------------
// Playlist download card
// ---------------------------------------------------------------------------

class _PlaylistCard extends StatefulWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onRemove,
  });

  final PlaylistDownloadTask playlist;
  final VoidCallback onCancel;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _expanded = false;

  PlaylistDownloadTask get pl => widget.playlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                _statusIcon(pl.status, colorScheme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.playlist_play,
                              size: 18, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              pl.playlistTitle,
                              style: theme.textTheme.bodyLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${pl.completedCount} of ${pl.totalCount} completed',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                _playlistActions(),
              ],
            ),
          ),

          // Overall progress bar
          if (pl.status == DownloadStatus.downloading ||
              pl.status == DownloadStatus.paused) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: LinearProgressIndicator(
                value: pl.overallPercent / 100.0,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                pl.status == DownloadStatus.paused
                    ? 'Paused  ·  ${pl.overallPercent.toStringAsFixed(1)}%'
                    : '${pl.overallPercent.toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],

          // Error message
          if (pl.status == DownloadStatus.failed && pl.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(pl.error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),

          // Expand/collapse button
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _expanded ? 'Hide items' : 'Show items',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),

          // Expanded item list
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  for (final item in pl.items)
                    _PlaylistItemRow(item: item, theme: theme),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _playlistActions() {
    return switch (pl.status) {
      DownloadStatus.downloading => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: widget.onPause,
                icon: const Icon(Icons.pause),
                tooltip: 'Pause'),
            IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
                tooltip: 'Cancel'),
          ],
        ),
      DownloadStatus.queued => IconButton(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
        ),
      DownloadStatus.paused => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: widget.onResume,
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Resume'),
            IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
                tooltip: 'Cancel'),
          ],
        ),
      DownloadStatus.failed || DownloadStatus.cancelled => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                tooltip: 'Retry'),
            IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove'),
          ],
        ),
      _ => IconButton(
          onPressed: widget.onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove',
        ),
    };
  }
}

class _PlaylistItemRow extends StatelessWidget {
  const _PlaylistItemRow({required this.item, required this.theme});

  final DownloadTask item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: _statusIcon(item.status, colorScheme, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName ?? item.url,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((item.status == DownloadStatus.downloading ||
                        item.status == DownloadStatus.paused) &&
                    item.progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LinearProgressIndicator(
                      value: item.progress!.percent / 100.0,
                      borderRadius: BorderRadius.circular(2),
                      minHeight: 2,
                    ),
                  ),
              ],
            ),
          ),
          if ((item.status == DownloadStatus.downloading ||
                  item.status == DownloadStatus.paused) &&
              item.progress != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${item.progress!.percent.toStringAsFixed(0)}%',
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Widget _statusIcon(DownloadStatus status, ColorScheme colorScheme,
    {double size = 24}) {
  return switch (status) {
    DownloadStatus.queued =>
      Icon(Icons.hourglass_empty, color: colorScheme.outline, size: size),
    DownloadStatus.downloading =>
      Icon(Icons.downloading, color: colorScheme.primary, size: size),
    DownloadStatus.paused =>
      Icon(Icons.pause_circle, color: colorScheme.tertiary, size: size),
    DownloadStatus.completed =>
      Icon(Icons.check_circle, color: Colors.green, size: size),
    DownloadStatus.failed =>
      Icon(Icons.error, color: colorScheme.error, size: size),
    DownloadStatus.cancelled =>
      Icon(Icons.cancel, color: colorScheme.outline, size: size),
  };
}

Widget _progressText(ThemeData theme, DownloadProgress? progress) {
  if (progress == null) {
    return Text('Starting...', style: theme.textTheme.bodySmall);
  }
  final parts = <String>['${progress.percent.toStringAsFixed(1)}%'];
  if (progress.totalSize != null) parts.add(progress.totalSize!);
  if (progress.speed != null) parts.add(progress.speed!);
  if (progress.eta != null) parts.add('ETA ${progress.eta}');
  return Text(parts.join('  ·  '), style: theme.textTheme.bodySmall);
}

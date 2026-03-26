import 'package:flutter/material.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/services/download_manager.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, required this.downloadManager});

  final DownloadManager downloadManager;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _urlController = TextEditingController();

  DownloadManager get _dm => widget.downloadManager;

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    _urlController.clear();
    final error = await _dm.download(url);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media DL')),
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
                    onSubmitted: (_) => _startDownload(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _dm,
              builder: (context, _) {
                final tasks = _dm.tasks;
                if (tasks.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    return _DownloadCard(
                      task: tasks[index],
                      onCancel: () => _dm.cancel(tasks[index]),
                      onRemove: () => _dm.remove(tasks[index]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
          Text(
            'No downloads yet',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Paste a URL above to get started',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.task,
    required this.onCancel,
    required this.onRemove,
  });

  final DownloadTask task;
  final VoidCallback onCancel;
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
            // Title row
            Row(
              children: [
                _statusIcon(colorScheme),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.fileName ?? task.url,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _actionButton(colorScheme),
              ],
            ),

            // Progress bar (only when downloading)
            if (task.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: task.progress != null
                    ? task.progress!.percent / 100.0
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              _progressDetails(theme),
            ],

            // Error message
            if (task.status == DownloadStatus.failed &&
                task.error != null) ...[
              const SizedBox(height: 8),
              Text(
                task.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(ColorScheme colorScheme) {
    return switch (task.status) {
      DownloadStatus.queued =>
        Icon(Icons.hourglass_empty, color: colorScheme.outline),
      DownloadStatus.downloading =>
        Icon(Icons.downloading, color: colorScheme.primary),
      DownloadStatus.completed =>
        Icon(Icons.check_circle, color: Colors.green),
      DownloadStatus.failed =>
        Icon(Icons.error, color: colorScheme.error),
      DownloadStatus.cancelled =>
        Icon(Icons.cancel, color: colorScheme.outline),
    };
  }

  Widget _actionButton(ColorScheme colorScheme) {
    return switch (task.status) {
      DownloadStatus.queued ||
      DownloadStatus.downloading =>
        IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
        ),
      _ => IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove',
        ),
    };
  }

  Widget _progressDetails(ThemeData theme) {
    final progress = task.progress;
    if (progress == null) {
      return Text('Starting...', style: theme.textTheme.bodySmall);
    }

    final parts = <String>[
      '${progress.percent.toStringAsFixed(1)}%',
    ];
    if (progress.totalSize != null) parts.add(progress.totalSize!);
    if (progress.speed != null) parts.add(progress.speed!);
    if (progress.eta != null) parts.add('ETA ${progress.eta}');

    return Text(
      parts.join('  ·  '),
      style: theme.textTheme.bodySmall,
    );
  }
}

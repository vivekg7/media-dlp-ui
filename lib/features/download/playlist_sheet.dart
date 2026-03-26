import 'package:flutter/material.dart';
import 'package:media_dl/core/models.dart';

/// Result from the playlist selection sheet.
class PlaylistSelection {
  const PlaylistSelection({
    required this.selectedEntries,
    this.formatId,
  });

  final List<PlaylistEntry> selectedEntries;
  final String? formatId;
}

/// Shows a bottom sheet for selecting playlist items.
Future<PlaylistSelection?> showPlaylistSheet(
  BuildContext context,
  PlaylistInfo info,
) {
  return showModalBottomSheet<PlaylistSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _PlaylistSheet(info: info),
  );
}

class _PlaylistSheet extends StatefulWidget {
  const _PlaylistSheet({required this.info});
  final PlaylistInfo info;

  @override
  State<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends State<_PlaylistSheet> {
  late final Set<int> _selected; // set of 1-based indices

  PlaylistInfo get info => widget.info;

  @override
  void initState() {
    super.initState();
    // Select all by default
    _selected = info.entries.map((e) => e.index).toSet();
  }

  bool get _allSelected => _selected.length == info.entries.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.addAll(info.entries.map((e) => e.index));
      }
    });
  }

  void _toggle(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Playlist header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (info.uploader != null) ...[
                        Text(
                          info.uploader!,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text('·', style: theme.textTheme.bodySmall),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${info.itemCount} items',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Select all / count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _allSelected,
                    tristate: true,
                    onChanged: (_) => _toggleAll(),
                  ),
                  Text(
                    _allSelected
                        ? 'All selected'
                        : '${_selected.length} of ${info.itemCount} selected',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Item list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: info.entries.length,
                itemBuilder: (context, index) {
                  final entry = info.entries[index];
                  final checked = _selected.contains(entry.index);
                  return ListTile(
                    leading: Checkbox(
                      value: checked,
                      onChanged: (_) => _toggle(entry.index),
                    ),
                    title: Text(
                      entry.title,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: entry.duration != null
                        ? Text(entry.durationString,
                            style: theme.textTheme.bodySmall)
                        : null,
                    dense: true,
                    onTap: () => _toggle(entry.index),
                  );
                },
              ),
            ),

            // Download button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final selectedEntries = info.entries
                              .where((e) => _selected.contains(e.index))
                              .toList();
                          Navigator.of(context).pop(
                            PlaylistSelection(
                                selectedEntries: selectedEntries),
                          );
                        },
                  icon: const Icon(Icons.download),
                  label: Text(
                    _selected.isEmpty
                        ? 'Select items to download'
                        : 'Download ${_selected.length} items',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

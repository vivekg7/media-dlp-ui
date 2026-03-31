import 'package:flutter/material.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/core/settings_notifier.dart';

/// Result from the format selection sheet.
class FormatSelection {
  const FormatSelection({
    this.formatId,
    this.isAudioOnly = false,
    this.embedSubs,
  });
  final String? formatId;
  final bool isAudioOnly;
  /// Override for subtitle embedding. Null means use global setting.
  final bool? embedSubs;
}

/// Shows a bottom sheet with media info and format picker.
/// Returns a [FormatSelection] if user confirms, or null if dismissed.
Future<FormatSelection?> showFormatSheet(
  BuildContext context,
  MediaInfo info, {
  required SettingsNotifier settings,
}) {
  return showModalBottomSheet<FormatSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _FormatSheet(info: info, settings: settings),
  );
}

class _FormatSheet extends StatefulWidget {
  const _FormatSheet({required this.info, required this.settings});
  final MediaInfo info;
  final SettingsNotifier settings;

  @override
  State<_FormatSheet> createState() => _FormatSheetState();
}

class _FormatSheetState extends State<_FormatSheet> {
  String? _selectedFormatId;
  late bool _embedSubs;

  @override
  void initState() {
    super.initState();
    _embedSubs = widget.settings.embedSubs;
  }

  MediaInfo get info => widget.info;
  SettingsNotifier get settings => widget.settings;

  bool get _audioOnly => settings.extractAudio;

  List<MediaFormat> get _videoAudioFormats =>
      info.formats.where((f) => f.isVideoAndAudio).toList();

  List<MediaFormat> get _videoOnlyFormats =>
      info.formats.where((f) => f.isVideoOnly).toList();

  List<MediaFormat> get _audioOnlyFormats =>
      info.formats.where((f) => f.isAudioOnly).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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

            // Media info header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  if (info.thumbnailUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        info.thumbnailUrl!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 120,
                          height: 68,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                  if (info.thumbnailUrl != null) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (info.uploader != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            info.uploader!,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (info.duration != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            info.durationString,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Settings summary
            _buildSettingsSummary(theme),

            const Divider(height: 1),

            // Format list
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Subtitle toggle
                  if (!_audioOnly)
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.subtitles_outlined, size: 20),
                      title: Text('Subtitles',
                          style: theme.textTheme.bodyMedium),
                      subtitle: _embedSubs
                          ? Text(settings.subLangs,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline))
                          : null,
                      value: _embedSubs,
                      onChanged: (v) => setState(() => _embedSubs = v),
                    ),
                  if (_audioOnly) ...[
                    // Audio-only mode: show best audio + audio formats only
                    _buildFormatTile(
                      theme,
                      title: 'Best quality',
                      subtitle:
                          'Auto-select best audio, convert to ${settings.audioFormat}',
                      formatId: null,
                      icon: Icons.auto_awesome,
                    ),
                    if (_audioOnlyFormats.isNotEmpty) ...[
                      _buildSectionHeader(theme, 'Audio Only'),
                      ..._audioOnlyFormats.map(
                          (f) => _buildFormatTileFromFormat(theme, f)),
                    ],
                  ] else ...[
                    // Normal mode: show all formats
                    _buildFormatTile(
                      theme,
                      title: 'Best quality',
                      subtitle: 'Auto-select best video + audio',
                      formatId: null,
                      icon: Icons.auto_awesome,
                    ),
                    if (_videoAudioFormats.isNotEmpty) ...[
                      _buildSectionHeader(theme, 'Video + Audio'),
                      ..._videoAudioFormats.map(
                          (f) => _buildFormatTileFromFormat(theme, f)),
                    ],
                    if (_audioOnlyFormats.isNotEmpty) ...[
                      _buildSectionHeader(theme, 'Audio Only'),
                      ..._audioOnlyFormats.map(
                          (f) => _buildFormatTileFromFormat(theme, f)),
                    ],
                    if (_videoOnlyFormats.isNotEmpty) ...[
                      _buildSectionHeader(theme, 'Video Only (no audio)'),
                      ..._videoOnlyFormats.map(
                          (f) => _buildFormatTileFromFormat(theme, f)),
                    ],
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),

            // Download button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final isAudio = _audioOnly ||
                        (_selectedFormatId != null &&
                            _audioOnlyFormats
                                .any((f) => f.formatId == _selectedFormatId));
                    Navigator.of(context).pop(
                      FormatSelection(
                        formatId: _selectedFormatId,
                        isAudioOnly: isAudio,
                        embedSubs: _embedSubs != settings.embedSubs
                            ? _embedSubs
                            : null,
                      ),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsSummary(ThemeData theme) {
    final chips = <Widget>[];

    if (_audioOnly) {
      chips.add(_settingsChip(
        theme,
        Icons.music_note,
        'Audio only (${settings.audioFormat})',
        highlight: true,
      ));
    } else if (settings.videoFormat != null) {
      chips.add(_settingsChip(
        theme,
        Icons.video_file_outlined,
        'Remux to ${settings.videoFormat}',
      ));
    }

    if (settings.embedThumbnail) {
      chips.add(_settingsChip(theme, Icons.image_outlined, 'Thumbnail'));
    }
    if (settings.embedMetadata) {
      chips.add(_settingsChip(theme, Icons.info_outline, 'Metadata'));
    }
    if (settings.sponsorBlock) {
      chips.add(_settingsChip(theme, Icons.block, 'SponsorBlock'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: chips,
      ),
    );
  }

  Widget _settingsChip(
    ThemeData theme,
    IconData icon,
    String label, {
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: highlight
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: highlight
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildFormatTile(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required String? formatId,
    IconData? icon,
  }) {
    final selected = _selectedFormatId == formatId;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(title, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () => setState(() => _selectedFormatId = formatId),
    );
  }

  Widget _buildFormatTileFromFormat(ThemeData theme, MediaFormat f) {
    final parts = <String>[];
    if (f.extension != null) parts.add(f.extension!);
    if (f.resolution != null && f.resolution != 'audio only') {
      parts.add(f.resolution!);
    }
    if (f.formatNote != null) parts.add(f.formatNote!);
    if (f.fps != null && f.fps! > 0) parts.add('${f.fps!.toInt()}fps');

    final subtitle = <String>[];
    if (f.vcodec != null && f.vcodec != 'none') subtitle.add(f.vcodec!);
    if (f.acodec != null && f.acodec != 'none') subtitle.add(f.acodec!);
    if (f.abr != null && f.abr! > 0) subtitle.add('${f.abr!.toInt()}kbps');
    final size = f.sizeString;
    if (size.isNotEmpty) subtitle.add(size);

    return _buildFormatTile(
      theme,
      title: parts.join(' · '),
      subtitle: subtitle.join(' · '),
      formatId: f.formatId,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/update_checker.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.binaryManager,
    required this.updateChecker,
  });

  final SettingsNotifier settings;
  final BinaryManager binaryManager;
  final UpdateChecker updateChecker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, binaryManager]),
        builder: (context, _) {
          return ListView(
            children: [
              const _SectionHeader(title: 'Appearance'),
              _ThemeTile(settings: settings),
              const Divider(),
              const _SectionHeader(title: 'Downloads'),
              _OutputDirTile(settings: settings),
              _FilenameTile(
                label: 'Filename template',
                value: settings.filenameTemplate,
                presets: kFilenamePresets,
                onChanged: settings.setFilenameTemplate,
              ),
              _FilenameTile(
                label: 'Playlist template',
                value: settings.playlistTemplate,
                presets: kPlaylistPresets,
                onChanged: settings.setPlaylistTemplate,
              ),
              const Divider(),
              const _SectionHeader(title: 'Post-Processing'),
              SwitchListTile(
                secondary: const Icon(Icons.image_outlined),
                title: const Text('Embed thumbnail'),
                subtitle: const Text('Add cover art to downloaded files'),
                value: settings.embedThumbnail,
                onChanged: (v) => settings.setEmbedThumbnail(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.label_outlined),
                title: const Text('Embed metadata'),
                subtitle: const Text('Add title, artist, date tags'),
                value: settings.embedMetadata,
                onChanged: (v) => settings.setEmbedMetadata(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.subtitles_outlined),
                title: const Text('Embed subtitles'),
                value: settings.embedSubs,
                onChanged: (v) => settings.setEmbedSubs(v),
              ),
              if (settings.embedSubs)
                _SubLangsTile(settings: settings),
              SwitchListTile(
                secondary: const Icon(Icons.block),
                title: const Text('SponsorBlock'),
                subtitle:
                    const Text('Remove sponsor segments from videos'),
                value: settings.sponsorBlock,
                onChanged: (v) => settings.setSponsorBlock(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.music_note_outlined),
                title: const Text('Extract audio only'),
                value: settings.extractAudio,
                onChanged: (v) => settings.setExtractAudio(v),
              ),
              if (settings.extractAudio)
                _AudioFormatTile(settings: settings),
              const Divider(),
              const _SectionHeader(title: 'Authentication'),
              _CookieTile(settings: settings),
              const Divider(),
              const _SectionHeader(title: 'Network'),
              _NetworkField(
                icon: Icons.vpn_lock,
                label: 'Proxy',
                hint: 'socks5://127.0.0.1:1080',
                value: settings.proxyUrl,
                helpText: 'HTTP/HTTPS/SOCKS proxy URL',
                onChanged: settings.setProxyUrl,
              ),
              _NetworkField(
                icon: Icons.speed,
                label: 'Rate limit',
                hint: '5M',
                value: settings.rateLimit,
                helpText: 'e.g. 500K, 5M, 1G (bytes per second)',
                onChanged: settings.setRateLimit,
              ),
              _NetworkField(
                icon: Icons.lan_outlined,
                label: 'Source address',
                hint: '0.0.0.0',
                value: settings.sourceAddress,
                helpText: 'Bind to a specific local IP address',
                onChanged: settings.setSourceAddress,
              ),
              const Divider(),
              const _SectionHeader(title: 'Tools'),
              _BinaryTile(
                binaryManager: binaryManager,
                updateChecker: updateChecker,
              ),
              const Divider(),
              const _SectionHeader(title: 'About'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Media DL'),
                subtitle: Text('A free and open-source media downloader'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.settings});

  final SettingsNotifier settings;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Theme'),
      subtitle: Text(_label(settings.themeMode)),
      trailing: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode),
          ),
        ],
        selected: {settings.themeMode},
        onSelectionChanged: (selected) {
          settings.setThemeMode(selected.first);
        },
      ),
    );
  }

  String _label(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
  }
}

// ---------------------------------------------------------------------------
// Subtitle languages
// ---------------------------------------------------------------------------

class _SubLangsTile extends StatelessWidget {
  const _SubLangsTile({required this.settings});

  final SettingsNotifier settings;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 24),
      title: const Text('Subtitle languages'),
      subtitle: Text(settings.subLangs),
      trailing: IconButton(
        icon: const Icon(Icons.edit),
        tooltip: 'Edit languages',
        onPressed: () => _editLangs(context),
      ),
    );
  }

  void _editLangs(BuildContext context) {
    final controller = TextEditingController(text: settings.subLangs);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subtitle languages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'en',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: kSubtitleLangPresets
                  .map((lang) => ActionChip(
                        label: Text(lang),
                        onPressed: () => controller.text = lang,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Comma-separated language codes. Use "all" for all available.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) settings.setSubLangs(val);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose;
  }
}

// ---------------------------------------------------------------------------
// Audio format
// ---------------------------------------------------------------------------

class _AudioFormatTile extends StatelessWidget {
  const _AudioFormatTile({required this.settings});

  final SettingsNotifier settings;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 24),
      title: const Text('Audio format'),
      trailing: DropdownButton<String>(
        value: settings.audioFormat,
        underline: const SizedBox.shrink(),
        onChanged: (v) {
          if (v != null) settings.setAudioFormat(v);
        },
        items: kAudioFormats
            .map((f) => DropdownMenuItem(value: f, child: Text(f)))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Network field (reusable for proxy, rate limit, source address)
// ---------------------------------------------------------------------------

class _NetworkField extends StatelessWidget {
  const _NetworkField({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.helpText,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String hint;
  final String? value;
  final String helpText;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSet = value != null;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        isSet ? value! : 'Not set',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isSet ? null : TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: () => _edit(context),
          ),
          if (isSet)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }

  void _edit(BuildContext context) {
    final controller = TextEditingController(text: value ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: hint,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              helpText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              onChanged(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose;
  }
}

// ---------------------------------------------------------------------------
// Cookie file
// ---------------------------------------------------------------------------

class _CookieTile extends StatelessWidget {
  const _CookieTile({required this.settings});

  final SettingsNotifier settings;

  @override
  Widget build(BuildContext context) {
    final path = settings.cookieFilePath;
    final isSet = path != null;

    return ListTile(
      leading: Icon(
        isSet ? Icons.cookie : Icons.cookie_outlined,
        color: isSet ? Theme.of(context).colorScheme.primary : null,
      ),
      title: const Text('Cookie file'),
      subtitle: Text(
        isSet ? path : 'Not set — needed for age-restricted or private content',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Set cookie file path',
            onPressed: () => _editPath(context),
          ),
          if (isSet)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Remove cookie file',
              onPressed: () => settings.setCookieFilePath(null),
            ),
        ],
      ),
    );
  }

  void _editPath(BuildContext context) {
    final controller =
        TextEditingController(text: settings.cookieFilePath ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cookie file path'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '/path/to/cookies.txt',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              'Provide a Netscape-format cookies.txt file.\n'
              'Export from your browser using an extension like '
              '"Get cookies.txt LOCALLY".',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              settings.setCookieFilePath(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose;
  }
}

// ---------------------------------------------------------------------------
// Output directory
// ---------------------------------------------------------------------------

class _OutputDirTile extends StatelessWidget {
  const _OutputDirTile({required this.settings});

  final SettingsNotifier settings;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: const Text('Download directory'),
      subtitle: Text(
        settings.outputDir,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit),
        tooltip: 'Change directory',
        onPressed: () => _editDir(context),
      ),
    );
  }

  void _editDir(BuildContext context) {
    final controller = TextEditingController(text: settings.outputDir);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download directory'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '/path/to/downloads',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                settings.setOutputDir(value);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose;
  }
}

// ---------------------------------------------------------------------------
// Filename template
// ---------------------------------------------------------------------------

class _FilenameTile extends StatelessWidget {
  const _FilenameTile({
    required this.label,
    required this.value,
    required this.presets,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> presets;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.text_fields),
      title: Text(label),
      subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.edit),
        tooltip: 'Edit template',
        onPressed: () => _editTemplate(context),
      ),
    );
  }

  void _editTemplate(BuildContext context) {
    final controller = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '%(title)s.%(ext)s',
              ),
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text('Presets',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            ...presets.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: OutlinedButton(
                    onPressed: () => controller.text = e.value,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(e.key, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                )),
            const SizedBox(height: 12),
            Text(
              'Variables: %(title)s, %(ext)s, %(id)s, %(uploader)s, '
              '%(upload_date)s, %(playlist_title)s, %(playlist_index)s',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) onChanged(val);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose;
  }
}

// ---------------------------------------------------------------------------
// Binary / yt-dlp
// ---------------------------------------------------------------------------

class _BinaryTile extends StatefulWidget {
  const _BinaryTile({
    required this.binaryManager,
    required this.updateChecker,
  });

  final BinaryManager binaryManager;
  final UpdateChecker updateChecker;

  @override
  State<_BinaryTile> createState() => _BinaryTileState();
}

class _BinaryTileState extends State<_BinaryTile> {
  bool _checkingUpdate = false;
  UpdateCheckResult? _updateResult;
  String? _updateError;

  @override
  Widget build(BuildContext context) {
    final info = widget.binaryManager.ytDlp;
    final theme = Theme.of(context);
    final isUpdating = widget.binaryManager.updating;

    if (widget.binaryManager.checking) {
      return const ListTile(
        leading: Icon(Icons.terminal),
        title: Text('yt-dlp'),
        subtitle: Text('Detecting...'),
        trailing: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(
            info.isAvailable
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: info.isAvailable
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
          title: const Text('yt-dlp'),
          subtitle: Text(
            info.isAvailable
                ? 'v${info.version}  •  ${info.path}'
                : info.error ?? 'Not found',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Re-detect',
                onPressed: isUpdating ? null : () => widget.binaryManager.detect(),
              ),
              if (info.isAvailable)
                _checkingUpdate
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.update),
                        tooltip: 'Check for update',
                        onPressed: isUpdating ? null : _checkForUpdate,
                      ),
            ],
          ),
        ),
        if (isUpdating)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Downloading update...', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        if (_updateError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _updateError!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ),
        if (!isUpdating && _updateResult != null) _buildUpdateResult(theme),
      ],
    );
  }

  Future<void> _checkForUpdate() async {
    final version = widget.binaryManager.ytDlp.version;
    if (version == null) return;

    setState(() {
      _checkingUpdate = true;
      _updateResult = null;
      _updateError = null;
    });

    final result = await widget.updateChecker.check(
      repo: 'yt-dlp/yt-dlp',
      currentVersion: version,
    );

    if (mounted) {
      setState(() {
        _checkingUpdate = false;
        _updateResult = result;
      });
    }
  }

  Future<void> _installUpdate() async {
    final assetUrl = _updateResult?.assetUrl;
    if (assetUrl == null) return;

    setState(() {
      _updateError = null;
    });

    final error = await widget.binaryManager.updateYtDlp(assetUrl);
    if (mounted) {
      setState(() {
        if (error != null) {
          _updateError = error;
        } else {
          _updateResult = null;
        }
      });
    }
  }

  Widget _buildUpdateResult(ThemeData theme) {
    final result = _updateResult!;

    if (result.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          result.error!,
          style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
        ),
      );
    }

    if (result.hasUpdate) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.new_releases,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Update available: v${result.latestVersion}',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (result.assetUrl != null)
              FilledButton.tonal(
                onPressed: _installUpdate,
                child: const Text('Update'),
              ),
          ],
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        'Already on the latest version',
        style: TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }
}

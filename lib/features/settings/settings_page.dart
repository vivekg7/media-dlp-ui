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

  @override
  Widget build(BuildContext context) {
    final info = widget.binaryManager.ytDlp;
    final theme = Theme.of(context);

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
            info.isAvailable ? Icons.check_circle_outline : Icons.error_outline,
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
                onPressed: () => widget.binaryManager.detect(),
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
                        onPressed: _checkForUpdate,
                      ),
            ],
          ),
        ),
        if (_updateResult != null) _buildUpdateResult(theme),
      ],
    );
  }

  Future<void> _checkForUpdate() async {
    final version = widget.binaryManager.ytDlp.version;
    if (version == null) return;

    setState(() {
      _checkingUpdate = true;
      _updateResult = null;
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.new_releases, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Update available: v${result.latestVersion}',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
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

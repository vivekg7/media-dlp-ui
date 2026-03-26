import 'package:flutter/material.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/core/theme.dart';
import 'package:media_dl/features/download/download_page.dart';
import 'package:media_dl/features/settings/settings_page.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/download_manager.dart';
import 'package:media_dl/services/update_checker.dart';

class MediaDlApp extends StatelessWidget {
  const MediaDlApp({
    super.key,
    required this.settings,
    required this.binaryManager,
    required this.updateChecker,
    required this.downloadManager,
  });

  final SettingsNotifier settings;
  final BinaryManager binaryManager;
  final UpdateChecker updateChecker;
  final DownloadManager downloadManager;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Media DL',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: settings.themeMode,
          home: AppShell(
            settings: settings,
            binaryManager: binaryManager,
            updateChecker: updateChecker,
            downloadManager: downloadManager,
          ),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settings,
    required this.binaryManager,
    required this.updateChecker,
    required this.downloadManager,
  });

  final SettingsNotifier settings;
  final BinaryManager binaryManager;
  final UpdateChecker updateChecker;
  final DownloadManager downloadManager;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DownloadPage(downloadManager: widget.downloadManager),
          SettingsPage(
            settings: widget.settings,
            binaryManager: widget.binaryManager,
            updateChecker: widget.updateChecker,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

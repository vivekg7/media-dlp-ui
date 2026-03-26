import 'package:flutter/material.dart';
import 'package:media_dl/app.dart';
import 'package:media_dl/core/app_dirs.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/binary_resolver.dart';
import 'package:media_dl/services/download_manager.dart';
import 'package:media_dl/services/update_checker.dart';
import 'package:media_dl/services/ytdlp_info_extractor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appSupportDir = getAppSupportDir();
  await ensureAppDirs(appSupportDir);

  final settings = SettingsNotifier(
    settingsPath: '$appSupportDir/settings.json',
  );
  await settings.load();

  final resolver = BinaryResolver(appSupportDir: appSupportDir);
  final binaryManager = BinaryManager(resolver: resolver);
  final updateChecker = UpdateChecker();
  final downloadManager = DownloadManager(
    binaryManager: binaryManager,
    settings: settings,
    historyPath: '$appSupportDir/download_history.json',
  );

  final infoExtractor = YtDlpInfoExtractor(binaryManager: binaryManager);

  // Detect binaries and load history on startup
  binaryManager.detect();
  downloadManager.loadHistory();

  runApp(MediaDlApp(
    settings: settings,
    binaryManager: binaryManager,
    updateChecker: updateChecker,
    downloadManager: downloadManager,
    infoExtractor: infoExtractor,
  ));
}

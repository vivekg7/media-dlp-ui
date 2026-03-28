import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_dl/app.dart';
import 'package:media_dl/core/app_dirs.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/services/android_process_runner.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/binary_resolver.dart';
import 'package:media_dl/services/download_manager.dart';
import 'package:media_dl/services/process_runner.dart';
import 'package:media_dl/services/share_receiver.dart';
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
  final updateChecker = UpdateChecker();
  final binaryManager = BinaryManager(
    resolver: resolver,
    updateChecker: updateChecker,
  );
  final processRunner =
      Platform.isAndroid ? AndroidProcessRunner() : ProcessRunner();
  final downloadManager = DownloadManager(
    binaryManager: binaryManager,
    settings: settings,
    historyPath: '$appSupportDir/download_history.json',
    processRunner: processRunner,
  );

  final infoExtractor = YtDlpInfoExtractor(
    binaryManager: binaryManager,
    settings: settings,
  );

  final shareReceiver = ShareReceiver();

  // Load history on startup (detect is triggered after platform channels are ready)
  downloadManager.loadHistory();

  runApp(MediaDlApp(
    settings: settings,
    binaryManager: binaryManager,
    updateChecker: updateChecker,
    downloadManager: downloadManager,
    infoExtractor: infoExtractor,
    shareReceiver: shareReceiver,
  ));
}

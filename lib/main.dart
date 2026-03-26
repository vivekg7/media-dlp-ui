import 'package:flutter/material.dart';
import 'package:media_dl/app.dart';
import 'package:media_dl/core/app_dirs.dart';
import 'package:media_dl/core/settings_notifier.dart';
import 'package:media_dl/services/binary_manager.dart';
import 'package:media_dl/services/binary_resolver.dart';
import 'package:media_dl/services/download_manager.dart';
import 'package:media_dl/services/update_checker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appSupportDir = getAppSupportDir();
  await ensureAppDirs(appSupportDir);

  final settings = SettingsNotifier();
  final resolver = BinaryResolver(appSupportDir: appSupportDir);
  final binaryManager = BinaryManager(resolver: resolver);
  final updateChecker = UpdateChecker();
  final downloadManager = DownloadManager(
    binaryManager: binaryManager,
    outputDir: getDefaultOutputDir(),
  );

  // Detect binaries on startup
  binaryManager.detect();

  runApp(MediaDlApp(
    settings: settings,
    binaryManager: binaryManager,
    updateChecker: updateChecker,
    downloadManager: downloadManager,
  ));
}

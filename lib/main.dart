import 'package:flutter/material.dart';
import 'package:media_dl/app.dart';
import 'package:media_dl/core/settings_notifier.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsNotifier();
  runApp(MediaDlApp(settings: settings));
}

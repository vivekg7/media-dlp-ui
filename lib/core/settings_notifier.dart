import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_dl/core/app_dirs.dart';

/// Default filename template for single downloads.
const kDefaultFilenameTemplate = '%(title)s.%(ext)s';

/// Default filename template for playlist downloads.
const kDefaultPlaylistTemplate =
    '%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s';

/// Common filename template presets.
const kFilenamePresets = <String, String>{
  'Title only': '%(title)s.%(ext)s',
  'Title + ID': '%(title)s [%(id)s].%(ext)s',
  'Uploader - Title': '%(uploader)s - %(title)s.%(ext)s',
  'Upload date - Title': '%(upload_date)s - %(title)s.%(ext)s',
};

const kPlaylistPresets = <String, String>{
  'Playlist folder / Index - Title':
      '%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s',
  'Playlist folder / Title':
      '%(playlist_title)s/%(title)s.%(ext)s',
  'Playlist folder / Index - Title + ID':
      '%(playlist_title)s/%(playlist_index)s - %(title)s [%(id)s].%(ext)s',
};

class SettingsNotifier extends ChangeNotifier {
  SettingsNotifier({required this.settingsPath});

  final String settingsPath;

  ThemeMode _themeMode = ThemeMode.system;
  String _outputDir = getDefaultOutputDir();
  String _filenameTemplate = kDefaultFilenameTemplate;
  String _playlistTemplate = kDefaultPlaylistTemplate;

  ThemeMode get themeMode => _themeMode;
  String get outputDir => _outputDir;
  String get filenameTemplate => _filenameTemplate;
  String get playlistTemplate => _playlistTemplate;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _save();
  }

  void setOutputDir(String dir) {
    if (_outputDir == dir) return;
    _outputDir = dir;
    notifyListeners();
    _save();
  }

  void setFilenameTemplate(String template) {
    if (_filenameTemplate == template) return;
    _filenameTemplate = template;
    notifyListeners();
    _save();
  }

  void setPlaylistTemplate(String template) {
    if (_playlistTemplate == template) return;
    _playlistTemplate = template;
    notifyListeners();
    _save();
  }

  /// Load settings from disk.
  Future<void> load() async {
    final file = File(settingsPath);
    if (!await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => ThemeMode.system,
      );
      _outputDir = json['outputDir'] as String? ?? getDefaultOutputDir();
      _filenameTemplate =
          json['filenameTemplate'] as String? ?? kDefaultFilenameTemplate;
      _playlistTemplate =
          json['playlistTemplate'] as String? ?? kDefaultPlaylistTemplate;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }

  Future<void> _save() async {
    try {
      final json = {
        'themeMode': _themeMode.name,
        'outputDir': _outputDir,
        'filenameTemplate': _filenameTemplate,
        'playlistTemplate': _playlistTemplate,
      };
      await File(settingsPath).writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }
}

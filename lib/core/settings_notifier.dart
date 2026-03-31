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

/// Audio format options for extraction.
const kAudioFormats = ['mp3', 'opus', 'aac', 'm4a'];

/// Video container format options for remuxing.
const kVideoFormats = ['mp4', 'mkv', 'webm'];

/// Default gallery-dl filename template.
const kDefaultGalleryDlTemplate = '{category}/{filename}.{extension}';

/// gallery-dl filename template presets.
const kGalleryDlPresets = <String, String>{
  'Category / Filename': '{category}/{filename}.{extension}',
  'Category / Subcategory / Filename':
      '{category}/{subcategory}/{filename}.{extension}',
  'Category / Num - Filename':
      '{category}/{num:>03}_{filename}.{extension}',
};

/// Subtitle language presets.
const kSubtitleLangPresets = ['en', 'en,es', 'en,fr', 'en,de', 'en,ja', 'all'];

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
  String? _cookieFilePath;

  // Network
  String? _proxyUrl;
  String? _rateLimit;
  String? _sourceAddress;

  // Post-processing
  bool _embedThumbnail = true;
  bool _embedMetadata = true;
  bool _embedSubs = false;
  String _subLangs = 'en';
  bool _sponsorBlock = false;
  bool _extractAudio = false;
  String _audioFormat = 'mp3';
  String? _videoFormat;

  // gallery-dl
  String _galleryDlTemplate = kDefaultGalleryDlTemplate;

  ThemeMode get themeMode => _themeMode;
  String get outputDir => _outputDir;
  String get filenameTemplate => _filenameTemplate;
  String get playlistTemplate => _playlistTemplate;
  String? get cookieFilePath => _cookieFilePath;

  String? get proxyUrl => _proxyUrl;
  String? get rateLimit => _rateLimit;
  String? get sourceAddress => _sourceAddress;

  bool get embedThumbnail => _embedThumbnail;
  bool get embedMetadata => _embedMetadata;
  bool get embedSubs => _embedSubs;
  String get subLangs => _subLangs;
  bool get sponsorBlock => _sponsorBlock;
  bool get extractAudio => _extractAudio;
  String get audioFormat => _audioFormat;
  String? get videoFormat => _videoFormat;
  String get galleryDlTemplate => _galleryDlTemplate;

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

  void setEmbedThumbnail(bool value) {
    if (_embedThumbnail == value) return;
    _embedThumbnail = value;
    notifyListeners();
    _save();
  }

  void setEmbedMetadata(bool value) {
    if (_embedMetadata == value) return;
    _embedMetadata = value;
    notifyListeners();
    _save();
  }

  void setEmbedSubs(bool value) {
    if (_embedSubs == value) return;
    _embedSubs = value;
    notifyListeners();
    _save();
  }

  void setSubLangs(String value) {
    if (_subLangs == value) return;
    _subLangs = value;
    notifyListeners();
    _save();
  }

  void setSponsorBlock(bool value) {
    if (_sponsorBlock == value) return;
    _sponsorBlock = value;
    notifyListeners();
    _save();
  }

  void setExtractAudio(bool value) {
    if (_extractAudio == value) return;
    _extractAudio = value;
    notifyListeners();
    _save();
  }

  void setAudioFormat(String value) {
    if (_audioFormat == value) return;
    _audioFormat = value;
    notifyListeners();
    _save();
  }

  void setVideoFormat(String? value) {
    if (_videoFormat == value) return;
    _videoFormat = value;
    notifyListeners();
    _save();
  }

  void setGalleryDlTemplate(String value) {
    if (_galleryDlTemplate == value) return;
    _galleryDlTemplate = value;
    notifyListeners();
    _save();
  }

  void setProxyUrl(String? value) {
    final v = (value != null && value.trim().isEmpty) ? null : value;
    if (_proxyUrl == v) return;
    _proxyUrl = v;
    notifyListeners();
    _save();
  }

  void setRateLimit(String? value) {
    final v = (value != null && value.trim().isEmpty) ? null : value;
    if (_rateLimit == v) return;
    _rateLimit = v;
    notifyListeners();
    _save();
  }

  void setSourceAddress(String? value) {
    final v = (value != null && value.trim().isEmpty) ? null : value;
    if (_sourceAddress == v) return;
    _sourceAddress = v;
    notifyListeners();
    _save();
  }

  void setCookieFilePath(String? path) {
    final value = (path != null && path.trim().isEmpty) ? null : path;
    if (_cookieFilePath == value) return;
    _cookieFilePath = value;
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
      _cookieFilePath = json['cookieFilePath'] as String?;
      _proxyUrl = json['proxyUrl'] as String?;
      _rateLimit = json['rateLimit'] as String?;
      _sourceAddress = json['sourceAddress'] as String?;
      _embedThumbnail = json['embedThumbnail'] as bool? ?? true;
      _embedMetadata = json['embedMetadata'] as bool? ?? true;
      _embedSubs = json['embedSubs'] as bool? ?? false;
      _subLangs = json['subLangs'] as String? ?? 'en';
      _sponsorBlock = json['sponsorBlock'] as bool? ?? false;
      _extractAudio = json['extractAudio'] as bool? ?? false;
      _audioFormat = json['audioFormat'] as String? ?? 'mp3';
      _videoFormat = json['videoFormat'] as String?;
      _galleryDlTemplate = json['galleryDlTemplate'] as String? ?? kDefaultGalleryDlTemplate;
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
        'cookieFilePath': _cookieFilePath,
        'proxyUrl': _proxyUrl,
        'rateLimit': _rateLimit,
        'sourceAddress': _sourceAddress,
        'embedThumbnail': _embedThumbnail,
        'embedMetadata': _embedMetadata,
        'embedSubs': _embedSubs,
        'subLangs': _subLangs,
        'sponsorBlock': _sponsorBlock,
        'extractAudio': _extractAudio,
        'audioFormat': _audioFormat,
        'videoFormat': _videoFormat,
        'galleryDlTemplate': _galleryDlTemplate,
      };
      await File(settingsPath).writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }
}

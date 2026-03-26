import 'dart:io';

/// Returns the app-specific support directory path per platform.
/// No external packages — uses known OS conventions.
String getAppSupportDir() {
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME']!;
    return '$home/Library/Application Support/com.crylo.media-dl';
  }
  if (Platform.isLinux) {
    final xdgData = Platform.environment['XDG_DATA_HOME'];
    if (xdgData != null && xdgData.isNotEmpty) {
      return '$xdgData/media-dl';
    }
    final home = Platform.environment['HOME']!;
    return '$home/.local/share/media-dl';
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['LOCALAPPDATA']!;
    return '$appData\\media-dl';
  }
  if (Platform.isAndroid) {
    // On Android we'll use app-internal storage.
    // This is a placeholder — will be refined when Android support is added.
    return '/data/data/com.crylo.media_dl/files';
  }
  throw UnsupportedError('Unsupported platform');
}

/// Returns the default download output directory.
String getDefaultOutputDir() {
  if (Platform.isAndroid) {
    // App-specific external storage — refined later
    return '/storage/emulated/0/Download/MediaDL';
  }
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  if (Platform.isWindows) {
    return '$home\\Downloads\\MediaDL';
  }
  return '$home/Downloads/MediaDL';
}

/// Ensures the app support directory and its bin/ subdirectory exist.
Future<void> ensureAppDirs(String appSupportDir) async {
  final binDir = Directory('$appSupportDir${Platform.pathSeparator}bin');
  if (!await binDir.exists()) {
    await binDir.create(recursive: true);
  }
}

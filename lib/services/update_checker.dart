import 'dart:convert';
import 'dart:io';

/// Result of checking for a newer release on GitHub.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.latestVersion,
    this.downloadUrl,
    this.assetUrl,
    this.error,
  });

  final String currentVersion;
  final String? latestVersion;

  /// HTML release page URL.
  final String? downloadUrl;

  /// Direct download URL for the platform-specific binary asset.
  final String? assetUrl;
  final String? error;

  bool get hasUpdate =>
      latestVersion != null && latestVersion != currentVersion;
}

/// Checks GitHub Releases for newer versions of a binary.
/// Uses dart:io HttpClient — no external HTTP packages.
class UpdateChecker {
  /// Check the latest release tag for a GitHub repo.
  /// [repo] should be like "yt-dlp/yt-dlp".
  Future<UpdateCheckResult> check({
    required String repo,
    required String currentVersion,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repo/releases/latest',
      );
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/vnd.github.v3+json');
      request.headers.set('User-Agent', 'MediaDL');

      final response = await request.close();
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: 'GitHub API returned ${response.statusCode}',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String?) ?? '';
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName;
      final htmlUrl = json['html_url'] as String?;

      // Find platform-specific asset
      final assets = (json['assets'] as List?) ?? [];
      final assetName = _platformAssetName(repo);
      String? assetUrl;
      if (assetName != null) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name == assetName) {
            assetUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }

      return UpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: htmlUrl,
        assetUrl: assetUrl,
      );
    } catch (e) {
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: 'Failed to check for updates: $e',
      );
    } finally {
      client.close();
    }
  }

  /// Download a file from [url] and save to [destPath].
  /// Returns null on success, or an error message on failure.
  Future<String?> downloadBinary(String url, String destPath) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'MediaDL');
      request.followRedirects = true;

      final response = await request.close();
      if (response.statusCode != 200) {
        return 'Download failed: HTTP ${response.statusCode}';
      }

      final file = File(destPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      await response.pipe(sink);

      // Set executable permission on Unix platforms
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', destPath]);
      }

      return null;
    } catch (e) {
      return 'Download failed: $e';
    } finally {
      client.close();
    }
  }

  /// Returns the expected GitHub Release asset filename for the current
  /// platform, or null if unsupported.
  static String? _platformAssetName(String repo) {
    if (repo == 'yt-dlp/yt-dlp') {
      if (Platform.isMacOS) return 'yt-dlp_macos';
      if (Platform.isLinux) return 'yt-dlp_linux';
      if (Platform.isWindows) return 'yt-dlp.exe';
      return null;
    }
    return null;
  }
}

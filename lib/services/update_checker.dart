import 'dart:convert';
import 'dart:io';

/// Result of checking for a newer release on GitHub.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.latestVersion,
    this.downloadUrl,
    this.error,
  });

  final String currentVersion;
  final String? latestVersion;
  final String? downloadUrl;
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

      return UpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: htmlUrl,
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
}

import 'package:media_dl/core/models.dart';

/// Parses gallery-dl stdout/stderr lines into structured [ParsedLine] objects.
///
/// gallery-dl output patterns (with --verbose):
///   /path/to/file.jpg                    — file downloaded
///   # /path/to/file.jpg                  — file skipped (already exists)
///   [extractor.name] ...                 — extractor info
///   [download] Downloading ...           — download start
///   [error] message                      — error
///   [warning] message                    — warning
class GalleryDlOutputParser {
  // [error] ...
  static final _errorRegex = RegExp(r'\[error\]\s+(.+)');

  // [warning] ...
  static final _warningRegex = RegExp(r'\[warning\]\s+(.+)');

  // # /path/to/file — skipped (already downloaded)
  static final _skippedRegex = RegExp(r'^#\s+(.+)$');

  // [download] ...
  static final _downloadInfoRegex = RegExp(r'^\[download\]\s+(.+)$');

  // [extractor...] ...
  static final _extractorRegex = RegExp(r'^\[extractor[^\]]*\]\s+(.+)$');

  /// Parse a single line of gallery-dl output.
  ParsedLine parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return const ParsedLine(type: ParsedLineType.other, message: '');
    }

    // Error
    final errorMatch = _errorRegex.firstMatch(trimmed);
    if (errorMatch != null) {
      return ParsedLine(
        type: ParsedLineType.error,
        message: errorMatch.group(1),
      );
    }

    // Warning
    final warningMatch = _warningRegex.firstMatch(trimmed);
    if (warningMatch != null) {
      return ParsedLine(
        type: ParsedLineType.warning,
        message: warningMatch.group(1),
      );
    }

    // Skipped / already downloaded
    final skippedMatch = _skippedRegex.firstMatch(trimmed);
    if (skippedMatch != null) {
      return ParsedLine(
        type: ParsedLineType.alreadyDownloaded,
        destinationPath: skippedMatch.group(1),
        message: trimmed,
      );
    }

    // Download info line
    if (_downloadInfoRegex.hasMatch(trimmed)) {
      return ParsedLine(
        type: ParsedLineType.info,
        message: trimmed,
      );
    }

    // Extractor info
    if (_extractorRegex.hasMatch(trimmed)) {
      return ParsedLine(
        type: ParsedLineType.info,
        message: trimmed,
      );
    }

    // Bracketed info lines
    if (trimmed.startsWith('[')) {
      return ParsedLine(
        type: ParsedLineType.info,
        message: trimmed,
      );
    }

    // Plain path — a file was downloaded
    // gallery-dl outputs the file path as a bare line on stdout
    if (trimmed.startsWith('/') || trimmed.contains(':\\')) {
      return ParsedLine(
        type: ParsedLineType.destination,
        destinationPath: trimmed,
        message: trimmed,
      );
    }

    return ParsedLine(type: ParsedLineType.other, message: trimmed);
  }
}

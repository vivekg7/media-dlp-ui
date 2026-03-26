import 'package:flutter_test/flutter_test.dart';
import 'package:media_dl/core/models.dart';
import 'package:media_dl/services/ytdlp_output_parser.dart';

void main() {
  late YtDlpOutputParser parser;

  setUp(() {
    parser = YtDlpOutputParser();
  });

  group('progress lines', () {
    test('parses standard progress line', () {
      final line =
          '[download]  45.2% of  150.23MiB at    5.23MiB/s ETA 00:12';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.progress);
      expect(result.progress, isNotNull);
      expect(result.progress!.percent, 45.2);
      expect(result.progress!.totalSize, '150.23MiB');
      expect(result.progress!.speed, '5.23MiB/s');
      expect(result.progress!.eta, '00:12');
    });

    test('parses 100% completion line', () {
      final line = '[download] 100% of  150.23MiB in 00:03:12';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.progress);
      expect(result.progress, isNotNull);
      expect(result.progress!.percent, 100.0);
      expect(result.progress!.totalSize, '150.23MiB');
      expect(result.progress!.speed, isNull);
      expect(result.progress!.eta, isNull);
    });

    test('parses progress line with approximate size (~)', () {
      final line =
          '[download]  12.5% of ~  200.00MiB at    3.00MiB/s ETA 00:55';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.progress);
      expect(result.progress!.percent, 12.5);
      expect(result.progress!.totalSize, '200.00MiB');
      expect(result.progress!.speed, '3.00MiB/s');
      expect(result.progress!.eta, '00:55');
    });

    test('parses progress with GiB size', () {
      final line =
          '[download]   1.0% of    2.50GiB at   10.00MiB/s ETA 04:15';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.progress);
      expect(result.progress!.percent, 1.0);
      expect(result.progress!.totalSize, '2.50GiB');
    });

    test('parses progress with KiB size', () {
      final line =
          '[download]  90.0% of  512.00KiB at  256.00KiB/s ETA 00:01';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.progress);
      expect(result.progress!.percent, 90.0);
      expect(result.progress!.totalSize, '512.00KiB');
    });
  });

  group('destination lines', () {
    test('parses destination line', () {
      final line =
          '[download] Destination: /home/user/Downloads/video.mp4';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.destination);
      expect(
          result.destinationPath, '/home/user/Downloads/video.mp4');
    });

    test('parses destination with spaces in path', () {
      final line =
          '[download] Destination: /home/user/My Downloads/my video.mp4';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.destination);
      expect(result.destinationPath,
          '/home/user/My Downloads/my video.mp4');
    });
  });

  group('already downloaded', () {
    test('parses already downloaded line', () {
      final line =
          '[download] /home/user/Downloads/video.mp4 has already been downloaded';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.alreadyDownloaded);
      expect(
          result.destinationPath, '/home/user/Downloads/video.mp4');
    });
  });

  group('error and warning lines', () {
    test('parses error line', () {
      final line = 'ERROR: Video unavailable. This video is private.';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.error);
      expect(result.message,
          'Video unavailable. This video is private.');
    });

    test('parses warning line', () {
      final line =
          'WARNING: Unable to download video subtitles: HTTP Error 404';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.warning);
      expect(result.message,
          'Unable to download video subtitles: HTTP Error 404');
    });
  });

  group('post-processing lines', () {
    test('parses merger line', () {
      final line =
          '[Merger] Merging formats into "/home/user/Downloads/video.mkv"';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.merging);
    });

    test('parses extract audio line', () {
      final line =
          '[ExtractAudio] Destination: /home/user/Downloads/audio.mp3';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.postProcess);
    });

    test('parses embed thumbnail line', () {
      final line = '[EmbedThumbnail] Adding thumbnail to "video.mp4"';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.postProcess);
    });

    test('parses sponsorblock line', () {
      final line =
          '[SponsorBlock] Skipping sponsor segment from 00:15 to 01:30';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.postProcess);
    });
  });

  group('playlist item lines', () {
    test('parses playlist item line', () {
      final line = '[download] Downloading item 3 of 15';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.playlistItem);
      expect(result.playlistItemIndex, 3);
      expect(result.playlistItemTotal, 15);
    });

    test('parses playlist item line with single item', () {
      final line = '[download] Downloading item 1 of 1';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.playlistItem);
      expect(result.playlistItemIndex, 1);
      expect(result.playlistItemTotal, 1);
    });
  });

  group('info and other lines', () {
    test('parses generic bracketed info line', () {
      final line =
          '[youtube] Extracting URL: https://www.youtube.com/watch?v=abc123';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.info);
      expect(result.message, line);
    });

    test('parses unrecognized line as other', () {
      final line = 'Some random output text';
      final result = parser.parseLine(line);

      expect(result.type, ParsedLineType.other);
      expect(result.message, line);
    });

    test('parses empty line as other', () {
      final result = parser.parseLine('');

      expect(result.type, ParsedLineType.other);
      expect(result.message, '');
    });

    test('parses whitespace-only line as other', () {
      final result = parser.parseLine('   ');

      expect(result.type, ParsedLineType.other);
      expect(result.message, '');
    });
  });

  group('real-world yt-dlp output sequence', () {
    test('parses a realistic download sequence', () {
      final lines = [
        '[youtube] Extracting URL: https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        '[youtube] dQw4w9WgXcQ: Downloading webpage',
        '[youtube] dQw4w9WgXcQ: Downloading ios player API JSON',
        '[info] dQw4w9WgXcQ: Downloading 1 format(s): 22',
        '[download] Destination: /home/user/Rick Astley - Never Gonna Give You Up.mp4',
        '[download]   0.0% of   50.23MiB at    1.00MiB/s ETA 00:50',
        '[download]  25.0% of   50.23MiB at    5.00MiB/s ETA 00:08',
        '[download]  50.0% of   50.23MiB at    5.50MiB/s ETA 00:05',
        '[download]  75.0% of   50.23MiB at    6.00MiB/s ETA 00:02',
        '[download] 100% of   50.23MiB in 00:00:10',
      ];

      final results = lines.map(parser.parseLine).toList();

      expect(results[0].type, ParsedLineType.info);
      expect(results[1].type, ParsedLineType.info);
      expect(results[2].type, ParsedLineType.info);
      expect(results[3].type, ParsedLineType.info);
      expect(results[4].type, ParsedLineType.destination);
      expect(results[5].type, ParsedLineType.progress);
      expect(results[5].progress!.percent, 0.0);
      expect(results[6].type, ParsedLineType.progress);
      expect(results[6].progress!.percent, 25.0);
      expect(results[9].type, ParsedLineType.progress);
      expect(results[9].progress!.percent, 100.0);
    });
  });
}

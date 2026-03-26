import 'package:flutter_test/flutter_test.dart';
import 'package:media_dl/services/process_runner.dart';

void main() {
  late ProcessRunner runner;

  setUp(() {
    runner = ProcessRunner();
  });

  test('runs a simple command and captures stdout', () async {
    final process = await runner.start('echo', ['hello world']);

    final lines = await process.stdout.toList();
    final exitCode = await process.exitCode;

    expect(exitCode, 0);
    expect(lines, contains('hello world'));
  });

  test('captures stderr output', () async {
    // Write to stderr via shell
    final process = await runner.start(
      'bash',
      ['-c', 'echo "error output" >&2'],
    );

    final stderrLines = await process.stderr.toList();
    final exitCode = await process.exitCode;

    expect(exitCode, 0);
    expect(stderrLines, contains('error output'));
  });

  test('reports non-zero exit code', () async {
    final process = await runner.start('bash', ['-c', 'exit 42']);

    final exitCode = await process.exitCode;
    expect(exitCode, 42);
  });

  test('can kill a long-running process', () async {
    final process = await runner.start('sleep', ['60']);

    // Give it a moment to start
    await Future.delayed(const Duration(milliseconds: 100));

    final killed = process.kill();
    expect(killed, isTrue);

    final exitCode = await process.exitCode;
    // Killed processes typically have a negative exit code or non-zero
    expect(exitCode, isNot(0));
  });

  test('exposes process ID', () async {
    final process = await runner.start('echo', ['test']);
    expect(process.pid, isPositive);
    await process.exitCode;
  });

  test('streams multiple stdout lines', () async {
    final process = await runner.start(
      'bash',
      ['-c', 'echo "line1"; echo "line2"; echo "line3"'],
    );

    final lines = await process.stdout.toList();
    final exitCode = await process.exitCode;

    expect(exitCode, 0);
    expect(lines, ['line1', 'line2', 'line3']);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of a completed process.
class ProcessResult {
  const ProcessResult({
    required this.exitCode,
    required this.pid,
  });

  final int exitCode;
  final int pid;
}

/// Abstract running process handle that exposes stdout/stderr streams and
/// cancellation. Both desktop (native) and Android (platform channel)
/// implementations conform to this interface.
abstract class RunningProcess {
  /// Stream of stdout lines.
  Stream<String> get stdout;

  /// Stream of stderr lines.
  Stream<String> get stderr;

  /// The OS process ID (or a synthetic ID on Android).
  int get pid;

  /// Kill the process. Returns true if the signal was successfully delivered.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);

  /// Future that completes with the exit code when the process exits.
  Future<int> get exitCode;
}

/// Desktop implementation of [RunningProcess] backed by dart:io [Process].
class NativeRunningProcess extends RunningProcess {
  NativeRunningProcess(this._process)
      : stdout = _process.stdout
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter()),
        stderr = _process.stderr
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter());

  final Process _process;

  @override
  final Stream<String> stdout;

  @override
  final Stream<String> stderr;

  @override
  int get pid => _process.pid;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }

  @override
  Future<int> get exitCode => _process.exitCode;
}

/// Starts and manages subprocesses with streaming output.
class ProcessRunner {
  /// Start a process and return a handle for streaming output and control.
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    return NativeRunningProcess(process);
  }
}

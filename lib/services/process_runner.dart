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

/// A running process handle that exposes stdout/stderr streams and cancellation.
class RunningProcess {
  RunningProcess._(this._process)
      : stdout = _process.stdout
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter()),
        stderr = _process.stderr
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter());

  final Process _process;

  /// Stream of stdout lines.
  final Stream<String> stdout;

  /// Stream of stderr lines.
  final Stream<String> stderr;

  /// The OS process ID.
  int get pid => _process.pid;

  /// Kill the process. Returns true if the signal was successfully delivered.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }

  /// Future that completes with the exit code when the process exits.
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
    return RunningProcess._(process);
  }
}

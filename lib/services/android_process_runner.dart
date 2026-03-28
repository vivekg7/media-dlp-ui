import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_dl/services/process_runner.dart';

/// Android implementation of [ProcessRunner] that delegates to the
/// youtubedl-android library via platform channels.
class AndroidProcessRunner extends ProcessRunner {
  static const _methodChannel = MethodChannel('com.crylo.media_dl/ytdlp');
  static int _counter = 0;

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final processId = 'dl_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';

    final eventChannel = EventChannel('com.crylo.media_dl/ytdlp_output/$processId');

    // Start execution on the Kotlin side (returns immediately).
    await _methodChannel.invokeMethod('execute', {
      'processId': processId,
      'arguments': arguments,
    });

    return AndroidRunningProcess(
      processId: processId,
      eventChannel: eventChannel,
    );
  }
}

/// Android implementation of [RunningProcess] backed by platform channels.
class AndroidRunningProcess extends RunningProcess {
  AndroidRunningProcess({
    required this.processId,
    required EventChannel eventChannel,
  }) {
    final stdoutController = StreamController<String>.broadcast();
    final stderrController = StreamController<String>.broadcast();
    final exitCompleter = Completer<int>();

    eventChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map;
      switch (map['type']) {
        case 'stdout':
          stdoutController.add(map['data'] as String);
        case 'stderr':
          stderrController.add(map['data'] as String);
        case 'exit':
          if (!exitCompleter.isCompleted) {
            exitCompleter.complete(map['code'] as int);
          }
          stdoutController.close();
          stderrController.close();
      }
    }, onError: (Object e) {
      if (!exitCompleter.isCompleted) exitCompleter.complete(-1);
      stdoutController.close();
      stderrController.close();
    });

    stdout = stdoutController.stream;
    stderr = stderrController.stream;
    exitCode = exitCompleter.future;
  }

  final String processId;

  @override
  late final Stream<String> stdout;

  @override
  late final Stream<String> stderr;

  @override
  int get pid => processId.hashCode;

  @override
  late final Future<int> exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    AndroidProcessRunner._methodChannel
        .invokeMethod('destroy', {'processId': processId});
    return true;
  }
}

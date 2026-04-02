import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'colony_stream_event.dart';

class ColonyLogStream {
  final Process _process;
  final Stream<ColonyStreamEvent> events;

  ColonyLogStream._(this._process, this.events);

  factory ColonyLogStream.fromProcess(Process process) {
    final controller = StreamController<ColonyStreamEvent>.broadcast();

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) => controller.add(ColonyStreamEvent.fromLine(line)),
      onError: controller.addError,
    );
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) => controller.add(
        ColonyStreamEvent.diagnostic(
          line.trim(),
          rawLine: '[stderr] $line',
          error: true,
        ),
      ),
      onError: controller.addError,
    );
    process.exitCode.then((code) {
      if (!controller.isClosed) {
        controller.add(ColonyStreamEvent.processExit(code));
        controller.close();
      }
    });

    return ColonyLogStream._(process, controller.stream);
  }

  void stop() {
    _process.kill(ProcessSignal.sigterm);
  }
}

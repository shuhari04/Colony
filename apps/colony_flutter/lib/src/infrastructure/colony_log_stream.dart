import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ColonyLogStream {
  final Process _process;
  final Stream<String> lines;

  ColonyLogStream._(this._process, this.lines);

  factory ColonyLogStream.fromProcess(Process process) {
    final controller = StreamController<String>.broadcast();

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      controller.add,
      onError: controller.addError,
    );
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) => controller.add('[stderr] $line'),
      onError: controller.addError,
    );
    process.exitCode.then((code) {
      if (!controller.isClosed) {
        controller.add('[process exited $code]');
        controller.close();
      }
    });

    return ColonyLogStream._(process, controller.stream);
  }

  void stop() {
    _process.kill(ProcessSignal.sigterm);
  }
}

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../model/board.dart';

class BoardSnapshotStore {
  const BoardSnapshotStore();

  Future<BoardSnapshot> load() async {
    try {
      final file = await _snapshotFile();
      if (!await file.exists()) {
        return const BoardSnapshot();
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return const BoardSnapshot();
      }
      return BoardSnapshot.decode(raw);
    } catch (_) {
      return const BoardSnapshot();
    }
  }

  Future<void> save(BoardSnapshot snapshot) async {
    final file = await _snapshotFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(snapshot.encode());
  }

  Future<File> _snapshotFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/board_layout.json');
  }
}

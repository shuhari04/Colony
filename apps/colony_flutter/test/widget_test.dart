import 'package:flutter_test/flutter_test.dart';
import 'package:colony_flutter/src/infrastructure/colony_command_adapter.dart';
import 'package:colony_flutter/src/infrastructure/colony_stream_event.dart';

void main() {
  test('parses session summary json', () {
    final summary = ColonySessionSummary.fromJson(const {
      'address': '@local:codex1',
      'node': 'local',
      'name': 'codex1',
      'provider': 'codex',
      'kind': 'codex',
      'model': 'gpt-5.2',
      'state': 'running',
      'backend': 'local_tmux',
    });

    expect(summary.address, '@local:codex1');
    expect(summary.provider, 'codex');
    expect(summary.kind, 'codex');
    expect(summary.model, 'gpt-5.2');
  });

  test('parses provider summary json', () {
    final summary = ColonyProviderSummary.fromJson(const {
      'id': 'claude',
      'displayName': 'Claude',
      'available': true,
    });

    expect(summary.id, 'claude');
    expect(summary.displayName, 'Claude');
    expect(summary.available, isTrue);
  });

  test('parses transcript event line', () {
    final event = ColonyStreamEvent.fromLine(
      '{"kind":"assistant_message","text":"hello","label":"Codex"}',
    );

    expect(event.kind, ColonyStreamEventKind.assistantMessage);
    expect(event.text, 'hello');
    expect(event.label, 'Codex');
  });
}

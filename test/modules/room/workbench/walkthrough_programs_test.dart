@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/walkthrough_programs.dart';

String get source => File(
        'workbench/backend/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/monty_gui_demo.py')
    .readAsStringSync();

void main() {
  test('only the byte-identical curated source can run or receive events',
      () async {
    expect(WalkthroughPrograms.accepts(source), isTrue);
    var runs = 0;
    final events = <String>[];
    var code = source;
    final controls = ProgramControls(
        source: () => code,
        run: () async {
          runs++;
        },
        event: (name) async {
          events.add(name);
        });
    await WalkthroughPrograms.perform(controls, 'run');
    await WalkthroughPrograms.perform(controls, 'plus');
    for (final other in [
      'print(42)',
      '$source\n# model repair',
      '',
      source.replaceFirst('count = 3', 'count = 99')
    ]) {
      code = other;
      expect(WalkthroughPrograms.accepts(code), isFalse);
      expect(
          () => WalkthroughPrograms.perform(controls, 'run'), throwsStateError);
      expect(() => WalkthroughPrograms.perform(controls, 'plus'),
          throwsStateError);
    }
    expect(runs, 1);
    expect(events, ['plus']);
  });
}

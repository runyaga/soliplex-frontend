import 'package:dart_monty/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/src/python_ui.dart';

void main() {
  test('workbench file host functions await the thread transport', () async {
    final disk = <String, String>{'team-survey.csv': 'color\nBlue\n'};
    final arena = PythonUiArena(
      workbenchEnabled: true,
      readFile: (name) async => disk[name] ?? '',
      writeFile: (name, text) async {
        disk[name] = text;
      },
    );
    final module = PythonUiArena.moduleFor(() => arena);
    final workbench = module.attrs['workbench']! as ExternalModule;
    final read = workbench.attrs['read_file']! as MontyHostFunction;
    final write = workbench.attrs['write_file']! as MontyHostFunction;
    expect(
      (await read.fn([const MontyString('team-survey.csv')], {})).dartValue,
      contains('Blue'),
    );
    await write.fn([
      const MontyString('notes.md'),
      const MontyString('Keep me'),
    ], {});
    expect(
      (await read.fn([const MontyString('notes.md')], {})).dartValue,
      'Keep me',
    );
    expect(arena.workbench.actions, isEmpty);
  });

  test('file access fails closed outside a thread host', () async {
    final module = PythonUiArena.moduleFor(PythonUiArena.new);
    final workbench = module.attrs['workbench']! as ExternalModule;
    final read = workbench.attrs['read_file']! as MontyHostFunction;
    await expectLater(
      Future.sync(() => read.fn([const MontyString('notes.md')], {})),
      throwsA(isA<ExternalException>()),
    );
  });
}

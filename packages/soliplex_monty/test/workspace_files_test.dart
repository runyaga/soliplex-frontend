import 'package:dart_monty/dart_monty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_monty/src/workspace_files.dart';

import 'support/monty.dart';

const _pathlib = 'from pathlib import Path\nPath';
const _sales = 'month,region,revenue\n2026-01,North,10.5\n2026-01,South,\n';

void main() {
  group('workspaceOsHandler in Monty', () {
    late MontyStarter starter;
    late MontyRuntime runtime;
    late OsHandler os;

    setUp(() async {
      starter = MontyStarter();
      runtime = await starter(const ResourceLimits(), const {});
      os = workspaceOsHandler(
        workspaceFiles([
          {'name': 'sales.csv', 'content': _sales},
        ]),
      );
    });

    tearDown(() => starter.close());

    Future<Object?> run(String code) async {
      try {
        return (await runtime.execute(code, os: os).result).dartValue;
      } on MontyError catch (error) {
        return '${error.exception.excType}: ${error.exception.message}';
      }
    }

    test(
      'a mounted file is readable with open and csv',
      () async {
        final result = await run('''
import csv
with open("/workspace/room/sales.csv") as f:
    rows = list(csv.reader(f.read().splitlines()))
skipped = 0
total = 0.0
for row in rows[1:]:
    try:
        total += float(row[2])
    except ValueError:
        skipped += 1
[len(rows), total, skipped]
''');

        expect(result, [3, 10.5, 1]);
      },
      skip: skipWithoutMonty,
    );

    test(
      'a path outside the workspace is refused',
      () async {
        for (final path in [
          '/etc/passwd',
          '/workspace/room/../../etc/passwd',
          'sales.csv',
        ]) {
          final result = await run('open("$path").read()');
          expect(result, startsWith('PermissionError'), reason: path);
          expect(result, contains('Errno 13'), reason: path);
        }
      },
      skip: skipWithoutMonty,
    );

    test(
      'writes are refused',
      () async {
        for (final code in [
          'open("/workspace/room/sales.csv", "w").write("x")',
          'open("/workspace/room/new.csv", "a")',
          '$_pathlib("/workspace/room/sub").mkdir()',
          '$_pathlib("/workspace/room/sales.csv").write_text("x")',
          '$_pathlib("/workspace/room/sales.csv").unlink()',
        ]) {
          final result = await run(code);
          expect(result, startsWith('PermissionError'), reason: code);
          expect(result, contains('Errno 30'), reason: code);
        }
        expect(
          await run('open("/workspace/room/sales.csv").read()'),
          _sales,
        );
      },
      skip: skipWithoutMonty,
    );
  });
}

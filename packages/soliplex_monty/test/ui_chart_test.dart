import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:dart_monty/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_monty/src/python_ui.dart';

void main() {
  late PythonUiArena arena;
  late ExternalModule ui;
  setUp(() {
    arena = PythonUiArena();
    ui = PythonUiArena.moduleFor(() => arena);
  });
  Future<Object?> call(
    String name,
    List<Object?> args, [
    Map<String, Object?> kwargs = const {},
  ]) async {
    final parts = name.split('.');
    final module = parts.length == 1
        ? ui
        : ui.attrs[parts.first]! as ExternalModule;
    return (await (module.attrs[parts.last]! as MontyHostFunction).fn(
      args.map(MontyValue.fromDart).toList(),
      kwargs.map((k, v) => MapEntry(k, MontyValue.fromDart(v))),
    )).dartValue;
  }

  test('graphics bars embed and wire the same default event context', () async {
    final event = await call('Event', [
      'pick',
      {'extra': 42},
    ]);
    final chart = await call(
      'graphics.Chart',
      [
        {
          'kind': 'bar',
          'points': [
            {'id': 'north', 'label': 'North', 'value': 80},
          ],
        },
        <String>[],
        'Regions',
      ],
      {'action': event, 'id': 'regions'},
    );
    final root = await call('Card', [chart]);
    await call('show', [root]);
    final node = arena.staged!.components.last;
    expect(node['selected'], {'@path': '/_ui/regions/label'});
    expect(((node['action']! as Map)['event'] as Map)['context'], {
      'extra': 42,
      'label': {'@path': '/_ui/regions/label'},
    });
    expect(node['@catalogId'], chartGraphicsCatalogId);
  });

  test('ui bars accept values up to 2^53 - 1 and reject larger ones', () async {
    // Matches the server rule; dart2js treats 1e100 as an int, the VM does not.
    final ok = await call('BarChart', [
      [
        {'label': 'Max', 'value': 9007199254740991},
        {'label': 'Half', 'value': 0.5},
      ],
      '',
    ]);
    await call('show', [ok]);
    validateStaticChartSpec(arena.staged!.components.single['spec']);
    for (final value in [9007199254740992, 1e100]) {
      final big = await call('BarChart', [
        [
          {'label': 'Big', 'value': value},
        ],
        '',
      ]);
      await expectLater(
        call('show', [big]),
        throwsA(isA<ExternalException>()),
        reason: '$value',
      );
    }
  });

  testWidgets('ui bars lower to Chart and preserve selection context', (
    tester,
  ) async {
    final action = await call('Event', [
      'pick',
      {'extra': 42},
    ]);
    final chart = await call(
      'BarChart',
      [
        [
          {'label': 12, 'value': 80},
          {'label': 'South', 'value': 76},
        ],
        'Regions',
        action,
        2,
      ],
      {'id': 'regions'},
    );
    final root = await call('Column', [
      [chart],
    ]);
    await call('show', [root]);
    final staged = arena.staged!;
    final node = staged.components.last;
    expect(node['component'], 'Chart');
    expect(node['@catalogId'], chartGraphicsCatalogId);
    expect(node['weight'], 2);
    expect(node['selected'], {'@path': '/_ui/regions/label'});
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [basicCatalog(), chartGraphicsCatalog()],
      validationConfig: ValidationConfig.strict,
    );
    addTearDown(processor.dispose);
    processor.processMessages(staged.messages('ui'));
    final events = <Map<String, Object?>>[];
    processor.model.onAction.subscribe((a) => events.add(a.toJson()));
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: A2uiSurface(surface: processor.model.allSurfaces.single),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chart-bar:12')));
    await tester.pumpAndSettle();
    expect(events.single['name'], 'pick');
    expect(events.single['context'], {'extra': 42, 'label': '12'});
    expect(
      processor.model.allSurfaces.single.dataModel.get('/_ui/regions/label'),
      '12',
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'ui line keeps six series, 500 labels, signed values and gaps',
    () async {
      final labels = [for (var i = 0; i < 500; i++) 'Day $i'];
      final chart = await call('LineChart', [
        labels,
        [
          for (var i = 0; i < 6; i++)
            {
              'label': 'Series $i',
              'values': [
                for (var j = 0; j < 500; j++)
                  if (j.isOdd) null else -j,
              ],
            },
        ],
        'History',
      ]);
      await call('show', [chart]);
      final node = arena.staged!.components.single;
      expect(node['component'], 'Chart');
      final series = (node['spec']! as Map)['series'] as List;
      expect(series, hasLength(6));
      final points = (series.first as Map)['points'] as List;
      expect(points, hasLength(500));
      expect((points[1] as Map)['value'], isNull);
      expect((points[2] as Map)['value'], -2);
      validateStaticChartSpec(node['spec']);
    },
  );

  test('invalid ui line still explains the label/value contract', () async {
    for (final labels in [
      <String>['only'],
      List.filled(501, 'day'),
    ]) {
      final chart = await call('LineChart', [
        labels,
        [
          {'label': 'Visits', 'values': List.filled(labels.length, 1)},
        ],
      ]);
      await expectLater(
        call('show', [chart]),
        throwsA(
          isA<ExternalException>().having(
            (e) => e.toString(),
            'message',
            contains('2 to 500 labels'),
          ),
        ),
      );
    }
  });
}

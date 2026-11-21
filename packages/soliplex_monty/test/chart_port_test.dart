// Pure Dart: no Monty worker.
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:dart_monty/core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

Future<Object?> _call(
  PythonUiArena arena,
  String name, [
  List<Object?> args = const [],
  Map<String, Object?> kwargs = const {},
]) async {
  final module = PythonUiArena.moduleFor(() => arena);
  final target = name == 'Chart'
      ? (module.attrs['graphics']! as ExternalModule).attrs['Chart']
      : module.attrs[name];
  final result = await (target! as MontyHostFunction).fn(
    [for (final a in args) MontyValue.fromDart(a)],
    {
      for (final MapEntry(:key, :value) in kwargs.entries)
        key: MontyValue.fromDart(value),
    },
  );
  return result.dartValue;
}

Future<String> _raised(Future<Object?> Function() body) async {
  try {
    await body();
  } on ExternalException catch (e) {
    return '${e.excType}: ${e.message}';
  }
  fail('no ExternalException');
}

const Map<String, Object> _spec = {
  'kind': 'scatter',
  'series': [
    {
      'id': 'profile',
      'points': [
        {'id': 'a', 'x': 0, 'y': 0},
        {'id': 'b', 'x': 2, 'y': 60},
      ],
    },
  ],
};

void main() {
  for (final height in [50, 1201]) {
    test('Chart rejects height $height before staging', () async {
      final arena = PythonUiArena();
      expect(
        await _raised(
          () => _call(arena, 'Chart', [_spec, <Object?>[], 'Profile', height]),
        ),
        contains('height'),
      );
      expect(arena.staged, isNull);
    });
  }
  test('Chart rejects an empty description before staging', () async {
    final arena = PythonUiArena();
    expect(
      await _raised(() => _call(arena, 'Chart', [_spec, <Object?>[], ''])),
      contains('description'),
    );
    expect(arena.staged, isNull);
  });
  test('literal handle-like text survives properties and data', () async {
    final arena = PythonUiArena();
    final text = await _call(arena, 'Text', ['<ui:hello>']);
    await _call(arena, 'show', [
      text,
      {'text': '<ui:hello>'},
    ]);
    expect(arena.staged!.components.single['text'], '<ui:hello>');
    expect(arena.staged!.dataModel, {'text': '<ui:hello>'});
  });
  test('concatenated current handle is literal text', () async {
    final arena = PythonUiArena();
    final bind = await _call(arena, 'bind', ['/x']);
    final text = await _call(arena, 'Text', ['value: $bind']);
    await _call(arena, 'show', [text]);
    expect(arena.staged!.components.single['text'], 'value: $bind');
  });
  test('stale exact handles are rejected', () async {
    final old = await _call(PythonUiArena(), 'bind', ['/x']);
    final arena = PythonUiArena();
    final text = await _call(arena, 'Text', [old]);
    expect(
      await _raised(() => _call(arena, 'show', [text])),
      contains('earlier run'),
    );
    final root = await _call(arena, 'Text', ['x']);
    expect(
      await _raised(
        () => _call(arena, 'show', [
          root,
          {'v': old},
        ]),
      ),
      contains('plain values'),
    );
  });
  test('explicit IDs cannot collide with generated IDs', () async {
    final arena = PythonUiArena();
    final first = await _call(arena, 'Text', ['first'], {'id': 'n1'});
    final second = await _call(arena, 'Text', ['second']);
    final root = await _call(arena, 'Column', [
      [first, second],
    ]);
    await _call(arena, 'show', [root]);
    expect(arena.staged!.components.map((c) => c['id']).toSet(), hasLength(3));
  });
  test('explicit IDs reject the reserved generated namespace', () async {
    final arena = PythonUiArena();
    expect(
      await _raised(() => _call(arena, 'Text', ['x'], {'id': 'monty_anon_0'})),
      startsWith('ValueError'),
    );
  });

  test('a lone Chart keeps the graphics surface', () async {
    final arena = PythonUiArena();
    final chart = await _call(arena, 'Chart', [_spec, <Object?>[], 'Profile']);
    await _call(arena, 'show', [chart]);
    final create = arena.staged!.messages('s').first['createSurface']! as Map;
    expect(create['catalogId'], chartGraphicsCatalogId);
  });

  testWidgets('a Chart renders beside a form in a basic surface', (
    tester,
  ) async {
    final arena = PythonUiArena();
    final title = await _call(arena, 'Text', ['Dive profile']);
    final chart = await _call(arena, 'Chart', [_spec, <Object?>[], 'Profile']);
    final column = await _call(arena, 'Column', [
      [title, chart],
    ]);
    await _call(arena, 'show', [column]);
    final messages = arena.staged!.messages('s');
    expect(
      (messages.first['createSurface']! as Map)['catalogId'],
      BasicCatalog.v1_0Id,
    );
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [basicCatalog(), chartGraphicsCatalog()],
      validationConfig: ValidationConfig.strict,
    )..processMessages(messages);
    addTearDown(processor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: A2uiSurface(surface: processor.model.allSurfaces.single),
          ),
        ),
      ),
    );
    expect(find.text('Dive profile'), findsOneWidget);
    expect(find.byType(ScatterChart), findsOneWidget);
  });

  testWidgets('a Chart in a horizontal List lays out at a finite width', (
    tester,
  ) async {
    final arena = PythonUiArena();
    final title = await _call(arena, 'Text', ['Dive profile']);
    final chart = await _call(arena, 'Chart', [_spec, <Object?>[], 'Profile']);
    final row = await _call(
      arena,
      'List',
      [
        [title, chart],
      ],
      {'direction': 'horizontal'},
    );
    await _call(arena, 'show', [row]);
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [basicCatalog(), chartGraphicsCatalog()],
      validationConfig: ValidationConfig.strict,
    )..processMessages(arena.staged!.messages('s'));
    addTearDown(processor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: A2uiSurface(surface: processor.model.allSurfaces.single),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ScatterChart), findsOneWidget);
  });

  testWidgets('a reversed, highlighted single point renders', (tester) async {
    final arena = PythonUiArena();
    final chart = await _call(arena, 'Chart', [
      {
        'kind': 'scatter',
        'y_reversed': true,
        'series': [
          {
            'id': 's',
            'line': true,
            'points': [
              {'id': 'p', 'x': 1, 'y': 60, 'highlight': true},
            ],
          },
          {'id': 'empty', 'line': true, 'points': <Object?>[]},
        ],
      },
      <Object?>[],
      'One point',
    ]);
    await _call(arena, 'show', [chart]);
    final processor = MessageProcessor<ComponentImplementation>(
      catalogs: [chartGraphicsCatalog()],
    )..processMessages(arena.staged!.messages('s'));
    addTearDown(processor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: A2uiSurface(surface: processor.model.allSurfaces.single),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(LineChart), findsOneWidget);
  });
}

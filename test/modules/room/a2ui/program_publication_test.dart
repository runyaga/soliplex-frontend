import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';

import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;

const _catalog = 'urn:soliplex:catalog:publication-test:1';

List<Map<String, Object?>> _publication(String source,
        {String surface = 'program'}) =>
    [
      {
        'version': '1.0',
        'createSurface': {'surfaceId': surface, 'catalogId': _catalog},
      },
      {
        'version': '1.0',
        'updateDataModel': {
          'surfaceId': surface,
          'path': '/',
          'value': {'source': source},
        },
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': surface,
          'components': [
            {
              'id': 'root',
              'component': 'PythonRepl',
              'source': {'@path': '/source'},
            },
          ],
        },
      },
    ];

// Runs on VM and Chrome. The actual Monty execution and globals are exercised
// by example/test/repair_publication_test.dart; this checks the shared mount.
void main() {
  testWidgets('full program publication keeps component State on VM and web',
      (tester) async {
    var mounts = 0;
    final store = ChatSurfaceStore(catalogs: [
      CatalogImplementation(
        id: _catalog,
        protocolVersion: A2uiProtocolVersion.v1_0,
        components: [
          ComponentImplementation(
            name: 'PythonRepl',
            schema: Schema.object(properties: {
              'source': CommonSchemasV1.dynamicString,
            }, required: [
              'source'
            ]),
            builder: (_, node, props, buildChild) => _Probe(
              key: ValueKey(node.instanceId),
              source: props.string('source')!,
              onMount: () => ++mounts,
            ),
          ),
        ],
      ),
    ]);
    addTearDown(store.dispose);
    final first = store.obtain('activity', _publication('original'));
    final surface = first.surfaces.single;
    Widget app() => MaterialApp(
          home: Scaffold(body: ChatSurfaceView(controller: store['activity']!)),
        );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(first.live, false);
    final repaired =
        store.obtain('activity', _publication('fixed'), live: true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(repaired, same(first));
    expect(repaired.surfaces.single, same(surface));
    expect(repaired.live, true);
    expect(mounts, 1);
    expect(find.text('fixed'), findsOneWidget);
    final replay = repaired.snapshot()['messages']! as List;
    expect((replay[1]['updateDataModel']['value'] as Map)['source'], 'fixed');
    // Changing surface identity deliberately resets mounted state.
    final unrelated = store.obtain(
      'activity',
      _publication('unrelated', surface: 'new-program'),
      live: true,
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(unrelated, isNot(same(first)));
    expect(mounts, 2);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.source, required this.onMount, super.key});
  final String source;
  final VoidCallback onMount;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => Text(widget.source);
}

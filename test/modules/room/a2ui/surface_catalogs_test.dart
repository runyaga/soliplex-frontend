import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_controller.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/gen_ui_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';

const _catalogId = 'urn:soliplex:catalog:test:1';

/// A catalog with one `Greeting` component that renders its bound name.
CatalogImplementation _greetingCatalog() => CatalogImplementation(
      id: _catalogId,
      protocolVersion: A2uiProtocolVersion.v1_0,
      components: [
        ComponentImplementation(
          name: 'Greeting',
          schema: Schema.object(
            properties: {'name': CommonSchemasV1.dynamicString},
            required: ['name'],
          ),
          builder: (context, node, props, buildChild) =>
              Text('Hello ${props.string('name')}'),
        ),
      ],
    );

/// A surface whose root is the custom `Greeting` component.
List<Map<String, Object?>> _greetingMessages() => [
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 'greet',
          'catalogId': BasicCatalog.v1_0Id,
        },
      },
      {
        'version': '1.0',
        'updateDataModel': {
          'surfaceId': 'greet',
          'path': '/',
          'value': {'who': 'dojo'},
        },
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': 'greet',
          'components': [
            {
              'id': 'root',
              'component': 'Greeting',
              'catalogId': _catalogId,
              'name': {'@path': '/who'},
            },
          ],
        },
      },
    ];

GenUiMessage _generated() => GenUiMessage.create(
      id: 'surface-message',
      widgetName: 'a2ui',
      data: {'messages': _greetingMessages()},
    );

Widget _app(Widget child) => ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('a registered catalog renders its component', (tester) async {
    final controller = ChatSurfaceController(catalogs: [_greetingCatalog()]);
    addTearDown(controller.dispose);
    controller.apply(_greetingMessages());

    await tester.pumpWidget(_app(ChatSurfaceView(controller: controller)));
    await tester.pumpAndSettle();

    expect(controller.error, isNull);
    expect(find.text('Hello dojo'), findsOneWidget);
  });

  testWidgets('a component from an unregistered catalog does not render', (
    tester,
  ) async {
    final controller = ChatSurfaceController();
    addTearDown(controller.dispose);
    try {
      controller.apply(_greetingMessages());
    } on Object catch (error) {
      controller.error = '$error';
    }

    await tester.pumpWidget(_app(ChatSurfaceView(controller: controller)));
    await tester.pumpAndSettle();

    expect(controller.error, isNotNull);
    expect(find.text('Hello dojo'), findsNothing);
  });

  test('a store builds every controller with its catalogs', () {
    final catalogs = [_greetingCatalog()];
    final store = ChatSurfaceStore(catalogs: catalogs);
    addTearDown(store.dispose);

    final controller = store.obtain('message', _greetingMessages());

    expect(store.catalogs, same(catalogs));
    expect(controller.error, isNull);
    expect(controller.surfaces.single.id, 'greet');
    expect(store.obtain('message', _greetingMessages()), same(controller));
  });

  testWidgets('the timeline renders surfaces with its injected catalogs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MessageTimeline(
          roomId: 'r',
          messages: [_generated()],
          messageStates: const {},
          surfaceCatalogs: [_greetingCatalog()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GenUiTile), findsOneWidget);
    expect(find.text('Hello dojo'), findsOneWidget);
  });

  testWidgets('the timeline without catalogs shows the surface error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MessageTimeline(
          roomId: 'r',
          messages: [_generated()],
          messageStates: const {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello dojo'), findsNothing);
    expect(find.textContaining('Cannot render surface'), findsOneWidget);
  });
}

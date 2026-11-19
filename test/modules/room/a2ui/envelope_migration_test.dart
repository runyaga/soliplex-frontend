import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_controller.dart';

void main() {
  test('canonical component catalog key is accepted', () {
    final controller = ChatSurfaceController();
    addTearDown(controller.dispose);

    controller.apply([
      {
        'version': '1.0',
        'createSurface': {
          'surfaceId': 's',
          'catalogId': BasicCatalog.v1_0Id,
        },
      },
      {
        'version': '1.0',
        'updateComponents': {
          'surfaceId': 's',
          'components': [
            {
              'id': 'root',
              'component': 'Text',
              '@catalogId': BasicCatalog.v1_0Id,
              'text': 'canonical',
            },
          ],
        },
      },
    ]);

    expect(controller.error, isNull);
    expect(controller.surfaces.single.id, 's');
  });

  test('duplicate canonical and legacy component catalog keys fail', () {
    final controller = ChatSurfaceController();
    addTearDown(controller.dispose);

    expect(
      () => controller.apply([
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 's',
            'catalogId': BasicCatalog.v1_0Id,
          },
        },
        {
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 's',
            'components': [
              {
                'id': 'root',
                'component': 'Text',
                '@catalogId': BasicCatalog.v1_0Id,
                'catalogId': BasicCatalog.v1_0Id,
                'text': 'ambiguous',
              },
            ],
          },
        },
      ]),
      throwsA(isA<A2uiValidationError>()),
    );
  });
}

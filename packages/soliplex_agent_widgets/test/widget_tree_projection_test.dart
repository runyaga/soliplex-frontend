import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent_widgets/soliplex_agent_widgets.dart';

void main() {
  group('WidgetTreeProjection.project', () {
    const projection = WidgetTreeProjection();

    test('empty state -> empty list', () {
      expect(projection.project(const {}), isEmpty);
    });

    test('missing /ui -> empty list', () {
      expect(projection.project(const {'other': 1}), isEmpty);
    });

    test('non-Map /ui -> empty list', () {
      expect(projection.project(const {'ui': 'not-a-map'}), isEmpty);
    });

    test('non-List /ui/widgets -> empty list', () {
      expect(
        projection.project(const {
          'ui': {'widgets': 'not-a-list'},
        }),
        isEmpty,
      );
    });

    test('skips entries that are not Maps', () {
      final out = projection.project(const {
        'ui': {
          'widgets': [
            'string',
            42,
            null,
            {'name': 'InfoCard'},
          ],
        },
      });
      expect(out, hasLength(1));
      expect(out.single.name, 'InfoCard');
    });

    test('skips entries missing a string `name`', () {
      final out = projection.project(const {
        'ui': {
          'widgets': [
            {'data': <String, dynamic>{}},
            {'name': 123},
            {'name': 'StatChip'},
          ],
        },
      });
      expect(out, hasLength(1));
      expect(out.single.name, 'StatChip');
    });

    test('uses entry id when present, falls back to index otherwise', () {
      final out = projection.project(const {
        'ui': {
          'widgets': [
            {'id': 'first', 'name': 'A'},
            {'name': 'B'},
            {'id': 'third', 'name': 'C'},
          ],
        },
      });
      expect(out.map((w) => w.id), equals(['first', 'w-1', 'third']));
    });

    test('passes through Map data; coerces non-map data to empty', () {
      final out = projection.project(const {
        'ui': {
          'widgets': [
            {
              'name': 'WithData',
              'data': {'k': 'v'},
            },
            {'name': 'WithListData', 'data': <int>[]},
            {'name': 'NoData'},
          ],
        },
      });
      expect(out[0].data, equals({'k': 'v'}));
      expect(out[1].data, isEmpty);
      expect(out[2].data, isEmpty);
    });

    test('preserves entry order', () {
      final out = projection.project(const {
        'ui': {
          'widgets': [
            {'id': 'a', 'name': 'A'},
            {'id': 'b', 'name': 'B'},
            {'id': 'c', 'name': 'C'},
          ],
        },
      });
      expect(out.map((w) => w.id), equals(['a', 'b', 'c']));
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

Map<String, Object?> _bar(
  Object? value, {
  Map<String, Object?> extra = const {},
}) => {
  'kind': 'bar',
  'points': [
    {'id': 'a', 'label': 'A', 'value': value},
  ],
  ...extra,
};

/// dart2js represents ints as doubles and shifts in 32 bits, so a 64-bit
/// integer input cannot be built there.
const Object _dart2js = identical(0, 0.0)
    ? 'dart2js cannot represent this 64-bit integer'
    : false;

Matcher get _rejected => throwsA(isA<FormatException>());

void main() {
  group('safe numbers', () {
    test('rejects a whole double above the safe range on every backend', () {
      expect(
        () => validateStaticChartSpec(_bar(9007199254740992.0)),
        _rejected,
      );
    });

    test('rejects the most negative 64-bit integer', () {
      expect(() => validateStaticChartSpec(_bar(-1 << 63)), _rejected);
    }, skip: _dart2js);

    test('accepts the largest safe integer', () {
      validateStaticChartSpec(_bar(9007199254740991));
    });

    test('rejects an out-of-range scatter coordinate', () {
      expect(
        () => validateStaticChartSpec({
          'kind': 'scatter',
          'series': [
            {
              'id': 's',
              'points': [
                {'id': 'p', 'x': -1 << 63, 'y': 0},
              ],
            },
          ],
        }),
        _rejected,
      );
    }, skip: _dart2js);

    test('rejects a gauge outside the safe range', () {
      expect(
        () => validateStaticChartSpec({
          'kind': 'gauge',
          'min_value': 0,
          'max_value': 9007199254740992,
          'value': 9007199254740992,
        }),
        _rejected,
      );
    });
  });

  group('whole component', () {
    Map<String, Object?> component() => {
      'spec': _bar(1),
      'selection': <Object?>[],
      'description': 'Demo',
    };
    for (final required in ['selection', 'description']) {
      test('rejects missing $required', () {
        expect(
          () => validateChartComponent(component()..remove(required)),
          _rejected,
        );
      });
    }
    for (final entry in <String, List<Object?>>{
      'height': [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        159,
        1201,
      ],
      'description': ['', 'x' * 513, null],
      'selection': [
        null,
        ['a'],
      ],
    }.entries) {
      for (final value in entry.value) {
        test('rejects invalid ${entry.key}: $value', () {
          expect(
            () => validateChartComponent({...component(), entry.key: value}),
            _rejected,
          );
        });
      }
    }
    test('accepts optional height boundaries and does not mutate props', () {
      for (final height in [160, 1200]) {
        final props = {...component(), 'height': height};
        final before = jsonEncode(props);
        validateChartComponent(props);
        expect(jsonEncode(props), before);
      }
    });
  });

  test(
    'byte limit canonicalizes whole doubles without changing stored data',
    () {
      const limit = 1024 * 1024;
      final points = [
        for (var i = 0; i < 5000; i++) {'id': '$i', 'label': '', 'value': 1},
      ];
      final spec = {'kind': 'bar', 'points': points};
      var remaining = limit - utf8.encode(jsonEncode(spec)).length;
      for (final point in points) {
        final count = remaining.clamp(0, 512);
        point['label'] = 'x' * count;
        remaining -= count;
        point['value'] = 1.0;
      }
      expect(remaining, 0);
      validateStaticChartSpec(spec);
      expect(points.first['value'], isA<double>());
      points.last['label'] = '${points.last['label']}x';
      expect(() => validateStaticChartSpec(spec), _rejected);
    },
  );

  for (final bad in [
    double.nan,
    double.infinity,
    -9007199254740992.0,
    9007199254740992.0,
  ]) {
    for (final key in ['value', 'min_value', 'max_value', 'target']) {
      test('gauge rejects unsafe $key: $bad', () {
        expect(
          () => validateStaticChartSpec({
            'kind': 'gauge',
            'value': 5,
            'min_value': 0,
            'max_value': 10,
            'target': 6,
            key: bad,
          }),
          _rejected,
        );
      });
    }
    for (final spec in <Map<String, Object?>>[
      {
        'kind': 'line',
        'series': [
          {
            'id': 's',
            'points': [
              {'id': 'p', 'label': 'P', 'value': bad},
            ],
          },
        ],
      },
      {
        'kind': 'scatter',
        'series': [
          {
            'id': 's',
            'points': [
              {'id': 'p', 'x': bad, 'y': 0},
            ],
          },
        ],
      },
      {
        'kind': 'pie',
        'slices': [
          {'id': 'p', 'label': 'P', 'value': bad},
        ],
      },
      {
        'kind': 'radar',
        'axes': [
          for (final id in ['a', 'b', 'c']) {'id': id, 'label': id},
        ],
        'series': [
          {
            'id': 's',
            'values': [bad, 0, 0],
          },
        ],
      },
      {
        'kind': 'candlestick',
        'candles': [
          {'id': 'p', 'x': bad, 'open': 1, 'high': 2, 'low': 0, 'close': 1},
        ],
      },
    ]) {
      test('${spec['kind']} rejects unsafe number $bad', () {
        expect(() => validateStaticChartSpec(spec), _rejected);
      });
    }
  }

  group('schemas', () {
    test('rejects a bad bar colour', () {
      expect(
        () => validateStaticChartSpec(_bar(1, extra: {'color': 'bad'})),
        _rejected,
      );
    });

    test('rejects an unknown bar field', () {
      expect(
        () => validateStaticChartSpec(_bar(1, extra: {'colour': '#112233ff'})),
        _rejected,
      );
    });

    test('rejects an overlong line label', () {
      expect(
        () => validateStaticChartSpec({
          'kind': 'line',
          'series': [
            {
              'id': 's',
              'points': [
                {'id': 'p', 'label': 'x' * 513, 'value': 1},
              ],
            },
          ],
        }),
        _rejected,
      );
    });

    test('rejects a gauge with an unknown field', () {
      expect(
        () => validateStaticChartSpec({
          'kind': 'gauge',
          'min_value': 0,
          'max_value': 10,
          'value': 5,
          'needle': true,
        }),
        _rejected,
      );
    });
  });

  test('a non-string key is a FormatException', () {
    expect(
      () => validateStaticChartSpec({
        'kind': 'bar',
        'points': [
          {1: 'a', 'id': 'a', 'label': 'A', 'value': 1},
        ],
      }),
      _rejected,
    );
  });
}

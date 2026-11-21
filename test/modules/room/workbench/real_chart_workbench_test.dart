import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_controller.dart';
import 'package:soliplex_frontend/src/modules/room/a2ui/surface_view.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/layout_tree.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/workbench_host.dart';

import '../../../fixtures/workbench/workbench_fixtures.g.dart';

const _points = [
  {'id': 'north', 'label': 'North', 'value': 80.0},
  {'id': 'south', 'label': 'South', 'value': 60.0},
];
const _specs = <String, Map<String, Object>>{
  'bar': {'points': _points},
  'line': {
    'series': [
      {'id': 'counts', 'label': 'Counts', 'points': _points},
    ],
  },
  'pie': {'slices': _points},
  'gauge': {'value': 80, 'min_value': 0, 'max_value': 100},
  'scatter': {
    'series': [
      {
        'id': 'counts',
        'points': [
          {'id': 'north', 'x': 1, 'y': 80},
          {'id': 'south', 'x': 2, 'y': 60},
        ],
      },
    ],
  },
  'radar': {
    'axes': [
      {'id': 'a', 'label': 'A'},
      {'id': 'b', 'label': 'B'},
      {'id': 'c', 'label': 'C'},
    ],
    'series': [
      {
        'id': 'counts',
        'values': [80, 60, 40]
      },
    ],
  },
  'candlestick': {
    'candles': [
      {'id': 'a', 'x': 1, 'open': 10, 'high': 20, 'low': 5, 'close': 15},
      {'id': 'b', 'x': 2, 'open': 15, 'high': 18, 'low': 3, 'close': 8},
    ],
  },
};
const _plots = {
  'bar': 'BarChart',
  'line': 'LineChart',
  'pie': 'PieChart',
  'gauge': 'GaugeChart',
  'scatter': 'ScatterChart',
  'radar': 'RadarChart',
  'candlestick': 'CandlestickChart',
};

void main() {
  for (final kind in _specs.keys) {
    for (final placement in ['window', 'split', 'tabs', 'sidebar']) {
      testWidgets('$kind paints with finite bounds in $placement',
          (tester) async {
        tester.view.physicalSize = const Size(1800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        final controller = _controller(kind);
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(body: _host(controller, placement)),
        ));
        await tester.pumpAndSettle();
        expect(controller.error, isNull);
        if (kind == 'bar') {
          expect(
              find.bySemanticsLabel('bar chart: Counts; North: 80, South: 60'),
              findsOneWidget);
        }
        expect(find.bySemanticsLabel(RegExp('$kind chart: Counts;')),
            findsOneWidget);
        final plots = find
            .byWidgetPredicate((w) => w.runtimeType.toString() == _plots[kind]);
        expect(plots, findsWidgets);
        for (final plot in plots.evaluate()) {
          final size = tester.getSize(find.byWidget(plot.widget));
          expect(size.isFinite, isTrue);
          expect(size.width, greaterThan(0));
          expect(size.height, greaterThan(0));
        }
        semantics.dispose();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('short chart windows size to content for every semantic size',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _controller('bar');
    addTearDown(controller.dispose);
    final heights = <double>[];
    for (final size in ['small', 'medium', 'large']) {
      await tester.pumpWidget(MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(body: _host(controller, 'window', size: size)),
      ));
      await tester.pumpAndSettle();
      heights.add(tester.getSize(find.byKey(const ValueKey('owner'))).height);
      expect(tester.takeException(), isNull);
    }
    expect(heights.toSet(), hasLength(1));
    expect(heights.first, greaterThan(0));
    expect(heights.first, lessThan(SoliplexBreakpoints.mobile));
  });
}

ChatSurfaceController _controller(String kind) => ChatSurfaceController()
  ..apply([
    {
      'version': '1.0',
      'createSurface': {
        'surfaceId': 'chart',
        'catalogId': 'urn:soliplex:catalog:graphics:2'
      }
    },
    {
      'version': '1.0',
      'updateComponents': {
        'surfaceId': 'chart',
        'components': [
          {
            'id': 'root',
            'component': 'Chart',
            'selection': [],
            'description': 'Counts',
            'spec': {'kind': kind, 'title': 'Counts', ..._specs[kind]!}
          },
        ],
      },
    },
  ]);

Widget _host(ChatSurfaceController controller, String placement,
    {String size = 'medium'}) {
  final layout = jsonDecode(workbenchFixtures['layout_tree_v1.json']!)
      as Map<String, dynamic>;
  final nodes = (layout['nodes'] as List).cast<Map<String, dynamic>>();
  final region = placement == 'sidebar' ? 'r_right' : 'r_canvas';
  (nodes.singleWhere((n) => n['id'] == region)['children'] as List)
      .add('owner');
  final nested = placement == 'split' || placement == 'tabs';
  nodes.addAll([
    _node(
        'owner',
        region,
        [nested ? 'panel' : 'leaf'],
        placement == 'sidebar' ? 'panel' : placement,
        size,
        {if (placement == 'split') 'axis': 'horizontal'}),
    if (nested) _node('panel', 'owner', ['leaf'], 'panel', size, {}),
    _node('leaf', nested ? 'panel' : 'owner', [], 'surface', size,
        {'activityMessageId': 'activity', 'surfaceId': 'chart'}),
  ]);
  return WorkbenchHost(
    tree: LayoutTree.fromLayout(layout, [
      WorkbenchRegistration(
          role: WorkbenchRole.content,
          activityMessageId: 'activity',
          surfaceId: 'chart')
    ]),
    chat: const Text('Chat'),
    surfaceBuilder: (_, __) =>
        ChatSurfaceView(controller: controller, surfaceId: 'chart'),
    mounts: SurfaceMountRegistry(),
  );
}

Map<String, dynamic> _node(String id, String parent, List<String> children,
        String kind, String size, Map<String, dynamic> payload) =>
    {
      'id': id,
      'parentId': parent,
      'children': children,
      'kind': kind,
      'title': 'Counts',
      'size': size,
      'visibility': 'open',
      'payload': payload,
    };

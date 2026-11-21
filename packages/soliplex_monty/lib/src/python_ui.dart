import 'dart:math';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:dart_monty/core.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

import 'package:soliplex_monty/src/python_workbench.dart';
import 'package:soliplex_monty/src/ui_chart.dart';

/// Positional order of every v1.0 basic-catalog constructor, from the Track B
/// binding contract. Each name is also accepted as a keyword.
const basicSignatures = <String, List<String>>{
  'Text': ['text', 'variant', 'weight'],
  'Image': ['url', 'description', 'fit', 'variant', 'weight'],
  'Icon': ['name', 'weight'],
  'Video': ['url', 'posterUrl', 'weight'],
  'AudioPlayer': ['url', 'description', 'weight'],
  'Row': ['children', 'justify', 'align', 'weight'],
  'Column': ['children', 'justify', 'align', 'weight'],
  'List': ['children', 'direction', 'align', 'weight'],
  'Card': ['child', 'weight'],
  'Tabs': ['tabs', 'weight'],
  'Modal': ['trigger', 'content', 'weight'],
  'Divider': ['axis', 'weight'],
  'Button': ['child', 'variant', 'action', 'weight'],
  'TextField': ['label', 'value', 'placeholder', 'variant', 'weight'],
  'CheckBox': ['label', 'value', 'weight'],
  'ChoicePicker': [
    'label',
    'variant',
    'options',
    'value',
    'displayStyle',
    'filterable',
    'weight',
  ],
  'Slider': ['label', 'min', 'max', 'value', 'steps', 'weight'],
  'DateTimeInput': [
    'value',
    'enableDate',
    'enableTime',
    'min',
    'max',
    'label',
    'weight',
  ],
};

/// Bounds on what one execution may stage.
const _maxNodes = 20000;
const _maxPathLength = 200;

/// A surface staged by `ui.show`, published only after the run succeeds.
class StagedSurface {
  const StagedSurface(this.components, this.dataModel);

  final List<Map<String, Object?>> components;
  final Object? dataModel;

  /// Wire messages for surface [surfaceId] in the basic catalog.
  List<Map<String, Object?>> messages(String surfaceId) => [
    {
      'version': '1.0',
      'createSurface': {
        'surfaceId': surfaceId,
        'catalogId': components.firstOrNull?['component'] == 'Chart'
            ? chartGraphicsCatalogId
            : BasicCatalog.v1_0Id,
      },
    },
    if (dataModel != null)
      {
        'version': '1.0',
        'updateDataModel': {
          'surfaceId': surfaceId,
          'path': '/',
          'value': dataModel,
        },
      },
    {
      'version': '1.0',
      'updateComponents': {'surfaceId': surfaceId, 'components': components},
    },
  ];
}

/// Host-side arena for one execution of the Python `ui` module.
///
/// Constructors return opaque string handles that name an entry in this
/// arena. Handles from another execution fail validation.
class PythonUiArena {
  PythonUiArena({
    bool workbenchEnabled = false,
    Future<String> Function(String filename)? readFile,
    Future<void> Function(String filename, String text)? writeFile,
  }) : workbench = PythonWorkbench(
         enabled: workbenchEnabled,
         readFile: readFile,
         writeFile: writeFile,
       ),
       _nonce = Random.secure().nextInt(0x7fffffff).toRadixString(36);

  final PythonWorkbench workbench;
  final String _nonce;
  final Map<String, Map<String, Object?>> _nodes = {};
  final Map<String, Object?> _values = {};
  final Set<String> _ids = {};
  StagedSurface? staged;

  String _token(String kind) =>
      '<ui:$kind:$_nonce:${_nodes.length + _values.length}>';

  bool _isToken(Object? value) =>
      value is String &&
      value.startsWith('<ui:') &&
      value.contains(':$_nonce:');

  /// The `ui` module given to Monty; every call goes to [current]'s arena.
  static ExternalModule moduleFor(PythonUiArena Function() current) =>
      ExternalModule({
        'workbench': ExternalModule({
          for (final name in PythonWorkbench.signatures.keys)
            name: MontyHostFunction(name, (positional, keywords) {
              final function =
                  current().workbench.module.attrs[name]! as MontyHostFunction;
              return function.fn(positional, keywords);
            }),
        }),
        for (final MapEntry(key: name, value: params) in {
          ...basicSignatures,
          ...uiChartSignatures,
        }.entries)
          name: MontyHostFunction(name, (positional, keywords) {
            return MontyString(
              current()._construct(name, params, positional, keywords),
            );
          }),
        'graphics': ExternalModule({
          'Chart': MontyHostFunction('Chart', (positional, keywords) {
            return MontyString(
              current()._construct(
                'Chart',
                const [
                  'spec',
                  'selection',
                  'description',
                  'height',
                  'selected',
                  'action',
                  'weight',
                ],
                positional,
                keywords,
              ),
            );
          }),
        }),
        'bind': MontyHostFunction('bind', (positional, keywords) {
          final path = current()._single(positional, keywords, 'path', 'bind');
          if (path is! String ||
              path.isEmpty ||
              path.length > _maxPathLength ||
              path.contains('~')) {
            throw const ExternalException(
              'ValueError',
              'bind() takes a JSON Pointer path such as "/form/name".',
            );
          }
          final arena = current();
          final token = arena._token('bind');
          arena._values[token] = {'@path': path};
          return MontyString(token);
        }),
        'Event': MontyHostFunction('Event', (positional, keywords) {
          final name = positional.isNotEmpty
              ? positional.first.dartValue
              : keywords['name']?.dartValue;
          if (name is! String || name.isEmpty || name.length > 64) {
            throw const ExternalException(
              'ValueError',
              'Event() takes a non-empty name of at most 64 characters.',
            );
          }
          final context = positional.length > 1
              ? positional[1].dartValue
              : keywords['context']?.dartValue;
          if (context != null && context is! Map) {
            throw const ExternalException(
              'TypeError',
              'Event() context must be a dict.',
            );
          }
          final arena = current();
          final token = arena._token('event');
          arena._values[token] = {
            'event': {'name': name, 'context': ?context},
          };
          return MontyString(token);
        }),
        'show': MontyHostFunction('show', (positional, keywords) {
          final root = positional.isNotEmpty
              ? positional.first.dartValue
              : keywords['root']?.dartValue;
          final arena = current();
          final node = root is String ? arena._nodes[root] : null;
          if (node == null) {
            throw const ExternalException(
              'TypeError',
              'show() takes a component built in this run.',
            );
          }
          final data = positional.length > 1
              ? positional[1].dartValue
              : keywords['data']?.dartValue;
          if (data != null && data is! Map) {
            throw const ExternalException(
              'TypeError',
              'show() data must be a dict.',
            );
          }
          arena.staged = arena._stage(root! as String, data);
          return const MontyNone();
        }),
      });

  Object? _single(
    List<MontyValue> positional,
    Map<String, MontyValue> keywords,
    String name,
    String function,
  ) {
    if (positional.length + keywords.length != 1) {
      throw ExternalException('TypeError', '$function() takes one argument.');
    }
    return positional.isNotEmpty
        ? positional.single.dartValue
        : keywords[name]?.dartValue;
  }

  String _construct(
    String component,
    List<String> params,
    List<MontyValue> positional,
    Map<String, MontyValue> keywords,
  ) {
    if (_nodes.length >= _maxNodes) {
      throw const ExternalException(
        'ValueError',
        'Too many components in one run.',
      );
    }
    if (positional.length > params.length) {
      throw ExternalException(
        'TypeError',
        '$component() takes at most ${params.length} positional arguments.',
      );
    }
    final props = <String, Object?>{};
    for (var i = 0; i < positional.length; i++) {
      props[params[i]] = positional[i].dartValue;
    }
    String? id;
    for (final MapEntry(:key, :value) in keywords.entries) {
      if (key == 'id') {
        final v = value.dartValue;
        if (v is! String ||
            !RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(v)) {
          throw ExternalException(
            'ValueError',
            '$component() id must be an identifier.',
          );
        }
        id = v;
        continue;
      }
      if (!params.contains(key)) {
        throw ExternalException(
          'TypeError',
          "$component() got an unexpected keyword argument '$key'.",
        );
      }
      if (props.containsKey(key)) {
        throw ExternalException(
          'TypeError',
          "$component() got multiple values for argument '$key'.",
        );
      }
      props[key] = value.dartValue;
    }
    final token = _token('node');
    final nodeId = id ?? 'n${_nodes.length}';
    if (!_ids.add(nodeId)) {
      throw ExternalException(
        'ValueError',
        'Duplicate component id "$nodeId".',
      );
    }
    _nodes[token] = {'id': nodeId, 'component': component, 'props': props};
    return token;
  }

  /// Flattens the tree under [rootToken] into A2UI components.
  StagedSurface _stage(String rootToken, Object? data) {
    final components = <Map<String, Object?>>[];
    final visited = <String>{};
    String visit(String token) {
      final node = _nodes[token];
      if (node == null) {
        throw const ExternalException(
          'TypeError',
          'A child must be a component built in this run.',
        );
      }
      final id = node['id']! as String;
      if (!visited.add(token)) return id;
      final props = node['props']! as Map<String, Object?>;
      final lowered = <String, Object?>{
        'id': components.isEmpty ? 'root' : id,
        'component': node['component'],
      };
      final index = components.length;
      components.add(lowered);
      for (final MapEntry(:key, :value) in props.entries) {
        lowered[key] = _lower(key, value, visit, node['component']! as String);
      }
      if (uiChartSignatures.containsKey(node['component'])) {
        if (node['component'] == 'BarChart') _wireChart(lowered);
        try {
          lowerUiChart(lowered);
        } on FormatException catch (error) {
          throw ExternalException('ValueError', error.message);
        }
      }
      components[index] = lowered;
      return lowered['id']! as String;
    }

    visit(rootToken);
    for (final component in components.where(
      (node) => node['component'] == 'Chart',
    )) {
      component['@catalogId'] = chartGraphicsCatalogId;
      try {
        validateStaticChartSpec(component['spec']);
      } on FormatException catch (error) {
        throw ExternalException('ValueError', error.message);
      }
      if (!component.containsKey('selected') &&
          (component['spec']! as Map)['kind'] == 'bar' &&
          component.containsKey('action')) {
        _wireChart(component);
      }
    }
    return StagedSurface(components, data == null ? null : _lowerData(data));
  }

  /// Binds the chart's selection to `/_ui/<id>/label` and adds that label
  /// to the tap action's context, so `handle_event` receives the bar label.
  static void _wireChart(Map<String, Object?> chart) {
    final selection = {'@path': '/_ui/${chart['id']}/label'};
    chart['selected'] = selection;
    final bars = chart['bars'];
    if (bars is List) {
      chart['bars'] = [
        for (final bar in bars)
          if (bar case {'label': final num label})
            {...bar, 'label': '$label'}
          else
            bar,
      ];
    }
    if (chart['action'] case {'event': final Map<Object?, Object?> event}) {
      final context = event['context'];
      event['context'] = {
        if (context is Map) ...context,
        'label': selection,
      };
    }
  }

  Object? _lower(
    String key,
    Object? value,
    String Function(String) visit,
    String component,
  ) {
    if (key == 'children') {
      if (value is! List) {
        throw ExternalException(
          'TypeError',
          '$component() children must be a list of components.',
        );
      }
      return [for (final child in value) visit(_handle(child, component))];
    }
    if (key == 'child' || key == 'trigger' || key == 'content') {
      return visit(_handle(value, component));
    }
    if (key == 'tabs' && value is List) {
      return [
        for (final tab in value)
          if (tab is Map)
            {
              'title': _value(tab['title']),
              'child': visit(_handle(tab['child'], component)),
            }
          else
            throw const ExternalException(
              'TypeError',
              'Tabs() takes a list of {"title": ..., "child": ...} dicts.',
            ),
      ];
    }
    if (key == 'options' && value is List) {
      return [
        for (final option in value)
          if (option is String)
            {'label': option, 'value': option}
          else
            _value(option),
      ];
    }
    return _value(value);
  }

  String _handle(Object? value, String component) {
    if (value is String && _nodes.containsKey(value)) return value;
    throw ExternalException(
      'TypeError',
      '$component() expects a component built in this run.',
    );
  }

  /// Replaces bind and Event handles; nodes are not allowed here.
  Object? _value(Object? value) => switch (value) {
    // Event contexts hold bind handles, so stored values are lowered too.
    final String s when _isToken(s) => _value(
      _values[s] ??
          (throw const ExternalException(
            'TypeError',
            'A component cannot be used as a property value.',
          )),
    ),
    final String s when s.startsWith('<ui:') => throw const ExternalException(
      'ValueError',
      'A handle from an earlier run cannot be reused.',
    ),
    final List<Object?> l => [for (final v in l) _value(v)],
    final Map<Object?, Object?> m => {
      for (final MapEntry(:key, :value) in m.entries) '$key': _value(value),
    },
    final double d when !d.isFinite => throw const ExternalException(
      'ValueError',
      'Numbers must be finite.',
    ),
    _ => value,
  };

  Object? _lowerData(Object? value) => switch (value) {
    final String s when s.startsWith('<ui:') => throw const ExternalException(
      'TypeError',
      'show() data holds plain values only.',
    ),
    final List<Object?> l => [for (final v in l) _lowerData(v)],
    final Map<Object?, Object?> m => {
      for (final MapEntry(:key, :value) in m.entries) '$key': _lowerData(value),
    },
    _ => value,
  };
}

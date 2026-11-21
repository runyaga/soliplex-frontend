import 'dart:math';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:dart_monty/core.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_monty/src/bindings/host_bindings.dart';
import 'package:soliplex_monty/src/bindings/registered_module.dart';
import 'package:soliplex_monty/src/python_workbench.dart';
import 'package:soliplex_monty/src/ui_chart.dart';

export 'bindings/positional_signatures.dart' show basicSignatures;

/// Caps rendered counts without relying on dart2js bit-shift widths.
const int _maxRenderedCount = 1000000000;
const _constructionBackstopFactor = 10;
const _maxPathLength = 200;

int _saturate(int value) => min(value, _maxRenderedCount);

void _validateLimit(int? value, String name) {
  if (value != null && (value < 1 || value >= _maxRenderedCount)) {
    throw ArgumentError.value(value, name, 'Must be null or 1..999999999.');
  }
}

/// A surface staged by `ui.show`, published only after the run succeeds.
class StagedSurface {
  StagedSurface(this.components, this.dataModel, {int? rendered})
    : rendered = rendered ?? components.length;

  final List<Map<String, Object?>> components;
  final Object? dataModel;

  /// Rendered component occurrences, counting shared subtrees per reference.
  final int rendered;

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
    this.maxNodes = defaultMaxNodes,
    this.warnNodes = defaultWarnNodes,
    bool workbenchEnabled = false,
    Future<String> Function(String filename)? readFile,
    Future<void> Function(String filename, String text)? writeFile,
  }) : workbench = PythonWorkbench(
         enabled: workbenchEnabled,
         readFile: readFile,
         writeFile: writeFile,
       ),
       _nonce = Random.secure().nextInt(0x7fffffff).toRadixString(36) {
    _validateLimit(maxNodes, 'maxNodes');
    _validateLimit(warnNodes, 'warnNodes');
  }

  static const int defaultMaxNodes = 20000;
  static const int defaultWarnNodes = 15000;

  /// Maximum rendered components per surface; null disables the limit.
  final int? maxNodes;

  /// Rendered count above which a show records a warning; null disables it.
  final int? warnNodes;

  final PythonWorkbench workbench;
  final String _nonce;
  final Map<String, Map<String, Object?>> _nodes = {};
  final Map<String, Object?> _values = {};
  final Set<String> _ids = {};
  StagedSurface? staged;
  final List<String> _warnings = [];

  List<String> get warnings => List.unmodifiable(_warnings);

  String _token(String kind) =>
      '<ui:$kind:$_nonce:${_nodes.length + _values.length}>';

  bool _isToken(Object? value) =>
      value is String &&
      _handlePattern.hasMatch(value) &&
      value.contains(':$_nonce:');

  /// The `ui` module given to Monty; every call goes to [current]'s arena.
  static ExternalModule moduleFor(
    PythonUiArena Function() current,
  ) => registerBindings(
    'ui',
    ExternalModule({
      'workbench': registerBindings(
        'ui.workbench',
        ExternalModule({
          for (final name in PythonWorkbench.functionNames)
            name: MontyHostFunction(name, (positional, keywords) {
              final function =
                  current().workbench.module.attrs[name]! as MontyHostFunction;
              return function.fn(positional, keywords);
            }),
        }),
      ),
      for (final MapEntry(key: name, value: params) in {
        ...basicSignatures,
        ...uiChartSignatures,
      }.entries)
        name: MontyHostFunction(name, (positional, keywords) {
          return MontyString(
            current()._construct(name, params, positional, keywords),
          );
        }),
      'graphics': registerBindings(
        'ui.graphics',
        ExternalModule({
          'Chart': MontyHostFunction('Chart', (positional, keywords) {
            return MontyString(
              current()._construct(
                'Chart',
                graphicsSignature,
                positional,
                keywords,
              ),
            );
          }),
        }),
      ),
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
        final staged = arena._stage(root! as String, data);
        final count = staged.rendered;
        final limit = arena.maxNodes;
        if (limit != null && count > limit) {
          throw ExternalException(
            'ValueError',
            'Surface renders $count components, exceeding the limit of '
                '$limit. Show fewer rows (page or filter the data).',
          );
        }
        final warning = arena.warnNodes;
        if (warning != null && count > warning) {
          arena._warnings.add(
            'Surface renders $count components (warning at $warning). '
            'Page or filter long lists.',
          );
        }
        arena.staged = staged;
        return const MontyNone();
      }),
    }),
  );

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
    final limit = maxNodes;
    final backstop = limit == null ? null : limit * _constructionBackstopFactor;
    if (backstop != null && _nodes.length >= backstop) {
      throw ExternalException(
        'ValueError',
        'Construction stopped at $backstop components '
            '(ten times the node limit of $limit).',
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
            !RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(v) ||
            v.startsWith(_anonPrefix)) {
          throw ExternalException(
            'ValueError',
            '$component() id must be an identifier.',
          );
        }
        id = v;
        continue;
      }
      if (!moduleBindings[component == 'Chart' ? 'ui.graphics' : 'ui']!
          .functions
          .singleWhere((b) => b.name == component)
          .parameters
          .any((p) => p.name == key)) {
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
    final nodeId = id ?? '$_anonPrefix${_nodes.length}';
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
    // Memoize finished subtrees, adding their size for every child reference.
    // The open stack accumulates only counts, never the expanded render tree.
    final sizes = <String, int>{};
    final open = <int>[];
    void addRendered(int size) {
      if (open.isNotEmpty) open.last = _saturate(open.last + size);
    }

    String visit(String token) {
      final node = _nodes[token];
      if (node == null) {
        throw const ExternalException(
          'TypeError',
          'A child must be a component built in this run.',
        );
      }
      final id = node['id']! as String;
      if (!visited.add(token)) {
        addRendered(sizes[token]!);
        return id;
      }
      final props = node['props']! as Map<String, Object?>;
      final lowered = <String, Object?>{
        'id': components.isEmpty ? 'root' : id,
        'component': node['component'],
      };
      final index = components.length;
      components.add(lowered);
      open.add(0);
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
      final size = _saturate(1 + open.removeLast());
      sizes[token] = size;
      addRendered(size);
      components[index] = lowered;
      return lowered['id']! as String;
    }

    visit(rootToken);
    for (final component in components.where(
      (node) => node['component'] == 'Chart',
    )) {
      component['@catalogId'] = chartGraphicsCatalogId;
      try {
        validateChartComponent({
          for (final entry in component.entries)
            if (!['id', 'component', '@catalogId'].contains(entry.key))
              entry.key: entry.value,
        });
      } on FormatException catch (error) {
        throw ExternalException('ValueError', error.message);
      }
      if (!component.containsKey('selected') &&
          (component['spec']! as Map)['kind'] == 'bar' &&
          component.containsKey('action')) {
        _wireChart(component);
      }
    }
    return StagedSurface(
      components,
      data == null ? null : _lowerData(data),
      rendered: sizes[rootToken],
    );
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
    final String s when _handlePattern.hasMatch(s) =>
      throw const ExternalException(
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
    final String s when _handlePattern.hasMatch(s) =>
      throw const ExternalException(
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

/// Matches only a complete handle from any arena.
final _handlePattern = RegExp(r'^<ui:(?:node|bind|event):[0-9a-z]+:\d+>$');

/// Explicit IDs cannot occupy the generated namespace.
const _anonPrefix = 'monty_anon_';

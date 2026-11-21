import 'dart:async';
import 'dart:math' as math;

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:dart_monty/dart_monty.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_monty/src/chart_module.dart';

import 'package:soliplex_monty/src/program_type_check.dart';
import 'package:soliplex_monty/src/python_ui.dart';
import 'package:soliplex_monty/src/repair_chain.dart';
import 'package:soliplex_monty/src/worker_location.dart';
import 'package:soliplex_monty/src/workspace_files.dart';

const labCatalogId = 'urn:soliplex:catalog:lab:1';

/// Starts the interpreter that one `PythonRepl` instance owns.
typedef ReplRuntimeStarter =
    Future<MontyRuntime> Function(
      ResourceLimits limits,
      Map<String, Object?> externalModules,
    );

/// Bounds for one REPL instance.
class ReplLimits {
  const ReplLimits({
    this.maxMemory = 32 * 1024 * 1024,
    this.maxFeedDuration = const Duration(seconds: 1),
    this.deadline = const Duration(seconds: 5),
    this.maxEntries = 20,
    this.maxOutputChars = 4000,
    this.maxSourceChars = 20000,
    this.retries = 2,
    this.maxRetries = 5,
    this.maxErrorChars = 2000,
    this.maxSuspensions = 1000000,
  });

  final int maxMemory;

  /// Host calls a session may make over its lifetime. An app window keeps one
  /// session across every event and each redraw makes many ui calls, so the
  /// dart_monty default of 1000 ends an app after a few dozen clicks. The
  /// per-run feed duration and deadline bound a runaway program.
  final int maxSuspensions;
  final Duration maxFeedDuration;
  final Duration deadline;
  final int maxEntries;
  final int maxOutputChars;
  final int maxSourceChars;

  /// Repair rounds while AI Fix is enabled, unless a surface sets fewer.
  final int retries;

  /// The most repair rounds a surface may ask for without a user's click.
  final int maxRetries;

  /// Error text sent to the model with a repair request.
  final int maxErrorChars;
}

/// A surface's `retry` property: the repair budget it asks for, and the
/// chain and attempt a repaired editor answers.
class ReplRetry {
  const ReplRetry({this.max, this.chainId, this.attempt = 0});

  /// Reads the `retry` property; null when it is absent or not an object.
  static ReplRetry? from(Object? value) => switch (value) {
    final Map<Object?, Object?> map => ReplRetry(
      max: switch (map['max']) {
        final num n => n.toInt(),
        _ => null,
      },
      chainId: switch (map['chainId']) {
        final String id when id.isNotEmpty => id,
        _ => null,
      },
      attempt: switch (map['attempt']) {
        final num n => n.toInt(),
        _ => 0,
      },
    ),
    _ => null,
  };

  final int? max;
  final String? chainId;
  final int attempt;
}

/// Pools that [_startRuntime] created, closed after their runtime.
final _ownedPools = Expando<Monty>('soliplex_monty.pool');

/// Starts a runtime whose worker comes from the Flutter asset base on the web.
Future<MontyRuntime> _startRuntime(
  ResourceLimits limits,
  Map<String, Object?> externalModules,
) async {
  final base = montyWorkerBase();
  if (base == null) {
    return MontyRuntime.start(limits: limits, externalModules: externalModules);
  }
  final pool = await Monty.start(
    maxProcesses: 2,
    checkoutTimeout: const Duration(seconds: 30),
    workerLocation: base,
  );
  try {
    final runtime = await MontyRuntime.start(
      pool: pool,
      limits: limits,
      externalModules: externalModules,
    );
    _ownedPools[runtime] = pool;
    return runtime;
  } on Object {
    await pool.close();
    rethrow;
  }
}

/// Disposes [runtime] and the pool [_startRuntime] created for it.
Future<void> _disposeRuntime(MontyRuntime runtime) async {
  await runtime.dispose();
  await _ownedPools[runtime]?.close();
}

/// JSON Pointer accepted for `outputPath`.
const _pointerPattern = r'^(/([^~/]|~[01])*)+$';

// Layout children need boundaries even inside a Card, which otherwise merges
// their text. Keep control internals together so a button retains its label.
CatalogImplementation _pythonBasicCatalog() {
  final basic = basicCatalog();
  return basic.copyWith(
    components: [
      for (final component in basic.components.values)
        if (const {'Row', 'Column', 'List', 'Card'}.contains(component.name))
          ComponentImplementation(
            name: component.name,
            schema: component.schema,
            allowedParents: component.allowedParents,
            allowedChildren: component.allowedChildren,
            builder: (context, node, props, buildChild) => component.builder(
              context,
              node,
              props,
              (child) => Semantics(container: true, child: buildChild(child)),
            ),
          )
        else
          component,
    ],
  );
}

/// Registers experimental components that run code only on a user gesture.
///
/// [isLive] says whether the surface around a component arrived from a run
/// in flight. Only such a surface may run a repaired program on arrival.
/// Without [isLive] nothing runs on arrival. [chains] defaults to
/// [RepairChains.shared]. [activeRunId] lets a host settle a repair request
/// when its model turn ends without delivering a replacement.
CatalogImplementation labCatalog({
  ReplRuntimeStarter? startRuntime,
  Future<String?> Function(String, ResourceLimits) checkTypes =
      checkProgramTypes,
  ReplLimits limits = const ReplLimits(),
  bool Function(BuildContext context)? isLive,
  RepairChains? chains,
  String? Function(BuildContext context)? activeRunId,
}) => CatalogImplementation(
  id: labCatalogId,
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    ComponentImplementation(
      name: 'PythonRepl',
      schema: Schema.object(
        properties: {
          'source': CommonSchemasV1.dynamicString,
          'outputPath': Schema.string(pattern: _pointerPattern, maxLength: 200),
          'onRun': Schema.fromMap({
            r'$ref': r'common_types.json#/$defs/Action',
          }),
          'onWorkbench': Schema.fromMap({
            r'$ref': r'common_types.json#/$defs/Action',
          }),
          'onFailure': Schema.fromMap({
            r'$ref': r'common_types.json#/$defs/Action',
          }),
          'showSource': Schema.boolean(),
          'mode': Schema.fromMap({
            'type': 'string',
            'enum': ['repl', 'run'],
          }),
          'retry': Schema.fromMap({
            'type': 'object',
            'properties': {
              'max': {'type': 'integer', 'minimum': 0, 'maximum': 10},
              'chainId': {'type': 'string', 'minLength': 1, 'maxLength': 64},
              'attempt': {'type': 'integer', 'minimum': 0, 'maximum': 50},
            },
            'additionalProperties': false,
          }),
          'files': workspaceFilesSchema(),
          'examples': Schema.fromMap({
            'type': 'array',
            'maxItems': 12,
            'items': {
              'type': 'object',
              'properties': {
                'label': {'type': 'string', 'minLength': 1, 'maxLength': 40},
                'source': {'type': 'string', 'maxLength': 20000},
              },
              'required': ['label', 'source'],
              'additionalProperties': false,
            },
          }),
          'typeCheck': Schema.boolean(),
        },
        required: ['source'],
      ),
      builder: (context, node, props, buildChild) {
        final source = props.string('source') ?? '';
        final binding = props.writable('source');
        final outputPath = props.string('outputPath');
        final sourcePath = binding == null
            ? null
            : DataModel.resolvePath(binding.path, node.dataPath);
        final resolvedOutput = outputPath == null
            ? null
            : DataModel.resolvePath(outputPath, node.dataPath);
        if (resolvedOutput != null &&
            sourcePath != null &&
            (resolvedOutput == sourcePath ||
                sourcePath.startsWith('$resolvedOutput/'))) {
          return const Text('Invalid REPL: outputPath overlaps source');
        }
        final surface = A2uiSurface.of(context);
        return PythonReplView(
          key: ValueKey('python-repl:${node.instanceId}'),
          source: source,
          typeCheck: props.boolean('typeCheck') ?? false,
          surfaceId: surface.id,
          limits: limits,
          startRuntime: startRuntime ?? _startRuntime,
          checkTypes: checkTypes,
          writeSource: binding == null
              ? null
              : (text) {
                  try {
                    binding.set(text);
                    return true;
                  } on A2uiDataError {
                    return false;
                  }
                },
          writeResult: resolvedOutput == null
              ? null
              : (result) => surface.dataModel.set(resolvedOutput, result),
          onRun: props.action('onRun'),
          onWorkbench: props.action('onWorkbench'),
          includeRunMetadata:
              switch (node.context?.componentModel.properties['onRun']) {
                {'event': {'name': 'workbench.program.run_result'}} => true,
                _ => false,
              },
          onFailure: props.action('onFailure'),
          retry: ReplRetry.from(props.value('retry')),
          showSource: props.boolean('showSource') ?? false,
          mode: props.string('mode') == 'run' ? ReplMode.run : ReplMode.repl,
          live: isLive?.call(context) ?? false,
          activeRunId: activeRunId?.call(context),
          chains: chains ?? RepairChains.shared,
          files: workspaceFiles(props.list('files')),
          examples: [
            for (final item in props.list('examples'))
              if (item case {
                'label': final String label,
                'source': final String code,
              })
                ReplExample(label, code),
          ],
        );
      },
    ),
  ],
);

/// A program the user can load into the editor; loading never runs it.
class ReplExample {
  const ReplExample(this.label, this.source);

  final String label;
  final String source;
}

/// One transcript entry: the code that ran and what it produced.
class ReplEntry {
  const ReplEntry({
    required this.input,
    required this.output,
    required this.ok,
    this.header = '',
  });

  final String input;
  final String output;
  final bool ok;

  /// What produced the entry, such as `Run 3` or `Run 2 · attempt 1 of 2`.
  final String header;
}

/// How a `PythonRepl` presents its program.
enum ReplMode {
  /// Editor, transcript of runs, and globals kept between runs.
  repl,

  /// Run button and the latest result. The editor is behind a toggle, and
  /// each Run starts a fresh interpreter session.
  run,
}

/// Editor, Run button and transcript backed by one Monty runtime.
///
/// Code runs from the Run button, or on arrival when this editor is the
/// repair a live [RepairChain] waits for and the surface arrived [live].
class PythonReplView extends StatefulWidget {
  const PythonReplView({
    required this.source,
    required this.limits,
    required this.startRuntime,
    super.key,
    this.surfaceId,
    this.typeCheck = false,
    this.checkTypes = checkProgramTypes,
    this.writeSource,
    this.writeResult,
    this.onRun,
    this.onWorkbench,
    this.includeRunMetadata = false,
    this.onFailure,
    this.retry,
    this.live = false,
    this.activeRunId,
    this.chains,
    this.showSource = false,
    this.mode = ReplMode.repl,
    this.examples = const [],
    this.files = const [],
  });

  final String source;

  /// Initial preference for this program; local choices take priority.
  final bool typeCheck;

  /// Runs a preflight check without evaluating the program.
  final Future<String?> Function(String, ResourceLimits) checkTypes;

  /// Stable program identity for local AI Fix preference persistence.
  final String? surfaceId;
  final List<ReplExample> examples;

  /// Files mounted read-only at `/workspace/room/<name>` for every run.
  final List<WorkspaceFile> files;
  final ReplLimits limits;
  final ReplRuntimeStarter startRuntime;
  final bool Function(String text)? writeSource;
  final void Function(Map<String, Object?> result)? writeResult;
  final Future<void> Function()? onRun;
  final Future<void> Function()? onWorkbench;

  /// Adds bounded provenance fields for a workbench run-result action.
  final bool includeRunMetadata;

  /// Asks the model to repair a failed run. The failure is in the result
  /// that [writeResult] wrote just before.
  final Future<void> Function()? onFailure;
  final ReplRetry? retry;

  /// Whether the surface arrived from a run in flight, not from history.
  final bool live;

  /// The model turn currently in flight, used to settle declined repairs.
  final String? activeRunId;
  final RepairChains? chains;

  /// Whether each transcript entry shows its code without a click.
  final bool showSource;
  final ReplMode mode;

  /// Receives each run on arrival instead of starting it, so a widget test
  /// can start it outside the fake-async zone.
  @visibleForTesting
  static void Function(VoidCallback start)? debugScheduleAutoRun;

  @override
  State<PythonReplView> createState() => _PythonReplViewState();
}

class _PythonReplViewState extends State<PythonReplView> {
  late final TextEditingController _editor;
  final ScrollController _scroll = ScrollController();
  final List<ReplEntry> _entries = [];
  Future<MontyRuntime>? _starting;
  ExecutionHandle? _active;
  bool _running = false;
  bool _disposed = false;
  int _runs = 0;
  PythonUiArena _arena = PythonUiArena();
  MessageProcessor<ComponentImplementation>? _ui;
  bool _loading = false;
  bool _historyOpen = false;
  ProgramApps? _apps;
  ProgramApps? _controlApps;
  late final _programControls = ProgramControls(
    source: () => _editor.text,
    run: run,
    event: (name) => _dispatch({'name': name, 'context': <String, Object?>{}}),
  );
  Widget? _appView;
  bool _appRequested = false;

  /// Whether the source editor is expanded in either mode.
  bool _editorOpen = false;
  bool _userOpenedEditor = false;

  bool get _runMode => widget.mode == ReplMode.run;

  RepairChain? _chain;

  /// The attempt this editor requested, and the one it ran on arrival.
  int? _requested;
  int? _claimed;
  String? _lastError;
  bool _aiFix = false;
  bool _typeCheck = false;
  double? _lastTypeCheckMs;
  bool _failedWithAiFix = false;
  bool _preferencesLoaded = false;
  late final Future<void> _preferences;
  String? _repairTurnId;
  String? _requestedDuringRunId;
  bool _notRepaired = false;

  String? get _preferenceKey => widget.surfaceId == null
      ? null
      : 'soliplex.python.aiFix.${widget.surfaceId}';

  Future<void> _loadPreference() async {
    final key = _preferenceKey;
    var enabled = false;
    var checked = widget.typeCheck;
    if (key != null) {
      try {
        // Run awaits this load, so a stalled store must not block it.
        final prefs = await SharedPreferences.getInstance().timeout(
          const Duration(seconds: 2),
        );
        enabled = prefs.getBool(key) ?? false;
        checked = prefs.getBool(_typeCheckKey!) ?? widget.typeCheck;
      } on Object {
        // A missing preference store defaults to explicit Run only.
      }
    }
    if (_disposed) return;
    setState(() {
      _aiFix = enabled;
      _typeCheck = checked;
      _preferencesLoaded = true;
    });
    _claimOnArrival();
  }

  String? get _typeCheckKey => widget.surfaceId == null
      ? null
      : 'soliplex.python.typeCheck.${widget.surfaceId}';

  void _setTypeCheck(bool enabled) {
    setState(() => _typeCheck = enabled);
    final key = _typeCheckKey;
    if (key != null) unawaited(_savePreference(key, enabled));
  }

  void _setAiFix(bool enabled) {
    setState(() => _aiFix = enabled);
    if (!enabled) _end();
    final key = _preferenceKey;
    if (key != null) {
      unawaited(_savePreference(key, enabled));
    }
  }

  Future<void> _savePreference(String key, bool enabled) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(key, enabled);
    } on Object {
      // Keep the current surface usable when local storage is unavailable.
    }
  }

  int? _fixedAfter;

  RepairChains get _chains => widget.chains ?? RepairChains.shared;

  bool get _repairable =>
      widget.onFailure != null && widget.writeResult != null;

  bool get _pending => _requested != null && _chain?.awaiting == _requested;

  /// Rounds a new chain may request without asking, clamped by the client.
  int get _budget => math.min(
    math.max(widget.retry?.max ?? widget.limits.retries, 0),
    widget.limits.maxRetries,
  );

  @override
  void initState() {
    super.initState();
    _editorOpen = !_runMode;
    _editor = TextEditingController(text: widget.source);
    _preferences = _loadPreference();
    unawaited(_preferences);
  }

  /// Runs this editor once when it is the repair a live chain waits for.
  void _claimOnArrival() {
    if (!_preferencesLoaded || !_repairable || !widget.live) return;
    final retry = widget.retry;
    final id = retry?.chainId ?? _chains.surfaceChains[widget.surfaceId];
    final chain = id == null ? null : _chains[id];
    if (chain == null) return;
    if (!_aiFix || !chain.autoRun) {
      chain.end();
      return;
    }
    if (retry?.chainId == null && widget.source == chain.awaitingSource) {
      return;
    }
    final attempt = retry?.chainId == null ? chain.awaiting : retry?.attempt;
    if (attempt == null || !chain.claim(attempt)) return;
    _follow(chain);
    _editorOpen = true;
    _claimed = attempt;
    _runs = chain.runs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (PythonReplView.debugScheduleAutoRun ?? (start) => start())(() {
        if (!_disposed && _aiFix && widget.live && chain.isActive) {
          unawaited(run());
        }
      });
    });
  }

  void _follow(RepairChain chain) {
    _chain?.removeListener(_onChain);
    _chain = chain..addListener(_onChain);
  }

  /// Repaints for a chain change, after the frame when another editor's
  /// build caused it.
  void _onChain() {
    if (_disposed || !mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.persistentCallbacks) return setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(PythonReplView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pending) {
      if (widget.activeRunId != null &&
          widget.activeRunId != _requestedDuringRunId) {
        _repairTurnId = widget.activeRunId;
      } else if (_repairTurnId != null) {
        // Replacement is delivered before the turn closes. Let its arrival
        // claim first, including an asynchronous preference load.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_disposed && _pending && widget.activeRunId == null) {
            _chain?.end();
            setState(() => _notRepaired = true);
          }
        });
      }
    }
    final bound = widget.writeSource != null;
    if ((bound || widget.source != oldWidget.source) &&
        widget.source != _editor.text) {
      _editor.value = TextEditingValue(
        text: widget.source,
        selection: TextSelection.collapsed(offset: widget.source.length),
      );
    }
    if (widget.source != oldWidget.source ||
        widget.retry?.chainId != oldWidget.retry?.chainId ||
        widget.retry?.attempt != oldWidget.retry?.attempt) {
      _claimOnArrival();
    }
  }

  /// Replaces the editor text with [example]. It does not run the code.
  void load(ReplExample example) {
    if (_running || _disposed) return;
    _editor.value = TextEditingValue(
      text: example.source,
      selection: TextSelection.collapsed(offset: example.source.length),
    );
    setState(() => _editorOpen = true);
    _onEdit(example.source);
  }

  void _onEdit(String text) {
    // Editing a pending program is not delivery of an agent repair.
    if (_chain?.isActive ?? false) _chain?.end();
    if (widget.writeSource?.call(text) == false) {
      _editor.text = widget.source;
    }
  }

  /// The read-only workspace; null when the surface delivered no files.
  late final OsHandler? _os = widget.files.isEmpty
      ? null
      : workspaceOsHandler(widget.files);

  ResourceLimits get _resourceLimits => ResourceLimits(
    maxMemory: widget.limits.maxMemory,
    maxFeedDuration: widget.limits.maxFeedDuration,
    maxSuspensions: widget.limits.maxSuspensions,
  );

  /// Runs the editor after Run or an authorized live repair arrival.
  Future<void> run() async {
    if (_running || _disposed) return;
    setState(() {
      _running = true;
      _fixedAfter = null;
      _notRepaired = false;
    });
    try {
      // A click while local storage is loading still honors the saved checks.
      await _preferences;
      if (_disposed) return;
      final code = _editor.text;
      final limits = widget.limits;
      if (code.length > limits.maxSourceChars) {
        final message = 'Source exceeds ${limits.maxSourceChars} characters.';
        _record(code, message, ok: false);
        _afterRun(code, message, ok: false);
        return;
      }
      final runtime = await _runtime(code);
      if (runtime == null || _disposed) return;
      if (_runMode && !await _freshSession(runtime, code)) return;
      if (!mounted) return;
      final threadApps = ProgramAppScope.maybeOf(context);
      _arena = PythonUiArena(
        workbenchEnabled: widget.onWorkbench != null,
        readFile: threadApps?.readFile,
        writeFile: threadApps?.writeFile,
      );
      var (output, ok) = await _execute(
        runtime,
        code,
        limits,
        inputs: {'CLIENT': _clientViewport()},
      );
      if (_disposed) return;
      if (_arena.workbench.rejected) {
        ok = false;
        output = _join(output, 'Workbench layout action limit (8) exceeded.');
      }
      if (ok) {
        final error = _stageApp();
        if (error != null) {
          output = _join(output, error);
          ok = false;
        }
      }
      if (ok) {
        final rejected = _commit(_arena.staged);
        if (rejected != null) {
          output = _join(output, 'Surface rejected: $rejected');
          ok = false;
        }
      }
      _record(code, output, ok: ok);
      _runs++;
      final invocationId =
          'invocation-${DateTime.now().microsecondsSinceEpoch}-$_runs';
      final runResult = <String, Object?>{
        if (widget.includeRunMetadata) ...{
          'invocationId': invocationId,
          'chainId': _chain?.id ?? invocationId,
          'outcome': ok ? 'success' : 'error',
        },
        'run': _runs,
        'source': code,
        'output': widget.includeRunMetadata
            ? output.substring(
                0,
                math.min(output.length, limits.maxOutputChars),
              )
            : _clip(output, limits.maxOutputChars),
        'ok': ok,
      };
      widget.writeResult?.call(runResult);
      _afterRun(code, output, ok: ok);
      final onRun = widget.onRun;
      if (ok && _arena.workbench.actions.isNotEmpty) {
        await _publishWorkbench();
        // Layout publication uses the same output binding. Restore the run's
        // evidence after a repair so the model can observe its final result.
        if (_claimed != null && !_disposed && onRun != null) {
          widget.writeResult?.call(runResult);
          unawaited(onRun().catchError((Object _) {}));
        }
      } else if (onRun != null && (ok || !_repairable)) {
        // Repairable failures stay local unless AI Fix requests a repair.
        unawaited(onRun().catchError((Object _) {}));
      }
    } finally {
      if (!_disposed) setState(() => _running = false);
    }
  }

  /// `Run n`, with the repair attempt when this editor ran one on arrival.
  String _runHeader() {
    final attempt = _claimed;
    final chain = _chain;
    final run = 'Run ${_runs + 1}';
    if (attempt == null || chain == null) return run;
    return '$run · attempt $attempt of ${chain.max}';
  }

  /// The session runtime, started on first use. Null when it failed to start.
  Future<MontyRuntime?> _runtime(String code) async {
    if (_starting == null) setState(() => _loading = true);
    try {
      return await (_starting ??= widget.startRuntime(_resourceLimits, {
        'ui': PythonUiArena.moduleFor(() => _arena),
        'chart': chartModule(),
      }));
    } on Object catch (error) {
      _starting = null;
      if (!_disposed) {
        _record(code, 'Python failed to start: $error', ok: false);
      }
      return null;
    } finally {
      if (!_disposed && _loading) setState(() => _loading = false);
    }
  }

  /// Clears globals and the Python-built surface before a run in
  /// [ReplMode.run]. False when the interpreter could not be reset.
  Future<bool> _freshSession(MontyRuntime runtime, String code) async {
    final old = _ui;
    final view = _appView;
    final program = widget.surfaceId;
    if (view != null && program != null) {
      _apps?.remove(program, view);
      _apps?.unbindState(program);
    }
    _appView = null;
    if (old != null) {
      setState(() => _ui = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    try {
      await runtime.clearState();
      return !_disposed;
    } on Object catch (error) {
      if (!_disposed) {
        _record(code, 'Python failed to reset: $error', ok: false);
      }
      return false;
    }
  }

  /// Only a failure with AI Fix enabled may start or continue a chain.
  void _afterRun(String code, String output, {required bool ok}) {
    if (!_repairable || _disposed) return;
    if (ok) return _settle();
    setState(() {
      _lastError = output;
      _failedWithAiFix = _aiFix;
    });
    if (!_aiFix) return;
    final chain = _chain;
    if (chain != null && chain.isActive) {
      if (chain.hasBudget) _requestRepair(chain, code);
    } else if (_budget > 0) {
      _follow(_chains.start(_budget, autoRun: true));
      _requestRepair(_chain!, code);
    }
  }

  void _settle() {
    final chain = _chain;
    setState(() {
      _lastError = null;
      if (chain != null && _claimed != null && chain.isActive) {
        _fixedAfter = chain.rounds;
        chain.markFixed();
      }
    });
  }

  /// Writes the failure where the `onFailure` action reads it, then
  /// dispatches the action once for the chain's next round.
  void _requestRepair(RepairChain chain, String code) {
    final onFailure = widget.onFailure;
    final attempt = chain.request();
    if (onFailure == null || attempt == null) return;
    chain
      ..awaitingSource = widget.source
      ..runs = _runs;
    final limits = widget.limits;
    final text = _lastError ?? '';
    final error = text.substring(
      0,
      math.min(text.length, limits.maxErrorChars),
    );
    widget.writeResult?.call({
      'run': _runs,
      'source': code.substring(0, math.min(code.length, limits.maxSourceChars)),
      'output': error,
      'error': error,
      'ok': false,
      'attempt': attempt,
      'chainId': chain.id,
      'aiFix': _aiFix,
      'autoRun': _aiFix && chain.autoRun,
      'instruction': _aiFix && chain.autoRun
          ? 'Repair this program. AI Fix is on: the repair will run now; '
                'do not claim it ran until a successful run result arrives.'
          : 'Repair this program once. The repair waits: '
                'tell the user to press Run.',
    });
    final surfaceId = widget.surfaceId;
    if (surfaceId != null) _chains.surfaceChains[surfaceId] = chain.id;
    setState(() {
      _editorOpen = true;
      _requested = attempt;
      _repairTurnId = null;
      _requestedDuringRunId = widget.activeRunId;
      _notRepaired = false;
    });
    unawaited(onFailure().catchError((Object _) {}));
  }

  /// Requests one repair after an explicit AI Fix click.
  void _fix() {
    if (_running || _disposed || _pending || _lastError == null) return;
    var chain = _chain;
    if (chain == null || !chain.isActive) {
      chain = _chains.start(
        1,
        autoRun: _aiFix && _failedWithAiFix,
      );
      _follow(chain);
    }
    chain.grant();
    _requestRepair(chain, _editor.text);
  }

  /// Ends the chain when AI Fix is unchecked or Stop is pressed.
  void _end() {
    _chain?.end();
    setState(() {});
  }

  /// Validates [staged] in a fresh processor and swaps it in.
  ///
  /// Returns the rejection reason, or null when committed or nothing staged.
  /// A rejected surface leaves the previous one on screen.
  String? _commit(StagedSurface? staged) {
    if (staged == null) return null;
    final next = MessageProcessor<ComponentImplementation>(
      catalogs: [
        _pythonBasicCatalog(),
        chartGraphicsCatalog(),
      ],
      validationConfig: ValidationConfig.strict,
    );
    final errors = <String>[];
    final sub = next.model.onError.subscribe((e) => errors.add('$e'));
    try {
      next.processMessages(staged.messages('python'));
    } on Object catch (error) {
      errors.add('$error');
    }
    sub.unsubscribe();
    if (errors.isNotEmpty || next.model.allSurfaces.isEmpty) {
      next.dispose();
      return errors.isEmpty ? 'no surface was created' : errors.first;
    }
    next.model.onAction.subscribe((action) {
      if (!_disposed) unawaited(_dispatch(action.toJson()));
    });
    final old = _ui;
    setState(() => _ui = next);
    final apps = ProgramAppScope.maybeOf(context);
    final program = widget.surfaceId;
    if (apps != null && program != null && widget.onWorkbench != null) {
      _apps = apps;
      final surface = next.model.allSurfaces.first;
      final view = A2uiSurface(key: ObjectKey(surface), surface: surface);
      _appView = view;
      apps
        ..publish(program, view)
        ..bindState(
          program,
          () => _ui?.model.allSurfaces.firstOrNull?.dataModel.get('/') ?? {},
        );
    }
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    return null;
  }

  /// Calls `handle_event(name, context)` in the session after a click on a
  /// Python-built widget. The click is the user gesture that runs code.
  Future<void> _dispatch(Map<String, Object?> action) async {
    if (_running || _disposed) return;
    final runtime = await _starting;
    if (runtime == null || _disposed) return;
    final name = action['name'];
    final label = 'handle_event(${_quote('$name')}, ...)';
    setState(() => _running = true);
    try {
      if (!mounted) return;
      final threadApps = ProgramAppScope.maybeOf(context);
      _arena = PythonUiArena(
        workbenchEnabled: widget.onWorkbench != null,
        readFile: threadApps?.readFile,
        writeFile: threadApps?.writeFile,
      );
      final data = _ui?.model.allSurfaces.firstOrNull?.dataModel.get('/');
      var (output, ok) = await _execute(
        runtime,
        'handle_event(EVENT["name"], EVENT["context"])',
        widget.limits,
        checkSource: _editor.text,
        inputs: {
          'CLIENT': _clientViewport(),
          'EVENT': {'name': name, 'context': action['context'] ?? {}},
          'DATA': data ?? {},
        },
      );
      if (_disposed) return;
      if (_arena.workbench.rejected) {
        ok = false;
        output = _join(output, 'Workbench layout action limit (8) exceeded.');
      }
      if (ok && !_appRequested) {
        final error = _stageApp();
        if (error != null) {
          output = _join(output, error);
          ok = false;
        }
      }
      if (ok) {
        final rejected = _commit(_arena.staged);
        if (rejected != null) {
          output = _join(output, 'Surface rejected: $rejected');
          ok = false;
        }
      } else if (output.contains("'handle_event' is not defined")) {
        output = 'Define handle_event(name, context) to react to clicks.';
      }
      // Redraws update the existing view; only Run opens/reopens its window.
      if (ok && _arena.workbench.actions.isNotEmpty) await _publishWorkbench();
      if (_disposed) return;
      _record(label, output, ok: ok, header: 'Click: $name');
      if (!ok) _afterRun(_editor.text, output, ok: false);
    } finally {
      if (!_disposed) setState(() => _running = false);
    }
  }

  Map<String, Object?> _clientViewport() {
    final render = context.findRenderObject();
    final size = render is RenderBox && render.hasSize
        ? render.size
        : MediaQuery.sizeOf(context);
    return {'width': size.width.floor(), 'height': size.height.floor()};
  }

  /// One automatic layout action, in the same bounded transaction as Python's.
  String? _stageApp() {
    if (_arena.staged == null ||
        ProgramAppScope.maybeOf(context) == null ||
        widget.surfaceId == null ||
        widget.onWorkbench == null) {
      return null;
    }
    if (_arena.workbench.actions.length >= 8) {
      return 'Workbench layout action limit (8) exceeded '
          '(including app window).';
    }
    _arena.workbench.actions.insert(0, {'op': 'show_app'});
    return null;
  }

  Future<void> _publishWorkbench() async {
    if (_disposed) return;
    widget.writeResult?.call({
      'invocationId': 'gesture-${DateTime.now().microsecondsSinceEpoch}',
      'actions': _arena.workbench.actions,
    });
    await widget.onWorkbench?.call();
    if (_arena.workbench.actions.any((a) => a['op'] == 'show_app')) {
      _appRequested = true;
    }
  }

  Future<(String, bool)> _execute(
    MontyRuntime runtime,
    String code,
    ReplLimits limits, {
    Map<String, Object?>? inputs,
    String? checkSource,
  }) async {
    final ExecutionHandle handle;
    try {
      if (_typeCheck) {
        final clock = Stopwatch()..start();
        final error = await widget.checkTypes(
          checkSource ?? code,
          _resourceLimits,
        );
        clock.stop();
        if (!_disposed) {
          setState(() => _lastTypeCheckMs = clock.elapsedMicroseconds / 1000);
        }
        if (error != null) return (error, false);
        if (_disposed) return ('Stopped.', false);
      }
      handle = runtime.execute(code, os: _os, inputs: inputs);
    } on Object catch (error) {
      return ('$error', false);
    }
    _active = handle;
    String? printed;
    BridgeRunError? failure;
    final events = handle.events.listen((event) {
      if (event is BridgeRunFinished) printed = event.printOutput;
      if (event is BridgeRunError) {
        printed = event.printOutput;
        failure = event;
      }
    });
    var timedOut = false;
    final deadline = Timer(limits.deadline, () {
      timedOut = true;
      unawaited(handle.cancel());
    });
    try {
      final value = await handle.result;
      final shown = _repr(value);
      return (_join(printed, shown), true);
    } on Object catch (error) {
      if (timedOut) {
        return (
          _join(
            printed,
            'Stopped: exceeded the ${_seconds(limits.deadline)} deadline. '
            'Interpreter state was reset.',
          ),
          false,
        );
      }
      final message = failure?.displayMessage ?? _describe(error);
      final reset = _resetsSession(error)
          ? '\nInterpreter state was reset.'
          : '';
      return (_join(printed, '$message$reset'), false);
    } finally {
      deadline.cancel();
      _active = null;
      await events.cancel();
    }
  }

  void _record(
    String input,
    String output, {
    required bool ok,
    String? header,
  }) {
    final limits = widget.limits;
    final keep = limits.maxEntries;
    setState(() {
      if (!ok) _userOpenedEditor = false;
      _editorOpen = !ok || _userOpenedEditor;
      _entries.add(
        ReplEntry(
          input: input,
          output: _clip(output, limits.maxOutputChars),
          ok: ok,
          header: header ?? _runHeader(),
        ),
      );
      while (_entries.length > keep) {
        _entries.removeAt(0);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    if (widget.surfaceId case final id?) {
      _controlApps?.unbind(id, _programControls);
    }
    _chain?.removeListener(_onChain);
    final active = _active;
    if (active != null) unawaited(active.cancel());
    final starting = _starting;
    if (starting != null) {
      unawaited(
        starting.then(_disposeRuntime, onError: (Object _) {}),
      );
    }
    final view = _appView;
    final program = widget.surfaceId;
    if (view != null && program != null) {
      _apps?.remove(program, view);
      _apps?.unbindState(program);
    }
    _ui?.dispose();
    _editor.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controls = ProgramAppScope.maybeOf(context);
    if (widget.surfaceId case final id?) {
      if (!identical(controls, _controlApps)) {
        _controlApps?.unbind(id, _programControls);
      }
      _controlApps = controls;
      controls?.bind(id, _programControls);
    }
    final theme = Theme.of(context);
    final mono = context.monospaceOn(theme.textTheme.bodyMedium);
    // Keep static text and output out of the editor's accessible name.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Python (Monty sandbox)', style: theme.textTheme.labelMedium),
          const SizedBox(height: SoliplexSpacing.s2),
          if (widget.examples.isNotEmpty && !_runMode) ...[
            Wrap(
              spacing: SoliplexSpacing.s2,
              runSpacing: SoliplexSpacing.s2,
              children: [
                for (final example in widget.examples)
                  SoliplexChip.action(
                    key: ValueKey('python-repl-example:${example.label}'),
                    label: Text(example.label),
                    onPressed: () => load(example),
                  ),
              ],
            ),
            const SizedBox(height: SoliplexSpacing.s2),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: SoliplexButton.text(
              key: const ValueKey('python-repl-edit'),
              onPressed: () => setState(() {
                _editorOpen = !_editorOpen;
                _userOpenedEditor = _editorOpen;
              }),
              icon: Icon(_editorOpen ? Icons.expand_less : Icons.edit),
              child: Text(_editorOpen ? 'Hide code' : 'Edit code'),
            ),
          ),
          if (_editorOpen)
            Semantics(
              container: true,
              child: TextField(
                key: const ValueKey('python-repl-editor'),
                controller: _editor,
                onChanged: _onEdit,
                style: mono,
                minLines: 3,
                // Keep Run and output near the top of a workbench window;
                // longer source scrolls inside the editor.
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Python source',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: SoliplexSpacing.s2),
          _controls(),
          ..._repairStatus(),
          const SizedBox(height: SoliplexSpacing.s3),
          if (_entries.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: SoliplexButton.text(
                key: const ValueKey('python-repl-history'),
                onPressed: () => setState(() => _historyOpen = !_historyOpen),
                child: Text(
                  _historyOpen
                      ? 'Show latest run'
                      : 'Show run history (${_entries.length})',
                ),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(context.radii.sm),
              ),
              child: ListView(
                controller: _scroll,
                shrinkWrap: true,
                padding: const EdgeInsets.all(SoliplexSpacing.s3),
                children: [
                  if (_entries.isEmpty)
                    const Text('Press Run to execute the code.'),
                  for (final entry
                      in _historyOpen || _entries.isEmpty
                          ? _entries
                          : [_entries.last])
                    _EntryView(
                      key: ObjectKey(entry),
                      entry: entry,
                      showSource: widget.showSource,
                    ),
                ],
              ),
            ),
          ),
          if (_apps == null && _ui?.model.allSurfaces.firstOrNull != null) ...[
            // Standalone consumers without a workbench retain inline UI.
            const SizedBox(height: SoliplexSpacing.s3),
            Text('Surface built by Python', style: theme.textTheme.labelMedium),
            const SizedBox(height: SoliplexSpacing.s2),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(context.radii.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SoliplexSpacing.s3),
                child: A2uiSurface(
                  key: ObjectKey(_ui!.model.allSurfaces.first),
                  surface: _ui!.model.allSurfaces.first,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on _PythonReplViewState {
  Widget _controls() => Wrap(
    spacing: SoliplexSpacing.s3,
    runSpacing: SoliplexSpacing.s2,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SoliplexButton.filled(
        key: const ValueKey('python-repl-run'),
        onPressed: _running ? null : () => unawaited(run()),
        icon: const Icon(Icons.play_arrow),
        isLoading: _running,
        child: Text(switch ((_loading, _running)) {
          (true, _) => 'Loading Monty…',
          (_, true) => 'Running',
          _ => 'Run',
        }),
      ),
      Semantics(
        container: true,
        child: MergeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                key: const ValueKey('python-repl-auto-fix'),
                value: _aiFix,
                onChanged: _preferencesLoaded
                    ? (value) => _setAiFix(value ?? false)
                    : null,
              ),
              const Text('AI Fix'),
            ],
          ),
        ),
      ),
      Semantics(
        container: true,
        child: MergeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                key: const ValueKey('python-repl-type-check'),
                value: _typeCheck,
                onChanged: _preferencesLoaded && !_running
                    ? (value) => _setTypeCheck(value ?? false)
                    : null,
              ),
              const Text('Type check'),
            ],
          ),
        ),
      ),
      if (_lastTypeCheckMs case final ms?) Text('Type check: $ms ms.'),
      if (_repairable && _lastError != null)
        SoliplexButton.outlined(
          key: const ValueKey('python-repl-ai-fix'),
          onPressed: _running || _pending ? null : _fix,
          icon: const Icon(Icons.auto_fix_high),
          child: const Text('Fix now'),
        ),
      if (!_runMode)
        Text(
          _historyOpen ? '${_entries.length} entries shown' : 'Latest run',
        ),
    ],
  );

  /// Progress and the result of a chain; manual repair stays available.
  List<Widget> _repairStatus() {
    final chain = _chain;
    final line = switch (chain) {
      _ when _pending =>
        'Run failed. Asking the model to fix it '
            '(attempt $_requested of ${chain!.max})…',
      _ when _notRepaired => 'The model did not repair the program.',
      _ when _fixedAfter != null =>
        'Fixed after $_fixedAfter attempt${_fixedAfter == 1 ? '' : 's'}',
      final RepairChain c when _claimed != null && _running =>
        'Running the fixed code (attempt $_claimed of ${c.max})…',
      _ => null,
    };
    return [
      if (line != null) ...[
        const SizedBox(height: SoliplexSpacing.s2),
        Row(
          children: [
            Expanded(
              child: Text(line, key: const ValueKey('python-repl-repair')),
            ),
            if (_pending)
              SoliplexButton.text(
                key: const ValueKey('python-repl-stop'),
                onPressed: _end,
                child: const Text('Stop'),
              ),
          ],
        ),
      ],
    ];
  }
}

/// One transcript entry: a header, its output, and its code on request.
class _EntryView extends StatefulWidget {
  const _EntryView({
    required this.entry,
    required this.showSource,
    super.key,
  });

  final ReplEntry entry;
  final bool showSource;

  @override
  State<_EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends State<_EntryView> {
  late bool _open = widget.showSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = context.monospaceOn(theme.textTheme.bodyMedium);
    final entry = widget.entry;
    final status = entry.ok ? 'ok' : 'failed';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${entry.header} · $status',
                    key: const ValueKey('python-repl-entry-header'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: entry.ok ? null : theme.colorScheme.error,
                    ),
                  ),
                ),
                if (!widget.showSource)
                  SoliplexButton.text(
                    key: const ValueKey('python-repl-show-code'),
                    onPressed: () => setState(() => _open = !_open),
                    child: Text(_open ? 'Hide code' : 'Show code'),
                  ),
              ],
            ),
            if (_open)
              Semantics(
                container: true,
                child: SelectableText(_prompt(entry.input), style: mono),
              ),
            if (entry.output.isNotEmpty)
              // Flutter web exposes a read-only field's value only on focus;
              // the label makes the output readable by assistive technology.
              Semantics(
                container: true,
                label: entry.output,
                excludeSemantics: true,
                child: SelectableText(
                  entry.output,
                  style: mono.copyWith(
                    color: entry.ok
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _prompt(String input) {
  final lines = input.trimRight().split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      '${i == 0 ? '>>>' : '...'} ${lines[i]}',
  ].join('\n');
}

String _join(String? printed, String tail) {
  final head = (printed ?? '').trimRight();
  if (head.isEmpty) return tail;
  if (tail.isEmpty) return head;
  return '$head\n$tail';
}

String _clip(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}\n… (truncated)';

String _seconds(Duration d) => d.inMilliseconds % 1000 == 0
    ? '${d.inSeconds} s'
    : '${d.inMilliseconds} ms';

bool _resetsSession(Object error) =>
    error is MontyCrashedError ||
    (error is MontyError &&
        const {
          'MemoryError',
          'TimeoutError',
        }.contains(error.exception.excType));

String _describe(Object error) => switch (error) {
  final MontySyntaxError e => e.display(),
  final MontyRuntimeError e => e.display(),
  final MontyTypingError e => e.display(),
  _ => '$error',
};

/// Python-style repr of a result; empty for None.
String _repr(MontyValue value, [int depth = 0]) {
  if (depth > 8) return '...';
  String seq(List<MontyValue> values) =>
      values.take(100).map((v) => _repr(v, depth + 1)).join(', ') +
      (values.length > 100 ? ', ...' : '');
  return switch (value) {
    MontyNone() when depth == 0 => '',
    MontyNone() => 'None',
    MontyBool(:final value) => value ? 'True' : 'False',
    MontyString(:final value) => _quote(value),
    MontyList(:final items) => '[${seq(items)}]',
    MontyTuple(:final items) when items.length == 1 =>
      '(${_repr(items.single, depth + 1)},)',
    MontyTuple(:final items) => '(${seq(items)})',
    MontyDict(:final pairs) =>
      '{${pairs.take(100).map((p) => _pair(p, depth)).join(', ')}}',
    _ => '${value.dartValue}',
  };
}

String _pair((MontyValue, MontyValue) pair, int depth) =>
    '${_repr(pair.$1, depth + 1)}: ${_repr(pair.$2, depth + 1)}';

String _quote(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

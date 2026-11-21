import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Live, thread-local app views. Layout and execution remain with their owners.
class ProgramApps extends ChangeNotifier {
  Future<String> Function(String filename)? readFile;
  Future<void> Function(String filename, String text)? writeFile;
  final _state = <String, Object? Function()>{};

  void bindState(String program, Object? Function() read) =>
      _state[program] = read;
  void unbindState(String program) => _state.remove(program);

  /// A fresh copy includes bound input edits made since the last Python event.
  Map<String, Object?> snapshot() {
    final result = <String, Object?>{};
    for (final entry in _state.entries.take(12)) {
      final candidate = {...result, entry.key: entry.value()};
      if (utf8.encode(jsonEncode(candidate)).length <= 15000) {
        result[entry.key] = candidate[entry.key];
      }
    }
    return jsonDecode(jsonEncode(result)) as Map<String, Object?>;
  }

  final _views = <String, Widget>{};
  bool _closed = false;
  final _controls = <String, ProgramControls>{};

  ProgramControls? controls(String program) => _controls[program];
  void bind(String program, ProgramControls controls) =>
      _controls[program] = controls;
  void unbind(String program, ProgramControls controls) {
    if (identical(_controls[program], controls)) _controls.remove(program);
  }

  Widget? view(String program) => _views[program];

  void publish(String program, Widget view) {
    _views[program] = view;
    _changed();
  }

  void remove(String program, Widget view) {
    if (identical(_views[program], view)) {
      _views.remove(program);
      _changed();
    }
  }

  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_closed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _closed = true;
    _views.clear();
    _controls.clear();
    _state.clear();
    super.dispose();
  }
}

/// Shares app views between the program and its server-authorized window.
class ProgramAppScope extends InheritedWidget {
  const ProgramAppScope({required this.apps, required super.child, super.key});

  final ProgramApps apps;

  static ProgramApps? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ProgramAppScope>()?.apps;

  @override
  bool updateShouldNotify(ProgramAppScope oldWidget) => apps != oldWidget.apps;
}

/// An empty replay never creates an interpreter or dispatches an action.
class ProgramAppView extends StatelessWidget {
  const ProgramAppView({required this.program, required this.apps, super.key});

  final String program;
  final ProgramApps apps;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: apps,
    builder: (context, _) =>
        apps.view(program) ?? const Text('Press Run to open this app.'),
  );
}

/// Live controls owned by a mounted interpreter. Registration alone never runs it.
class ProgramControls {
  const ProgramControls({
    required this.source,
    required this.run,
    required this.event,
  });
  final String Function() source;
  final Future<void> Function() run;
  final Future<void> Function(String name) event;
}

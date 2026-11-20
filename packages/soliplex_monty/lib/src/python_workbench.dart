import 'dart:math';

import 'package:dart_monty/core.dart';

/// One user gesture's staged layout requests. Nothing mutates a client layout.
class PythonWorkbench {
  PythonWorkbench({required this.enabled});

  static const maxActions = 8;
  static const signatures = <String, List<String>>{
    'open_window': ['title', 'kind', 'content'],
    'move_window': ['window_id', 'order'],
    'close_window': ['window_id'],
  };

  final bool enabled;
  final List<Map<String, Object?>> actions = [];
  bool rejected = false;

  ExternalModule get module => ExternalModule({
    for (final entry in signatures.entries)
      entry.key: MontyHostFunction(entry.key, (positional, keywords) {
        if (!enabled || actions.length >= maxActions) {
          rejected = true;
          throw const ExternalException(
            'ValueError',
            'Workbench unavailable or layout action limit (8) exceeded.',
          );
        }
        final args = <String, Object?>{};
        if (positional.length > entry.value.length) {
          throw const ExternalException(
            'TypeError',
            'Too many workbench arguments.',
          );
        }
        for (var i = 0; i < positional.length; i++) {
          args[entry.value[i]] = positional[i].dartValue;
        }
        for (final arg in keywords.entries) {
          if (!entry.value.contains(arg.key) || args.containsKey(arg.key)) {
            throw const ExternalException(
              'TypeError',
              'Unknown or duplicate workbench argument.',
            );
          }
          args[arg.key] = arg.value.dartValue;
        }
        if (entry.key == 'open_window') {
          if (args['title'] is! String ||
              !['text', 'python'].contains(args['kind']) ||
              args['content'] is! String) {
            throw const ExternalException(
              'TypeError',
              'open_window(title, kind, content) needs strings; '
                  'kind is text or python.',
            );
          }
          final stamp = DateTime.now().microsecondsSinceEpoch;
          final nonce = Random.secure().nextInt(0x100000000);
          final id = 'wbp_${stamp}_$nonce';
          actions.add({'op': 'open', 'window_id': id, ...args});
          return MontyString(id);
        }
        if (args['window_id'] is! String) {
          throw const ExternalException(
            'TypeError',
            'A window id is required.',
          );
        }
        actions.add({
          'op': entry.key == 'move_window' ? 'move' : 'close',
          ...args,
        });
        return const MontyNone();
      }),
  });
}

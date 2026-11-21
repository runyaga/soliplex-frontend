import 'dart:convert';
import 'dart:math';

import 'package:dart_monty/core.dart';

/// One user gesture's staged layout requests. Nothing mutates a client layout.
class PythonWorkbench {
  PythonWorkbench({required this.enabled, this.readFile, this.writeFile});

  final Future<String> Function(String filename)? readFile;
  final Future<void> Function(String filename, String text)? writeFile;

  static const maxActions = 8;

  /// Maximum UTF-8 size of a thread file, shared with the server contract.
  static const int maxFileBytes = 8 * 1024 * 1024;
  static const signatures = <String, List<String>>{
    'read_file': ['filename'],
    'write_file': ['filename', 'text'],
    'open_window': ['title', 'kind', 'content'],
    'update_window': ['window_id', 'content'],
    'move_window': ['window_id', 'order'],
    'close_window': ['window_id'],
  };

  final bool enabled;
  final List<Map<String, Object?>> actions = [];
  bool rejected = false;

  ExternalModule get module => ExternalModule({
    for (final entry in signatures.entries)
      entry.key: MontyHostFunction(entry.key, (positional, keywords) async {
        if (!enabled ||
            (!['read_file', 'write_file'].contains(entry.key) &&
                actions.length >= maxActions)) {
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
        if (entry.key == 'read_file' || entry.key == 'write_file') {
          final filename = args['filename'];
          if (filename is! String ||
              !RegExp(
                r'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}\.(csv|md|txt|json)$',
              ).hasMatch(filename)) {
            throw const ExternalException(
              'ValueError',
              'Use a plain .csv, .md, .txt or .json filename.',
            );
          }
          try {
            if (entry.key == 'read_file' && readFile != null) {
              return MontyString(await readFile!(filename));
            }
            final text = args['text'];
            if (entry.key == 'write_file' &&
                writeFile != null &&
                text is String) {
              if (utf8.encode(text).length > maxFileBytes) {
                throw const ExternalException(
                  'ValueError',
                  'Write exceeds $maxFileBytes UTF-8 bytes.',
                );
              }
              await writeFile!(filename, text);
              return const MontyNone();
            }
          } on Object {
            throw const ExternalException(
              'ValueError',
              'Thread file request failed: check size and form CSV ownership.',
            );
          }
          throw const ExternalException(
            'ValueError',
            'Thread file transport unavailable or invalid text.',
          );
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
        if (entry.key == 'update_window' && args['content'] is! String) {
          throw const ExternalException(
            'TypeError',
            'Window content must be text.',
          );
        }
        actions.add({
          'op': switch (entry.key) {
            'move_window' => 'move',
            'update_window' => 'update',
            _ => 'close',
          },
          ...args,
        });
        return const MontyNone();
      }),
  });
}

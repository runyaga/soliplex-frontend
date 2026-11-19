import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_monty/core.dart';
import 'package:json_schema_builder/json_schema_builder.dart'
    hide ValidationResult;

/// Where the `PythonRepl` `files` property mounts each file in Python.
const roomMount = '/workspace/room';

/// Bounds on the `files` property of one `PythonRepl`.
const maxWorkspaceFiles = 4;
const int maxWorkspaceBytes = 512 * 1024;

const _namePattern = r'^[A-Za-z0-9][A-Za-z0-9._ -]{0,99}$';

/// Schema of the `PythonRepl` `files` property: `[{name, content}]`.
Schema workspaceFilesSchema() => Schema.fromMap({
  'type': 'array',
  'maxItems': maxWorkspaceFiles,
  'items': {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'pattern': _namePattern},
      'content': {'type': 'string', 'maxLength': maxWorkspaceBytes},
    },
    'required': ['name', 'content'],
    'additionalProperties': false,
  },
});

/// One text file a surface delivered, mounted at `/workspace/room/<name>`.
class WorkspaceFile {
  WorkspaceFile(this.name, String content)
    : bytes = Uint8List.fromList(utf8.encode(content)).asUnmodifiableView();

  final String name;
  final Uint8List bytes;

  String get path => '$roomMount/$name';
}

/// The files in a `files` property, or none when any entry is malformed,
/// a name repeats, or the bounds are exceeded.
List<WorkspaceFile> workspaceFiles(List<Object?> raw) {
  final files = <WorkspaceFile>[];
  final names = <String>{};
  var total = 0;
  final name = RegExp(_namePattern);
  for (final item in raw) {
    if (item case {
      'name': final String n,
      'content': final String content,
    } when name.hasMatch(n) && names.add(n)) {
      final file = WorkspaceFile(n, content);
      total += file.bytes.length;
      files.add(file);
    } else {
      return const [];
    }
  }
  if (files.length > maxWorkspaceFiles || total > maxWorkspaceBytes) {
    return const [];
  }
  return files;
}

/// A fresh handler that serves [files] read-only under `/workspace`.
OsHandler workspaceOsHandler(List<WorkspaceFile> files) => readOnlyOsHandler(
  OSAccess(files: [for (final f in files) ReadOnlyFile(f.path, f.bytes)]),
);

/// A mounted file whose writes and deletes raise `PermissionError`.
///
/// `OSAccess` moves a file on `Path.rename` and creates new files beside it
/// without calling the file, so this alone does not make a directory
/// read-only. [readOnlyOsHandler] does.
final class ReadOnlyFile implements AbstractFile {
  ReadOnlyFile(this.path, Uint8List bytes)
    : name = path.substring(path.lastIndexOf('/') + 1),
      _bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  @override
  String path;

  @override
  final String name;

  final Uint8List _bytes;

  @override
  int get permissions => 0x124; // 0o444

  @override
  bool get deleted => false;

  @override
  Object readContent() => _bytes;

  @override
  void writeContent(Object content) => throw _readOnlyError(path);

  @override
  void delete() => throw _readOnlyError(path);
}

ExternalException _readOnlyError(String path) => ExternalException(
  'PermissionError',
  "[Errno 30] Read-only file system: '$path'",
);

ExternalException _outsideError(String path) => ExternalException(
  'PermissionError',
  "[Errno 13] Permission denied: '$path'",
);

const _readCalls = {
  'Path.exists',
  'Path.is_file',
  'Path.is_dir',
  'Path.read_text',
  'Path.read_bytes',
  'Path.iterdir',
  'Path.scan',
  'Path.stat',
  'Path.resolve',
  'Path.absolute',
};

const _writeCalls = {
  'Path.write_text',
  'Path.write_bytes',
  'Path.append_text',
  'Path.append_bytes',
  'Path.mkdir',
  'Path.unlink',
  'Path.rmdir',
  'Path.rename',
};

/// Wraps [inner] so that file calls reach it only to read under [root].
///
/// A path outside [root], or one with a `..` segment, raises
/// `PermissionError` errno 13. A write, `mkdir`, `unlink`, `rmdir`,
/// `rename` or an `open` in any mode but read raises `PermissionError`
/// errno 30. Unknown `Path.*` calls are refused. Other OS calls pass through.
OsHandler readOnlyOsHandler(OSAccess inner, {String root = '/workspace'}) {
  final rootParts = _segments(root);

  void checkPath(MontyValue? arg) {
    final raw = _pathText(arg);
    final parts = _segments(raw.startsWith('/') ? raw : '/$raw');
    if (parts.contains('..') ||
        parts.length < rootParts.length ||
        !_startsWith(parts, rootParts)) {
      throw _outsideError(raw);
    }
  }

  return (name, args, kwargs) {
    final isOpen = name == 'open';
    if (!isOpen && !name.startsWith('Path.')) return inner(name, args, kwargs);
    if (name == 'Path.is_symlink') return const MontyBool(false);
    checkPath(args.firstOrNull);
    if (name == 'Path.rename') checkPath(args.elementAtOrNull(1));
    _checkReadOnly(name, args, kwargs);
    return inner(name, args, kwargs);
  };
}

void _checkReadOnly(
  String name,
  List<MontyValue> args,
  Map<String, MontyValue>? kwargs,
) {
  if (name == 'open') {
    final mode = switch (args.elementAtOrNull(1) ?? kwargs?['mode']) {
      MontyString(:final value) => value,
      _ => 'r',
    };
    if (!const {'r', 'rb', 'rt', 'br', 'tr'}.contains(mode)) {
      throw _readOnlyError(_pathText(args.firstOrNull));
    }
  } else if (_writeCalls.contains(name)) {
    throw _readOnlyError(_pathText(args.firstOrNull));
  } else if (!_readCalls.contains(name)) {
    throw ExternalException('PermissionError', 'unsupported call $name');
  }
}

String _pathText(MontyValue? arg) => switch (arg) {
  MontyString(:final value) || MontyPath(:final value) => value,
  MontyFileHandle(:final path) => path,
  _ => throw const ExternalException('TypeError', 'expected a path'),
};

List<String> _segments(String path) =>
    path.split('/').where((s) => s.isNotEmpty && s != '.').toList();

bool _startsWith(List<String> parts, List<String> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (parts[i] != prefix[i]) return false;
  }
  return true;
}

// Terminal panel — direct on-device Python execution, bypasses the LLM
// and bypasses the session lifecycle.
//
// The dialog owns its own [MontyRuntime], built from the shared
// [MontyExtensionSet]. That keeps the terminal usable the moment the
// user opens the room, even before any conversation has started — no
// "session must attach first" dance.
//
// State persists across runs *within* the dialog (the runtime stays
// alive until the dialog closes), so consecutive snippets can reference
// each other. State does NOT cross over to the LLM tool path; that uses
// its own session-scoped runtime. Treat the terminal as a scratch REPL,
// not a chat memory.

import 'dart:convert';

import 'package:dart_monty/dart_monty.dart' show MontyRuntime;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:soliplex_agent_monty/soliplex_agent_monty.dart'
    show MontyExtensionSet;

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.extensionSetFactory});

  /// Factory that returns a fresh [MontyExtensionSet] each call. The
  /// dialog calls it once in [initState] to build its own runtime;
  /// extension instances cannot be shared across runtimes because each
  /// runtime disposes its own. Pass `makeMontyExtensionSet` from
  /// `lib/src/monty_singleton.dart`.
  final MontyExtensionSet Function() extensionSetFactory;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  late final TextEditingController _input;
  late final MontyRuntime _runtime;
  final _historyScroll = ScrollController();
  final List<_TerminalEntry> _history = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
    _runtime = MontyRuntime(extensions: widget.extensionSetFactory().all);
  }

  @override
  void dispose() {
    _input.dispose();
    _historyScroll.dispose();
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final code = _input.text;
    if (code.trim().isEmpty || _running) return;
    setState(() {
      _running = true;
      _history.add(_TerminalEntry.input(code));
    });
    _scrollToBottom();
    try {
      final handle = _runtime.execute(code);
      final result = await handle.result;
      if (!mounted) return;
      setState(() {
        _history.add(_TerminalEntry.result(
          output: result.printOutput ?? '',
          value: result.value.toJson(),
          error: result.error?.toJson(),
        ));
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _history.add(_TerminalEntry.dartError(e.toString()));
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _input.clear();
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_historyScroll.hasClients) return;
      _historyScroll.animateTo(
        _historyScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              onClose: () => Navigator.of(context).pop(),
              onClear: _history.isEmpty
                  ? null
                  : () => setState(_history.clear),
            ),
            Expanded(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: _history.isEmpty
                    ? Center(
                        child: Text(
                          'Paste Python and press ⌘/Ctrl + Enter to run.\n'
                          'Bypasses the LLM — runs directly on the on-device '
                          'monty runtime attached to this session.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _historyScroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _history.length,
                        itemBuilder: (_, i) =>
                            _EntryView(entry: _history[i], textStyle: mono),
                      ),
              ),
            ),
            const Divider(height: 1),
            _InputArea(
              controller: _input,
              running: _running,
              onRun: _run,
              textStyle: mono,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, this.onClear});
  final VoidCallback onClose;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 18),
          const SizedBox(width: 8),
          Text(
            'Monty terminal — on-device Python',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          if (onClear != null)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('Clear'),
            ),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
    );
  }
}

class _InputArea extends StatelessWidget {
  const _InputArea({
    required this.controller,
    required this.running,
    required this.onRun,
    required this.textStyle,
  });

  final TextEditingController controller;
  final bool running;
  final VoidCallback onRun;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _RunIntent(),
                SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _RunIntent(),
              },
              child: Actions(
                actions: {
                  _RunIntent: CallbackAction<_RunIntent>(
                    onInvoke: (_) {
                      if (!running) onRun();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: controller,
                  enabled: !running,
                  minLines: 3,
                  maxLines: 12,
                  style: textStyle,
                  decoration: const InputDecoration(
                    hintText: 'print(1 + 1)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: running ? null : onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow, size: 18),
            label: Text(running ? 'Running…' : 'Run'),
          ),
        ],
      ),
    );
  }
}

class _RunIntent extends Intent {
  const _RunIntent();
}

// ---------------------------------------------------------------------------
// History entries
// ---------------------------------------------------------------------------

sealed class _TerminalEntry {
  const _TerminalEntry();
  factory _TerminalEntry.input(String code) = _InputEntry;
  factory _TerminalEntry.result({
    required String output,
    Object? value,
    Object? error,
  }) = _ResultEntry;
  factory _TerminalEntry.dartError(String message) = _DartErrorEntry;
}

class _InputEntry extends _TerminalEntry {
  const _InputEntry(this.code);
  final String code;
}

class _ResultEntry extends _TerminalEntry {
  const _ResultEntry({required this.output, this.value, this.error});
  final String output;
  final Object? value;
  final Object? error;
}

class _DartErrorEntry extends _TerminalEntry {
  const _DartErrorEntry(this.message);
  final String message;
}

class _EntryView extends StatelessWidget {
  const _EntryView({required this.entry, required this.textStyle});
  final _TerminalEntry entry;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: switch (entry) {
        _InputEntry(:final code) => _Block(
            label: '>>>',
            labelColor: scheme.primary,
            text: code,
            textStyle: textStyle,
          ),
        _ResultEntry(
          :final output,
          :final value,
          :final error,
        ) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (output.isNotEmpty)
                _Block(
                  label: 'output',
                  labelColor: scheme.onSurfaceVariant,
                  text: output,
                  textStyle: textStyle,
                ),
              if (value != null && value is! Map ||
                  (value is Map && value.isNotEmpty))
                _Block(
                  label: 'value',
                  labelColor: scheme.tertiary,
                  text: const JsonEncoder.withIndent('  ').convert(value),
                  textStyle: textStyle,
                ),
              if (error != null)
                _Block(
                  label: 'error',
                  labelColor: scheme.error,
                  text: error is Map
                      ? const JsonEncoder.withIndent('  ').convert(error)
                      : error.toString(),
                  textStyle: textStyle,
                ),
            ],
          ),
        _DartErrorEntry(:final message) => _Block(
            label: 'dart-error',
            labelColor: scheme.error,
            text: message,
            textStyle: textStyle,
          ),
      },
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.label,
    required this.labelColor,
    required this.text,
    required this.textStyle,
  });

  final String label;
  final Color labelColor;
  final String text;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(text, style: textStyle),
        ],
      ),
    );
  }
}

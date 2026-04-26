import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'narration.dart';
import 'narration_singleton.dart';

/// Narration log. A scrolling panel that sits below the map drawer
/// and shows running script chatter, attributed to one of four
/// rendering buckets (COORDINATOR / PRIMARY / SECONDARY / FIELD).
/// Each new entry from `narrate_say(...)` appears at the bottom; the
/// list auto-scrolls.
class NarrationPanel extends StatefulWidget {
  const NarrationPanel({super.key});

  @override
  State<NarrationPanel> createState() => _NarrationPanelState();
}

class _NarrationPanelState extends State<NarrationPanel> {
  final _scroll = ScrollController();
  int _lastSeenLength = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd(int length) {
    if (length == _lastSeenLength) return;
    _lastSeenLength = length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final entries = narrationController.entries.value;
      _scrollToEnd(entries.length);
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E12),
          border: Border(
            top: BorderSide(color: const Color(0xFF1F2A36), width: 1),
            bottom: BorderSide(color: const Color(0xFF1F2A36), width: 1),
          ),
        ),
        child: entries.isEmpty
            ? const _Empty()
            : ListView.builder(
                controller: _scroll,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: entries.length,
                itemBuilder: (_, i) => _Line(entry: entries[i]),
              ),
      );
    });
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'NARRATION LOG — quiet',
        style: TextStyle(
          color: Color(0xFF607080),
          fontFamily: 'monospace',
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.entry});

  final Narration entry;

  @override
  Widget build(BuildContext context) {
    final ts = entry.createdAt;
    final stamp =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: stamp,
              style: const TextStyle(color: Color(0xFF5A6B7C)),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: '[${entry.actor.label}]',
              style: TextStyle(
                color: entry.actor.color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: entry.text,
              style: const TextStyle(color: Color(0xFFE6EDF3)),
            ),
          ],
        ),
      ),
    );
  }
}

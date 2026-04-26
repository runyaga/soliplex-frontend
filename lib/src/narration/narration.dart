import 'package:flutter/widgets.dart' show Color;
import 'package:meta/meta.dart';

/// A voice on a narration log. Each actor renders distinctly so the
/// reader can scan a running log without parsing names.
///
/// Generic-purpose roles, suitable for any scripted-narrative demo —
/// humanitarian operations, scientific expeditions, logistics, support
/// hand-offs. Demos pick the labels that fit their story by passing
/// strings to [parse]; the four enum values are the rendering buckets.
enum NarrationActor {
  /// Coordinating / headquarters voice. Big-picture orders, status
  /// roll-ups, dispatch. Calm, authoritative, white.
  coordinator(label: 'COORDINATOR', argbHex: 0xFFFFFFFF),

  /// Primary actor — the entity in motion (vehicle, team, agent). Most
  /// of the live SITREP traffic comes from here. Yellow.
  primary(label: 'PRIMARY', argbHex: 0xFFFFE066),

  /// Secondary actor — a paired or supporting entity (escort vehicle,
  /// partner team, second agent). Flank reports, area sweep. Sky-blue.
  secondary(label: 'SECONDARY', argbHex: 0xFF66C7FF),

  /// Field / on-site / ground reporter — the recipient or local
  /// element giving terse status from the operating area. Orange.
  field(label: 'FIELD', argbHex: 0xFFFFA040);

  const NarrationActor({required this.label, required this.argbHex});

  /// Display label shown in the panel.
  final String label;

  /// Voice color encoded as a 0xAARRGGBB constant.
  final int argbHex;

  /// Convenience accessor for widget code.
  Color get color => Color(argbHex);

  /// Resolve from a script-side string. Tolerant — falls back to
  /// [primary] if a script passes something unrecognised so the
  /// narration still appears.
  static NarrationActor parse(String? raw) {
    if (raw == null) return NarrationActor.primary;
    final n =
        raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (n) {
      'coordinator' ||
      'coord' ||
      'hq' ||
      'base' ||
      'control' ||
      'dispatch' =>
        NarrationActor.coordinator,
      'primary' || 'lead' || 'main' || 'one' || '1' => NarrationActor.primary,
      'secondary' ||
      'support' ||
      'wing' ||
      'two' ||
      '2' =>
        NarrationActor.secondary,
      'field' ||
      'ground' ||
      'site' ||
      'reporter' ||
      'local' =>
        NarrationActor.field,
      _ => NarrationActor.primary,
    };
  }
}

/// A single line on the narration log.
@immutable
class Narration {
  const Narration({
    required this.id,
    required this.actor,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final NarrationActor actor;
  final String text;
  final DateTime createdAt;
}

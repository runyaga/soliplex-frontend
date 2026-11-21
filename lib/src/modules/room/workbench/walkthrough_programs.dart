import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

/// Byte-for-byte allowlist of the backend's curated monty_gui_demo.py.
/// A publication, editor change or model repair cannot grant itself consent.
class WalkthroughPrograms {
  static const montyGuiDigest =
      '4e44af032efeb79954357e0ac15d4a5d2b93ba8c62a4261c20beae4df542adc0';

  static bool accepts(String source) =>
      sha256.convert(utf8.encode(source)).toString() == montyGuiDigest;

  static Future<void> perform(ProgramControls controls, String effect) {
    if (!accepts(controls.source())) {
      throw StateError(
          'Walkthrough refused a program outside its curated source');
    }
    if (effect == 'run') return controls.run();
    if (!const {'plus', 'add_point', 'open_log'}.contains(effect)) {
      throw StateError('Unknown walkthrough program action');
    }
    return controls.event(effect);
  }
}

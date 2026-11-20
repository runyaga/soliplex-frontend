import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

/// Byte-for-byte allowlist of the backend's curated monty_gui_demo.py.
/// A publication, editor change or model repair cannot grant itself consent.
class WalkthroughPrograms {
  static const montyGuiDigest =
      '5937b6c319acf6f4ae807ba39af2f6097768e8611d634be338943bc108eb4e07';

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

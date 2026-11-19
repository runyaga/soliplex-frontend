import 'dart:ui_web' as ui_web;

const _workerKey = 'packages/dart_monty/lib/assets/dart_monty_worker.js';

/// The dart_monty worker directory under the Flutter asset base.
///
/// A cache-busted build serves assets below a versioned directory, which the
/// worker's page-relative default path does not reach.
String? montyWorkerBase() {
  final script = ui_web.assetManager.getAssetUrl(_workerKey);
  return script.substring(0, script.lastIndexOf('/'));
}

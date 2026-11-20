import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/workbench/surface_mount_registry.dart';

void main() {
  test(
    'keeps mount identity across moves and removes only absent identities',
    () {
      final registry = SurfaceMountRegistry();
      final original = registry.keyFor('activity1', 'surface1');
      expect(registry.keyFor('activity1', 'surface1'), same(original));
      registry.retain(['activity1\u0000surface1']);
      expect(registry.keyFor('activity1', 'surface1'), same(original));
      registry.retain([]);
      expect(registry.length, 0);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';

import 'package:soliplex_frontend/src/modules/room/a2ui/surface_scope.dart';

void main() {
  test('thread app snapshot reads current edits and removes disposed programs',
      () {
    final apps = ProgramApps();
    final store = ChatSurfaceStore()..programSnapshot = apps.snapshot;
    var data = <String, Object?>{
      'items': ['Buy tea']
    };
    apps.bindState('todo', () => data);
    expect(store.programSnapshot!()['todo'], {
      'items': ['Buy tea']
    });
    data = {
      'items': ['Buy tea', 'Call Sam']
    };
    final copy = store.programSnapshot!();
    data['items'] = ['Updated'];
    expect(copy['todo'], {
      'items': ['Buy tea', 'Call Sam']
    });
    apps.unbindState('todo');
    expect(store.programSnapshot!(), isEmpty);
    apps.bindState('large', () => {'text': 'x' * 16000});
    expect(store.programSnapshot!(), isEmpty);
    store.dispose();
    apps.dispose();
  });
}

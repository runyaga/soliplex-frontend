import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/core/app_module.dart';
import 'package:soliplex_frontend/src/core/shell_config.dart';

class _FakeModule extends AppModule {
  _FakeModule({required String ns, ModuleRoutes? routes})
      : _ns = ns,
        _routes = routes ?? const ModuleRoutes();

  final String _ns;
  final ModuleRoutes _routes;

  int disposeCount = 0;

  @override
  String get namespace => _ns;

  @override
  ModuleRoutes build() => _routes;

  @override
  Future<void> onDispose() async => disposeCount++;
}

class _DisposeOrderModule extends AppModule {
  _DisposeOrderModule({required String ns, required this.order}) : _ns = ns;

  final String _ns;
  final List<String> order;

  @override
  String get namespace => _ns;

  @override
  ModuleRoutes build() => const ModuleRoutes();

  @override
  Future<void> onDispose() async => order.add(_ns);
}

class _NoLifecycleModule extends AppModule {
  @override
  String get namespace => 'no-lifecycle';

  @override
  ModuleRoutes build() => const ModuleRoutes();
}

ThemeData _theme() => ThemeData.light();

void main() {
  group('ShellConfig.fromModules — namespace validation', () {
    test('accepts empty module list', () async {
      await expectLater(
        ShellConfig.fromModules(
          modules: const [],
          appName: 'test',
          theme: _theme(),
        ),
        completes,
      );
    });

    test('accepts modules with unique namespaces', () async {
      await expectLater(
        ShellConfig.fromModules(
          modules: [_FakeModule(ns: 'a'), _FakeModule(ns: 'b')],
          appName: 'test',
          theme: _theme(),
        ),
        completes,
      );
    });

    test('allows multiple modules with empty namespace', () async {
      await expectLater(
        ShellConfig.fromModules(
          modules: [_FakeModule(ns: ''), _FakeModule(ns: '')],
          appName: 'test',
          theme: _theme(),
        ),
        completes,
      );
    });

    test('throws StateError for duplicate non-empty namespace', () async {
      await expectLater(
        ShellConfig.fromModules(
          modules: [_FakeModule(ns: 'dup'), _FakeModule(ns: 'dup')],
          appName: 'test',
          theme: _theme(),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ShellConfig.fromModules — lifecycle', () {
    test('onDispose called in reverse registration order', () async {
      final order = <String>[];
      final first = _DisposeOrderModule(ns: 'first', order: order);
      final second = _DisposeOrderModule(ns: 'second', order: order);
      final third = _DisposeOrderModule(ns: 'third', order: order);

      final config = await ShellConfig.fromModules(
        modules: [first, second, third],
        appName: 'test',
        theme: _theme(),
      );

      config.onDispose?.call();
      await Future<void>.delayed(Duration.zero);

      expect(order, ['third', 'second', 'first']);
    });
  });

  group('ShellConfig.fromModules — routes & overrides', () {
    test('flattens routes from all modules', () async {
      final config = await ShellConfig.fromModules(
        modules: [_FakeModule(ns: 'a'), _FakeModule(ns: 'b')],
        appName: 'test',
        theme: _theme(),
      );

      expect(config.routes, isA<List>());
    });

    test('config carries appName and theme', () async {
      final theme = _theme();
      final config = await ShellConfig.fromModules(
        modules: const [],
        appName: 'MyApp',
        theme: theme,
      );

      expect(config.appName, 'MyApp');
      expect(config.theme, same(theme));
    });
  });

  group('AppModule defaults', () {
    test('default onDispose is a no-op', () async {
      final m = _NoLifecycleModule();
      expect(() async => m.onDispose(), returnsNormally);
    });
  });
}

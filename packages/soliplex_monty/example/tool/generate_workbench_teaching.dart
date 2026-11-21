import 'dart:convert';
import 'dart:io';

import 'package:a2ui_agent/a2ui_agent.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_monty/src/bindings/host_bindings.dart';
import 'package:soliplex_monty_app/workbench_catalogs.dart';

/// Generated from the same implementations the host and Python arena register.
Map<String, Object?> workbenchTeaching() {
  final catalogs = [
    basicCatalog(),
    ...workbenchCatalogs(),
    chartGraphicsCatalog(),
  ];
  return {
    'generator': 'a2ui_agent-0.4.0',
    'catalogs': [for (final catalog in catalogs) catalog.toJson()],
    'catalogTeaching': ExpressFormat(catalogs).promptGenerator.generate(),
    'pythonSignatures': {
      for (final module in moduleBindings.values)
        for (final binding in module.functions)
          '${module.name == 'ui' ? '' : '${module.name.replaceFirst('ui.', '')}.'}${binding.name}':
              binding.stub,
    },
  };
}

void main(List<String> args) {
  final target = File(
    'workbench/backend/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench/catalog_teaching.json',
  );
  final expected =
      '${const JsonEncoder.withIndent('  ').convert(workbenchTeaching())}\n';
  if (args.contains('--check') ||
      Platform.environment['WB_CHECK_TEACHING'] == '1') {
    if (!target.existsSync() || target.readAsStringSync() != expected) {
      stderr.writeln(
        'Workbench catalog teaching drift: regenerate catalog_teaching.json',
      );
      exitCode = 1;
    }
  } else {
    target.writeAsStringSync(expected);
  }
}

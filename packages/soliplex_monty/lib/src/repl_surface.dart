import 'package:a2ui_core/a2ui_core.dart';

import 'package:soliplex_monty/src/lab_catalog.dart';
import 'package:soliplex_monty/src/repl_examples.dart';

/// Builds the PythonRepl sample surface. The payload sets source text only.
List<Map<String, Object?>> pythonReplSurfaceMessages() => [
  {
    'version': '1.0',
    'createSurface': {'surfaceId': 'repl', 'catalogId': BasicCatalog.v1_0Id},
  },
  {
    'version': '1.0',
    'updateDataModel': {
      'surfaceId': 'repl',
      'path': '/',
      'value': {
        'repl': {'source': 'x = sum(range(10))\nprint(x)\nx * 2'},
      },
    },
  },
  {
    'version': '1.0',
    'updateComponents': {
      'surfaceId': 'repl',
      'components': [
        {
          'id': 'root',
          'component': 'Column',
          'children': ['title', 'repl'],
        },
        {'id': 'title', 'component': 'Text', 'text': 'Try Python locally'},
        {
          'id': 'repl',
          'component': 'PythonRepl',
          'catalogId': labCatalogId,
          'source': {'@path': '/repl/source'},
          'outputPath': '/repl/result',
          'examples': replExamples,
          'onRun': {
            'event': {
              'name': 'python_ran',
              'context': {
                'result': {'@path': '/repl/result'},
              },
            },
          },
        },
      ],
    },
  },
];

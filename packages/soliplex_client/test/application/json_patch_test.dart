import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('applyJsonPatch', () {
    group('add operation', () {
      test('adds value to root level', () {
        final state = <String, dynamic>{'existing': 'value'};
        final operations = [
          {'op': 'add', 'path': '/new', 'value': 'added'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['existing'], 'value');
        expect(result['new'], 'added');
      });

      test('rejects nested add when intermediate path does not exist', () {
        // RFC 6902 §A.12 — `add` requires the parent to exist. The
        // homegrown impl auto-created intermediates; the package
        // (`json_patch`) is strict-to-spec. Production callers
        // (AG-UI server) emit spec-compliant patches with valid
        // parents, so this is no production regression — failing
        // patches are logged and the state is returned unchanged.
        final state = <String, dynamic>{};
        final operations = [
          {'op': 'add', 'path': '/a/b/c', 'value': 'deep'},
        ];

        final result = applyJsonPatch(state, operations);

        // Patch fails silently; state is unchanged.
        expect(result, equals(state));
      });

      test('adds item to array at end', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/2', 'value': 'c'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'b', 'c']);
      });

      test('appends to array using RFC 6902 "-" syntax', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/-', 'value': 'c'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'b', 'c']);
      });

      test('appends to nested array using "-" syntax', () {
        final state = <String, dynamic>{
          'rag': {
            'citations': ['chunk-1'],
          },
        };
        final operations = [
          {'op': 'add', 'path': '/rag/citations/-', 'value': 'chunk-2'},
        ];

        final result = applyJsonPatch(state, operations);

        final citations =
            (result['rag'] as Map<String, dynamic>)['citations'] as List;
        expect(citations, equals(['chunk-1', 'chunk-2']));
      });

      test('inserts item in array at index per RFC 6902', () {
        final state = <String, dynamic>{
          'items': ['a', 'b', 'c'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/1', 'value': 'inserted'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'inserted', 'b', 'c']);
      });
    });

    group('replace operation', () {
      test('replaces existing value', () {
        final state = <String, dynamic>{'key': 'old'};
        final operations = [
          {'op': 'replace', 'path': '/key', 'value': 'new'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'new');
      });

      test('replaces nested value', () {
        final state = <String, dynamic>{
          'outer': {'inner': 'old'},
        };
        final operations = [
          {'op': 'replace', 'path': '/outer/inner', 'value': 'new'},
        ];

        final result = applyJsonPatch(state, operations);

        final outer = result['outer'] as Map<String, dynamic>;
        expect(outer['inner'], 'new');
      });
    });

    group('remove operation', () {
      test('removes value at root level', () {
        final state = <String, dynamic>{'keep': 'yes', 'remove': 'no'};
        final operations = [
          {'op': 'remove', 'path': '/remove'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result.containsKey('keep'), isTrue);
        expect(result.containsKey('remove'), isFalse);
      });

      test('removes nested value', () {
        final state = <String, dynamic>{
          'outer': {'keep': 'yes', 'remove': 'no'},
        };
        final operations = [
          {'op': 'remove', 'path': '/outer/remove'},
        ];

        final result = applyJsonPatch(state, operations);

        final outer = result['outer'] as Map<String, dynamic>;
        expect(outer['keep'], 'yes');
        expect(outer.containsKey('remove'), isFalse);
      });

      test('removes item from array', () {
        final state = <String, dynamic>{
          'items': ['a', 'b', 'c'],
        };
        final operations = [
          {'op': 'remove', 'path': '/items/1'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'c']);
      });
    });

    group('multiple operations', () {
      test('applies operations in sequence', () {
        final state = <String, dynamic>{'count': 0};
        final operations = [
          {'op': 'add', 'path': '/name', 'value': 'test'},
          {'op': 'replace', 'path': '/count', 'value': 1},
          {'op': 'add', 'path': '/items', 'value': <dynamic>[]},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['count'], 1);
        expect(result['name'], 'test');
        expect(result['items'], isEmpty);
      });
    });

    group('error handling', () {
      test('skips invalid operation (not a map)', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          'not a map',
          {'op': 'add', 'path': '/new', 'value': 'added'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'value');
        expect(result['new'], 'added');
      });

      test('skips operation with missing op', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'path': '/key', 'value': 'changed'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'value');
      });

      test('skips operation with missing path', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'op': 'add', 'value': 'changed'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'value');
      });

      test('skips unsupported operations (move, copy, test)', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'op': 'move', 'from': '/key', 'path': '/newKey'},
          {'op': 'copy', 'from': '/key', 'path': '/keyCopy'},
          {'op': 'test', 'path': '/key', 'value': 'value'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result, equals({'key': 'value'}));
      });
    });

    group('immutability', () {
      test('does not modify original state', () {
        final state = <String, dynamic>{
          'nested': {'value': 'original'},
        };
        final operations = [
          {'op': 'replace', 'path': '/nested/value', 'value': 'modified'},
        ];

        applyJsonPatch(state, operations);

        final nested = state['nested'] as Map<String, dynamic>;
        expect(nested['value'], 'original');
      });

      test('does not modify original arrays', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/2', 'value': 'c'},
        ];

        applyJsonPatch(state, operations);

        expect(state['items'], ['a', 'b']);
      });
    });

    group('intermediate container creation', () {
      // The homegrown impl auto-created intermediate Lists when a path
      // segment was followed by a numeric index or "-". The package
      // (`json_patch`) is strict-to-spec and rejects such patches when
      // the parent is missing. AG-UI server emits well-formed patches,
      // so production never relied on this leniency.
      test('rejects intermediate List creation (numeric index)', () {
        final state = <String, dynamic>{};
        final operations = [
          {'op': 'add', 'path': '/rag/citations/0', 'value': 'chunk-1'},
        ];
        final result = applyJsonPatch(state, operations);
        expect(result, equals(state));
      });

      test('rejects intermediate List creation ("-" syntax)', () {
        final state = <String, dynamic>{};
        final operations = [
          {'op': 'add', 'path': '/data/items/-', 'value': 'first'},
        ];
        final result = applyJsonPatch(state, operations);
        expect(result, equals(state));
      });
    });

    group('edge cases', () {
      test('handles empty path', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'op': 'add', 'path': '', 'value': 'ignored'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result, equals({'key': 'value'}));
      });

      test('handles invalid array index beyond bounds', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/10', 'value': 'out of bounds'},
        ];

        // Should handle gracefully - either skip or extend
        final result = applyJsonPatch(state, operations);

        // Verify original items preserved
        final items = result['items'] as List;
        expect(items.contains('a'), isTrue);
        expect(items.contains('b'), isTrue);
      });

      test('handles negative array index', () {
        final state = <String, dynamic>{
          'items': ['a', 'b', 'c'],
        };
        final operations = [
          {'op': 'remove', 'path': '/items/-1'},
        ];

        // Should handle gracefully - skip invalid operation
        final result = applyJsonPatch(state, operations);

        // Original array should be unchanged since -1 is not a valid index
        expect(result['items'], ['a', 'b', 'c']);
      });

      test('handles non-numeric array index', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/notanumber', 'value': 'invalid'},
        ];

        // Should handle gracefully
        final result = applyJsonPatch(state, operations);

        // Array should be unchanged
        expect(result['items'], ['a', 'b']);
      });

      test('replaces entire state via empty-path (RFC 6902 root)', () {
        // RFC 6902 § 4: the empty string "" refers to the root. The
        // homegrown impl also accepted "/" as root (lenient); the
        // package is strict and treats "/" as the empty-string key.
        // AG-UI server emits empty-path patches for root replace.
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {
            'op': 'replace',
            'path': '',
            'value': {'new': 'state'},
          },
        ];

        final result = applyJsonPatch(state, operations);

        expect(result, equals({'new': 'state'}));
      });

      test('handles complex nested structures', () {
        final state = <String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{
              'c1': {
                'chunk_id': 'c1',
                'content': 'first',
                'document_id': 'd1',
                'document_uri': 'uri',
              },
            },
            'citations': <dynamic>['c1'],
          },
        };
        final operations = [
          {'op': 'add', 'path': '/rag/citations/-', 'value': 'c2'},
          {'op': 'add', 'path': '/rag/citations/-', 'value': 'c3'},
          {
            'op': 'add',
            'path': '/rag/citation_index/c2',
            'value': {
              'chunk_id': 'c2',
              'content': 'second',
              'document_id': 'd2',
              'document_uri': 'uri',
            },
          },
        ];

        final result = applyJsonPatch(state, operations);

        final rag = result['rag'] as Map<String, dynamic>;
        final citations = rag['citations'] as List<dynamic>;
        expect(citations, equals(['c1', 'c2', 'c3']));
        final citationIndex = rag['citation_index'] as Map<String, dynamic>;
        expect(citationIndex.containsKey('c2'), isTrue);
      });
    });
  });

  group('diffJsonPatch', () {
    test('equal maps produce empty diff', () {
      const a = {'k': 1};
      const b = {'k': 1};
      expect(diffJsonPatch(a, b), isEmpty);
    });

    test('add a key produces an add op', () {
      const a = <String, dynamic>{};
      const b = {'k': 1};
      final ops = diffJsonPatch(a, b);
      expect(ops, hasLength(1));
      expect(ops.single['op'], 'add');
      expect(ops.single['path'], '/k');
      expect(ops.single['value'], 1);
    });

    test('change a value produces a replace op', () {
      const a = {'k': 1};
      const b = {'k': 2};
      final ops = diffJsonPatch(a, b);
      expect(ops, hasLength(1));
      expect(ops.single['op'], 'replace');
      expect(ops.single['path'], '/k');
      expect(ops.single['value'], 2);
    });

    test('drop a key produces a remove op', () {
      const a = {'k': 1, 'j': 2};
      const b = {'j': 2};
      final ops = diffJsonPatch(a, b);
      expect(ops, hasLength(1));
      expect(ops.single['op'], 'remove');
      expect(ops.single['path'], '/k');
    });

    test('roundtrip: applying the diff to before equals after', () {
      const before = {
        'ui': {
          'narrations': [
            {'actor': 'primary', 'text': 'one'},
          ],
          'hud': {'banner': 'standing by'},
        },
      };
      const after = {
        'ui': {
          'narrations': [
            {'actor': 'primary', 'text': 'one'},
            {'actor': 'field', 'text': 'two'},
          ],
          'hud': {'banner': 'underway'},
        },
      };

      final ops = diffJsonPatch(before, after);
      expect(ops, isNotEmpty);

      final reconstructed = applyJsonPatch(before, ops);
      expect(reconstructed, equals(after));
    });
  });
}

import 'package:soliplex_client/src/domain/workbench_snapshot.dart';
import 'package:test/test.dart';

void main() {
  test(
    'copies nested input and keeps publication parts by stable identity',
    () {
      final source = <String, dynamic>{
        'revision': 3,
        'layout': <String, dynamic>{
          'schemaVersion': 1,
          'layoutRevision': 3,
          'nodes': <Object?>[],
        },
        'registrations': <Object?>[
          {
            'role': 'content',
            'activityMessageId': 'a1',
            'surfaceId': 's1',
          },
        ],
        'records': <Object?>[
          {
            'recordId': 'r1',
            'sequence': 4,
            'partIndex': 1,
            'partCount': 2,
            'content': {'n': 2},
          },
          {
            'recordId': 'r1',
            'sequence': 4,
            'partIndex': 0,
            'partCount': 2,
            'content': {'n': 1},
          },
        ],
      };
      final snapshot = WorkbenchSnapshot.fromJson(source);
      (source['records'] as List).clear();
      expect(snapshot.records.map((record) => record.partIndex), [0, 1]);
      expect(snapshot.records.first.identity, 'r1:0/2');
      expect(
        () => snapshot.records.first.content['n'] = 5,
        throwsUnsupportedError,
      );
    },
  );

  test('rejects unknown roles and malformed registration metadata', () {
    expect(
      () => WorkbenchRegistration.fromJson({
        'role': 'admin',
        'activityMessageId': 'a1',
        'surfaceId': 's1',
      }),
      throwsFormatException,
    );
    expect(
      () => WorkbenchRegistration.fromJson({
        'role': 'content',
        'surfaceId': 's1',
      }),
      throwsFormatException,
    );
  });
}

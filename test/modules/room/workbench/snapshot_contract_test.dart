import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import '../../../fixtures/workbench/workbench_fixtures.g.dart';

/// The server's snapshot route output parses with the client's strict parser.
void main() {
  test('fresh-thread snapshot fixture parses with the default layout', () {
    final snapshot = WorkbenchSnapshot.fromJson(
      jsonDecode(workbenchFixtures['snapshot_fresh_v1.json']!)
          as Map<String, dynamic>,
    );
    expect(snapshot.revision, 0);
    expect(snapshot.records, isEmpty);
    expect(snapshot.layout['rootId'], 'wb_root');
  });

  test('snapshot with a form and a chart parses with consistent parts', () {
    final snapshot = WorkbenchSnapshot.fromJson(
      jsonDecode(workbenchFixtures['snapshot_content_v1.json']!)
          as Map<String, dynamic>,
    );
    expect(snapshot.revision, 2);
    expect(snapshot.records, hasLength(2));
    expect(snapshot.registrations, hasLength(3));
  });
}

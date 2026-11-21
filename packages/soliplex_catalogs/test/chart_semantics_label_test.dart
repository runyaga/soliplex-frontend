import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_catalogs/src/chart_semantics.dart';

void main() {
  const spec = {
    'kind': 'scatter',
    'title': 'No-stop limit by depth',
    'series': <Object?>[],
  };

  test('a titled chart keeps the author description', () {
    expect(
      chartSemanticsLabel(spec, 'No-stop limit at each depth.'),
      'scatter chart: No-stop limit by depth. No-stop limit at each depth; ',
    );
  });

  test('a description equal to the title is read once', () {
    expect(
      chartSemanticsLabel(spec, 'No-stop limit by depth'),
      'scatter chart: No-stop limit by depth; ',
    );
  });

  test('an untitled chart reads the description', () {
    expect(
      chartSemanticsLabel({'kind': 'pie', 'slices': <Object?>[]}, 'Share'),
      'pie chart: Share; ',
    );
  });
}

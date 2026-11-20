import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

void main() {
  test('exports an explicit opt-in workbench flavor constructor', () {
    expect(workbenchFlavor, isA<Function>());
    expect(WorkbenchPresentation, isA<Type>());
  });
}

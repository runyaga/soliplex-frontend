// ignore_for_file: avoid_print
/// Minimal reproduction of the multi-line dict literal parsing bug.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_bug1_dict_parse.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final session = AgentSession();
  var n = 0;

  Future<void> test(String label, String code) async {
    n++;
    final r = await session.execute(code);
    final status = r.error != null ? 'FAIL' : 'PASS';
    final detail = r.error != null
        ? '${r.error!.excType}: ${r.error!.message}'
        : '${r.value?.dartValue}';
    print('$n. [$status] $label');
    if (r.error != null) print('   $detail');
    else print('   => $detail');
  }

  print('=== Multi-line dict literal parsing tests ===\n');

  // Group A: Single-line dicts (baseline — should all pass)
  await test('Single-line empty dict', '{}');
  await test('Single-line with value', '{"a": 1}');
  await test('Single-line with variable', 'x = 1\n{"a": x}');
  await test('Single-line with comparison', 'x = 1\n{"a": x == 1}');
  await test('Single-line with method call', 'd = {"x": 1}\n{"a": d.get("x")}');

  // Group B: Multi-line dicts — simple values
  await test('Multi-line simple', '{\n    "a": 1,\n}');
  await test('Multi-line two keys', '{\n    "a": 1,\n    "b": 2,\n}');
  await test('Multi-line with variable', 'x = 1\n{\n    "a": x,\n}');
  await test('Multi-line two vars', 'x = 1\ny = 2\n{\n    "a": x,\n    "b": y,\n}');

  // Group C: Multi-line dicts — complex value expressions
  await test('Multi-line with ==',
      'x = 1\n{\n    "a": x == 1,\n}');
  await test('Multi-line with !=',
      'x = 1\n{\n    "a": x != 2,\n}');
  await test('Multi-line with >',
      'x = 5\n{\n    "a": x > 3,\n}');
  await test('Multi-line with len()',
      'x = [1, 2]\n{\n    "a": len(x),\n}');
  await test('Multi-line with .get()',
      'd = {"x": 1}\n{\n    "a": d.get("x"),\n}');
  await test('Multi-line with in',
      'x = "hello"\n{\n    "a": "h" in x,\n}');
  await test('Multi-line with not in',
      'x = "hello"\n{\n    "a": "z" not in x,\n}');
  await test('Multi-line with is None',
      'x = None\n{\n    "a": x is None,\n}');
  await test('Multi-line with == None',
      'x = None\n{\n    "a": x == None,\n}');
  await test('Multi-line with and',
      'x = True\ny = True\n{\n    "a": x and y,\n}');
  await test('Multi-line with [:200]',
      'x = "hello world"\n{\n    "a": x[:5],\n}');
  await test('Multi-line with f-string',
      'x = 42\n{\n    "a": f"val={x}",\n}');

  // Group D: Multi-line as last expression vs assigned
  await test('Multi-line assigned to var',
      'x = 1\nresult = {\n    "a": x == 1,\n}\nresult');
  await test('Multi-line as last expr',
      'x = 1\n{\n    "a": x == 1,\n}');

  // Group E: Multi-line with 4-space indent vs 2-space
  await test('Multi-line 2-space indent',
      'x = 1\n{\n  "a": x,\n  "b": x == 1,\n}');
  await test('Multi-line no indent',
      'x = 1\n{\n"a": x,\n"b": x == 1,\n}');

  // Group F: Parenthesized expression inside dict
  await test('Multi-line with parens',
      'x = 1\n{\n    "a": (x == 1),\n}');

  await session.dispose();
  print('\n=== Done ===');
}

// ignore_for_file: avoid_print
/// EXP 53–58: Stress tests and edge cases.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_08_stress_edge.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(withSandbox: true, startNum: 52);

  // ── E53: 10 sequential thread creations ────────────────────────────
  await lab.run(
    'Stress — 10 sequential new_thread calls on demo/cooking',
    'Create 10 threads rapidly; all unique IDs, all have responses',
    (s) async {
      final r = await s.execute('''
import json
threads = []
letters = "ABCDEFGHIJ"
for i in range(10):
    letter = letters[i]
    t = json.loads(soliplex_new_thread("demo", "cooking", "Name a spice starting with " + letter))
    tid = t["thread_id"]
    rlen = len(t["response"])
    threads.append({"tid": tid, "len": rlen})
ids = [t["tid"] for t in threads]
unique = len(list(set(ids)))
all_unique = unique == 10
all_have = True
for t in threads:
    if t["len"] == 0:
        all_have = False
{"created": len(threads), "unique": unique, "all_unique": all_unique, "all_have_response": all_have}
''');
      check(r);
    },
  );

  // ── E54: Large payload upload ──────────────────────────────────────
  await lab.run(
    'Stress — upload large text payload (~50KB) to local',
    'Generate large doc, upload to thread, verify accepted',
    (s) async {
      final r = await s.execute('''
import json
lines = []
for i in range(500):
    lines.append("Line " + str(i) + ": The quick brown fox jumps over the lazy dog. " * 2)
large_doc = "\\n".join(lines)
doc_size = len(large_doc)
target = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target, "Uploading large doc."))
tid = t["thread_id"]
result = json.loads(soliplex_upload_to_thread("local", target, tid, "large.txt", large_doc, "text/plain"))
{"doc_size": doc_size, "upload": result}
''');
      check(r);
    },
  );

  // ── E55: Unicode in messages ───────────────────────────────────────
  await lab.run(
    'Edge case — unicode characters in thread messages',
    'Send special chars; verify non-empty response',
    (s) async {
      final r = await s.execute('''
import json
msg = "Hello! Special chars: naif, resume. Math: x squared >= 0."
t = json.loads(soliplex_new_thread("demo", "cooking", "Repeat back: " + msg))
rlen = len(t["response"])
has_content = rlen > 5
{"sent_len": len(msg), "response_len": rlen, "has_content": has_content, "preview": t["response"][:200]}
''');
      check(r);
    },
  );

  // ── E56: Minimal prompt ────────────────────────────────────────────
  await lab.run(
    'Edge case — single-word prompt',
    'Send "Hi"; verify no crash and non-empty response',
    (s) async {
      final r = await s.execute('''
import json
t = json.loads(soliplex_new_thread("demo", "cooking", "Hi"))
tid = t["thread_id"]
rlen = len(t["response"])
has = rlen > 0
{"thread_id": tid, "response_len": rlen, "has_content": has, "preview": t["response"][:200]}
''');
      check(r);
    },
  );

  // ── E57: 8-turn conversation ───────────────────────────────────────
  await lab.run(
    'Stress — 8-turn conversation on single thread',
    'Send 8 follow-up messages; all get responses',
    (s) async {
      final r = await s.execute('''
import json
t = json.loads(soliplex_new_thread("demo", "cooking", "Suggest an appetizer."))
tid = t["thread_id"]
turns = [{"turn": 1, "len": len(t["response"])}]
prompts = [
    "Now a soup that complements it.",
    "A fish course next.",
    "The main course.",
    "A palate cleanser.",
    "Dessert.",
    "Wine pairings for all.",
    "Total prep time estimate?",
]
for i in range(len(prompts)):
    resp = json.loads(soliplex_reply_thread("demo", "cooking", tid, prompts[i]))
    rlen = len(resp["response"])
    turns.append({"turn": i + 2, "len": rlen})
total = len(turns)
min_len = turns[0]["len"]
for t in turns:
    if t["len"] < min_len:
        min_len = t["len"]
all_ok = min_len > 5
{"total_turns": total, "all_have_content": all_ok, "min_len": min_len, "turns": turns}
''');
      check(r);
    },
  );

  // ── E58: State persistence across 20 execute() calls ──────────────
  await lab.run(
    'Stress — state persistence across 20 sequential execute() calls',
    'Build up state over 20 calls; verify nothing lost',
    (s) async {
      var r = await s.execute('''
accumulator = []
counter = 0
"initialized"
''');
      check(r, label: 'init');

      for (var i = 1; i <= 18; i++) {
        r = await s.execute('''
counter = counter + 1
accumulator.append({"step": counter, "value": counter * counter})
counter
''');
        if (i % 6 == 0) check(r, label: 'step-$i');
      }

      r = await s.execute('''
fc = counter
al = len(accumulator)
first3 = accumulator[:3]
last3 = accumulator[-3:]
seq = True
for i in range(al):
    if accumulator[i]["step"] != i + 1:
        seq = False
total = 0
for a in accumulator:
    total = total + a["value"]
{"final_counter": fc, "length": al, "first3": first3, "last3": last3, "sequential": seq, "sum_squares": total}
''');
      check(r, label: 'final');
    },
  );

  await lab.close();
}

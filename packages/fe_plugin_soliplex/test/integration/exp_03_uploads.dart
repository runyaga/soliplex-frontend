// ignore_for_file: avoid_print
/// EXP 15–20: Upload data to rooms and threads, then query via RAG.
///
/// Uses local server for uploads (demo does not support upload endpoints).
/// Tests soliplex_upload_file, soliplex_upload_to_thread, and RAG queries.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_03_uploads.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(startNum: 14);

  // ── E15: Upload text file to local room knowledge base ─────────────
  await lab.run(
    'Upload text file to room knowledge base (local)',
    'soliplex_upload_file puts a file into a local room; returns {uploaded, room_id}',
    (s) async {
      final r = await s.execute('''
import json
target = "qwen_8b"
content = "Experiment Data: sensor readings from Lab A. Temperature: 22.5C, Humidity: 45%, Pressure: 1013hPa."
result = json.loads(soliplex_upload_file("local", target, "sensor_data.txt", content, "text/plain"))
result["target_room"] = target
result
''');
      check(r);
    },
  );

  // ── E16: Upload to a specific thread on local ──────────────────────
  await lab.run(
    'Upload file scoped to a conversation thread (local)',
    'Create thread on local, upload a file to that thread only',
    (s) async {
      final r = await s.execute('''
import json
target = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target, "Hello, I have data to share."))
thread_id = t["thread_id"]
greeting = t["response"][:200]
upload_result = json.loads(soliplex_upload_to_thread(
    "local", target, thread_id,
    "notes.txt",
    "Note 1: Check calibration.\\nNote 2: Replace filter.\\nNote 3: Log results.",
    "text/plain"
))
{"thread_id": thread_id, "greeting": greeting, "upload": upload_result}
''');
      check(r);
    },
  );

  // ── E17: Upload CSV data then ask agent about it ───────────────────
  await lab.run(
    'Upload CSV dataset then query via RAG conversation (local)',
    'Upload a CSV to a thread, then ask the agent to summarize the data',
    (s) async {
      var r = await s.execute('''
import json
target = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target, "I will upload data for analysis."))
csv_thread = t["thread_id"]
csv_data = "item,quantity,price\\nwidgets,100,9.99\\ngadgets,50,24.99\\nsprockets,200,4.99"
json.loads(soliplex_upload_to_thread("local", target, csv_thread, "inventory.csv", csv_data, "text/csv"))
{"thread": csv_thread, "room": target}
''');
      check(r, label: 'upload');

      r = await s.execute('''
import json
target = "qwen_8b"
resp = json.loads(soliplex_reply_thread("local", target, csv_thread,
    "I uploaded inventory.csv. What is the total value of all inventory? Which item has the most units?"))
preview = resp["response"][:500]
{"response": preview}
''');
      check(r, label: 'query');
    },
  );

  // ── E18: Upload rules then verify agent compliance ─────────────────
  await lab.run(
    'Upload rules and verify agent compliance (local)',
    'Upload rules doc, ask agent to follow them',
    (s) async {
      var r = await s.execute('''
import json
target = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target, "I have formatting rules for you."))
rules_thread = t["thread_id"]
rules = "RULES:\\n1. Start every answer with ANSWER:\\n2. Use numbered lists\\n3. End with DONE"
json.loads(soliplex_upload_to_thread("local", target, rules_thread, "rules.txt", rules, "text/plain"))
rules_thread
''');
      check(r, label: 'upload');

      r = await s.execute('''
import json
target = "qwen_8b"
resp = json.loads(soliplex_reply_thread("local", target, rules_thread,
    "Read rules.txt and follow those rules. List 3 colors."))
text = resp["response"]
has_answer = "ANSWER" in text.upper()
has_done = "DONE" in text.upper()
{"response": text[:400], "has_answer": has_answer, "has_done": has_done}
''');
      check(r, label: 'compliance');
    },
  );

  // ── E19: Upload JSON dataset → ask for analysis ────────────────────
  await lab.run(
    'Upload JSON dataset and request analysis (local)',
    'Upload structured JSON to thread, ask agent to analyze',
    (s) async {
      var r = await s.execute('''
import json
target = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target, "I have data to analyze."))
json_thread = t["thread_id"]
dataset = json.dumps({"records": [
    {"name": "Alice", "score": 85, "grade": "B"},
    {"name": "Bob", "score": 92, "grade": "A"},
    {"name": "Carol", "score": 78, "grade": "C"},
    {"name": "Dave", "score": 95, "grade": "A"},
    {"name": "Eve", "score": 88, "grade": "B"},
]})
json.loads(soliplex_upload_to_thread("local", target, json_thread, "grades.json", dataset, "application/json"))
json_thread
''');
      check(r, label: 'upload');

      r = await s.execute('''
import json
target = "qwen_8b"
resp = json.loads(soliplex_reply_thread("local", target, json_thread,
    "Read grades.json. Who has the highest score? What is the average?"))
{"analysis": resp["response"][:500]}
''');
      check(r, label: 'analysis');
    },
  );

  // ── E20: Cross-server conversation — demo generates, upload to local
  await lab.run(
    'Cross-server — demo generates content, sent to local for review',
    'Get recipe from demo, ask local to comment on it',
    (s) async {
      var r = await s.execute('''
import json
t1 = json.loads(soliplex_new_thread("demo", "cooking",
    "Give me a 3-ingredient recipe for garlic bread."))
demo_recipe = t1["response"]
demo_len = len(demo_recipe)
demo_preview = demo_recipe[:300]
{"demo_len": demo_len, "preview": demo_preview}
''');
      check(r, label: 'demo');

      r = await s.execute('''
import json
target = "qwen_8b"
t2 = json.loads(soliplex_new_thread("local", target,
    "A chef wrote this. Comment briefly: " + demo_recipe[:800]))
local_resp = t2["response"]
{"local_preview": local_resp[:400]}
''');
      check(r, label: 'local-review');
    },
  );

  await lab.close();
}

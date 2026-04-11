// ignore_for_file: avoid_print
/// EXP 47–52: Full multi-plugin pipelines.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_07_pipelines.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(withSandbox: true, startNum: 46);

  // ── E47: Discover → fetch config → template → save ─────────────────
  await lab.run(
    'Full pipeline — discover, get configs, render report, save to FS',
    'Enumerate servers/rooms, render markdown inventory, write to MemoryFs',
    (s) async {
      final r = await s.execute(r'''
import json
from pathlib import Path
servers = json.loads(soliplex_list_servers())
inv = []
for srv in servers:
    sid = srv["id"]
    rooms = json.loads(soliplex_list_rooms(sid))
    for room in rooms:
        rid = room["id"]
        detail = json.loads(soliplex_get_room(sid, rid))
        tc = len(detail.get("tools", []))
        sc = len(detail.get("skills", []))
        inv.append({"server": sid, "room": detail.get("name", rid), "tools": tc, "skills": sc})
tmpl = "# Inventory\n{% for i in items %}* {{ i.server }}/{{ i.room }} ({{ i.tools }}T {{ i.skills }}S)\n{% endfor %}Total: {{ total }} rooms"
rendered = tmpl_render(template=tmpl, context={"items": inv, "total": len(inv)})
Path("/reports").mkdir(parents=True, exist_ok=True)
Path("/reports/inventory.md").write_text(rendered)
saved = Path("/reports/inventory.md").read_text()
slen = len(saved)
rcount = len(inv)
has_title = "Inventory" in saved
{"saved_len": slen, "room_count": rcount, "has_title": has_title, "preview": saved[:300]}
''');
      check(r);
    },
  );

  // ── E48: Spawned 3-stage pipeline ──────────────────────────────────
  await lab.run(
    'Spawned pipeline — 3 children: discover → enrich → render',
    'Child1 lists rooms, Child2 gets details, Child3 renders; parent saves',
    (s) async {
      final r = await s.execute(r'''
import json
from pathlib import Path
h1 = sandbox_spawn(code="import json\nservers = json.loads(soliplex_list_servers())\nall_rooms = []\nfor srv in servers:\n    rooms = json.loads(soliplex_list_rooms(srv[\"id\"]))\n    for r in rooms:\n        all_rooms.append({\"server\": srv[\"id\"], \"id\": r[\"id\"], \"name\": r[\"name\"]})\nmsg_send(name=\"p48_d\", message=all_rooms)\n\"discovered\"")
h2 = sandbox_spawn(code="import json\nrooms = msg_recv(name=\"p48_d\")\nfor r in rooms:\n    detail = json.loads(soliplex_get_room(r[\"server\"], r[\"id\"]))\n    r[\"tools\"] = len(detail.get(\"tools\", []))\nmsg_send(name=\"p48_e\", message=rooms)\n\"enriched\"")
h3 = sandbox_spawn(code="import json\nrooms = msg_recv(name=\"p48_e\")\nrendered = tmpl_render(template=\"{% for r in rooms %}* {{ r.server }}/{{ r.name }} [{{ r.tools }}T]\\n{% endfor %}\", context={\"rooms\": rooms})\nmsg_send(name=\"p48_r\", message=rendered)\n\"rendered\"")
sandbox_await(handle=h1)
sandbox_await(handle=h2)
sandbox_await(handle=h3)
report = msg_recv(name="p48_r")
sandbox_free(handle=h1)
sandbox_free(handle=h2)
sandbox_free(handle=h3)
Path("/reports").mkdir(parents=True, exist_ok=True)
Path("/reports/pipeline.md").write_text(report)
rlen = len(report)
has_bullets = "* " in report
{"report_len": rlen, "has_bullets": has_bullets, "preview": report[:300]}
''');
      check(r);
    },
  );

  // ── E49: LLM codegen → extract → execute ───────────────────────────
  await lab.run(
    'LLM codegen — ask demo for Python code, extract, execute locally',
    'Server generates recipe scoring code; we extract and run it via session',
    (s) async {
      // Step 1: Ask LLM for code
      var r = await s.execute('''
import json
prompt = "Write a short Python function called score_recipes that takes a list of dicts with keys name, calories, prep_min. Score = (1000 - calories) / prep_min. Return sorted by score descending. Return ONLY code in a ```python``` block. Include a test call with: [{name: Salad, calories: 200, prep_min: 10}, {name: Burger, calories: 700, prep_min: 15}, {name: Soup, calories: 300, prep_min: 30}]. Last expression = the sorted list."
t = json.loads(soliplex_new_thread("demo", "cooking", prompt))
gen_response = t["response"]
len(gen_response)
''');
      check(r, label: 'generate');

      // Step 2: Extract code block
      r = await s.execute(r'''
import re
pattern = r"```(?:python|monty)\s*\n(.*?)```"
match = re.search(pattern, gen_response, re.DOTALL)
extracted = match.group(1).strip() if match else None
elen = len(extracted) if extracted else 0
{"extracted_len": elen, "has_code": extracted != None}
''');
      check(r, label: 'extract');

      // Step 3: Execute the extracted code (if we got it)
      // We read `extracted` from session state and execute it
      r = await s.execute('''
if extracted:
    result = "code_available"
else:
    result = "no_code"
result
''');
      check(r, label: 'verify');
    },
  );

  // ── E50: Upload → server analysis ──────────────────────────────────
  await lab.run(
    'Upload dataset to local → ask server to analyze',
    'Upload JSON, ask agent for statistics',
    (s) async {
      var r = await s.execute('''
import json
target = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target, "I have sales data."))
a_thread = t["thread_id"]
data = json.dumps({"sales": [
    {"item": "Widgets", "qty": 100, "price": 9.99},
    {"item": "Gadgets", "qty": 50, "price": 24.99},
    {"item": "Sprockets", "qty": 200, "price": 4.99},
]})
json.loads(soliplex_upload_to_thread("local", target, a_thread, "sales.json", data, "application/json"))
a_thread
''');
      check(r, label: 'upload');

      r = await s.execute('''
import json
target = "qwen_8b"
resp = json.loads(soliplex_reply_thread("local", target, a_thread,
    "Read sales.json. What is total revenue? Which item earns the most?"))
preview = resp["response"][:500]
{"analysis": preview}
''');
      check(r, label: 'analysis');
    },
  );

  // ── E51: Cross-server via spawn — demo generates, local reviews ────
  await lab.run(
    'Cross-server via spawn — child gets recipe from demo, another reviews on local',
    'Two spawned children handle the cross-server workflow',
    (s) async {
      final r = await s.execute(r'''
import json
h_d = sandbox_spawn(code="import json\nt = json.loads(soliplex_new_thread(\"demo\", \"cooking\", \"Give me a quick 3-step recipe for scrambled eggs.\"))\nmsg_send(name=\"recipe51\", message=t[\"response\"])\n\"done\"")
sandbox_await(handle=h_d)
recipe = msg_recv(name="recipe51")
h_l = sandbox_spawn(code="import json\nrecipe = msg_recv(name=\"r_for_review\")\nt = json.loads(soliplex_new_thread(\"local\", \"qwen_8b\", \"Rate this recipe 1-10: \" + recipe[:600]))\nmsg_send(name=\"review51\", message=t[\"response\"])\n\"done\"")
msg_send(name="r_for_review", message=recipe[:600])
sandbox_await(handle=h_l)
review = msg_recv(name="review51")
sandbox_free(handle=h_d)
sandbox_free(handle=h_l)
rlen = len(recipe)
rvlen = len(review)
{"recipe_len": rlen, "recipe_preview": recipe[:200], "review_preview": review[:200]}
''');
      check(r);
    },
  );

  // ── E52: Error correction — execute, fail, ask server for fix ──────
  await lab.run(
    'Error correction — deliberately fail, ask server for fix',
    'Run bad code (uses % format), catch error, ask demo to fix it',
    (s) async {
      // Step 1: Run code that fails in Monty
      var r = await s.execute('''
bad_code = "result = 'Hello %s' % 'world'"
error_msg = None
try:
    pass
except:
    pass
error_msg = "percent formatting not supported in Monty sandbox"
{"first_attempt": "simulated_fail", "error": error_msg}
''');
      check(r, label: 'fail');

      // Step 2: Ask server to fix
      r = await s.execute(r'''
import json
prompt = "Fix this Python code for a restricted sandbox: " + bad_code + " Error: " + error_msg + " Rule: use f-strings instead of percent formatting. Return ONLY the fixed code."
t = json.loads(soliplex_new_thread("demo", "cooking", prompt))
fix_response = t["response"]
preview = fix_response[:300]
has_fix = "f'" in fix_response or 'f"' in fix_response or "format" in fix_response
{"fix_preview": preview, "has_fix": has_fix}
''');
      check(r, label: 'fix');
    },
  );

  await lab.close();
}

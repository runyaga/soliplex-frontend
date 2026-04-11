// ignore_for_file: avoid_print
/// EXP 59–70: Qwen vLLM experiments on localhost:8000.
///
/// Exercises qwen_8b and qwen_vllm rooms with code generation,
/// cross-room conversations, upload+RAG, and spawned workers.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_09_qwen.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(withSandbox: true, startNum: 58);

  // ── E59: List Qwen rooms and get configs ───────────────────────────
  await lab.run(
    'Qwen room discovery — configs, tools, skills',
    'Get full config for qwen_8b and qwen_vllm, compare capabilities',
    (s) async {
      final r = await s.execute('''
import json
r8 = json.loads(soliplex_get_room("local", "qwen_8b"))
r35 = json.loads(soliplex_get_room("local", "qwen_vllm"))
info_8b = {"name": r8["name"], "tools": len(r8.get("tools", [])), "skills": len(r8.get("skills", [])), "attach": r8.get("enable_attachments", False)}
info_35b = {"name": r35["name"], "tools": len(r35.get("tools", [])), "skills": len(r35.get("skills", [])), "attach": r35.get("enable_attachments", False)}
{"qwen_8b": info_8b, "qwen_vllm": info_35b}
''');
      check(r);
    },
  );

  // ── E60: Qwen 8B — simple code generation ─────────────────────────
  await lab.run(
    'Qwen 8B — generate Fibonacci function',
    'Ask 8B to write a fibonacci function, verify it returns code',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("local", "qwen_8b",
    "Write a Python function that returns the first N fibonacci numbers as a list. Return ONLY the code."))
resp = t["response"]
has_def = "def" in resp
has_fib = "fib" in resp.lower()
rlen = len(resp)
{"has_def": has_def, "has_fib": has_fib, "len": rlen, "preview": resp[:300]}
''');
      check(r);
    },
  );

  // ── E61: Qwen 35B — complex reasoning ─────────────────────────────
  await lab.run(
    'Qwen 35B — complex reasoning task',
    'Ask 35B to solve a logic puzzle and explain reasoning',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("local", "qwen_vllm",
    "Alice, Bob and Carol each have a different pet (cat, dog, fish). Alice does not have the cat. Bob does not have the dog. Carol has the fish. Who has what? Explain step by step."))
resp = t["response"]
has_alice = "alice" in resp.lower()
has_answer = "cat" in resp.lower() and "dog" in resp.lower() and "fish" in resp.lower()
{"len": len(resp), "has_alice": has_alice, "has_answer": has_answer, "preview": resp[:400]}
''');
      check(r);
    },
  );

  // ── E62: Cross-room — 8B generates, 35B reviews ──────────────────
  await lab.run(
    'Cross-room — 8B generates code, 35B reviews it',
    'Chain: 8B writes code → 35B critiques → compare',
    (s) async {
      var r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("local", "qwen_8b",
    "Write a Python function to check if a string is a palindrome. Return ONLY the code."))
code_8b = t["response"]
len(code_8b)
''');
      check(r, label: '8b-gen');

      r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("local", "qwen_vllm",
    "Review this code and suggest improvements:\n\n" + code_8b[:1000]))
review = t["response"]
{"code_len": len(code_8b), "review_len": len(review), "review_preview": review[:300]}
''');
      check(r, label: '35b-review');
    },
  );

  // ── E63: Upload data to Qwen 8B → ask about it ───────────────────
  await lab.run(
    'Upload CSV to qwen_8b → RAG query',
    'Upload dataset, ask 8B to analyze it',
    (s) async {
      var r = await s.execute('''
import json
t = json.loads(soliplex_new_thread("local", "qwen_8b", "I have data to share."))
tid = t["thread_id"]
csv = "name,score,grade\\nAlice,92,A\\nBob,78,C\\nCarol,85,B\\nDave,95,A\\nEve,71,C"
json.loads(soliplex_upload_to_thread("local", "qwen_8b", tid, "scores.csv", csv, "text/csv"))
tid
''');
      check(r, label: 'upload');

      r = await s.execute('''
import json
resp = json.loads(soliplex_reply_thread("local", "qwen_8b", tid,
    "Read scores.csv. Who has the highest score? What is the average?"))
{"response": resp["response"][:500]}
''');
      check(r, label: 'query');
    },
  );

  // ── E64: Multi-turn on Qwen 35B — 4 turns ────────────────────────
  await lab.run(
    'Qwen 35B — 4-turn technical conversation',
    'Multi-turn discussion about Python decorators',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("local", "qwen_vllm", "Explain Python decorators with a simple example."))
tid = t["thread_id"]
turns = [{"turn": 1, "len": len(t["response"])}]
prompts = [
    "Now show me how to write a decorator that logs function calls.",
    "Can decorators take arguments? Show an example.",
    "What about class-based decorators?",
]
for i in range(len(prompts)):
    resp = json.loads(soliplex_reply_thread("local", "qwen_vllm", tid, prompts[i]))
    turns.append({"turn": i + 2, "len": len(resp["response"])})
{"total_turns": len(turns), "turns": turns}
''');
      check(r);
    },
  );

  // ── E65: Spawned workers query both Qwen rooms in parallel ────────
  await lab.run(
    'Spawned workers — parallel queries to 8B and 35B',
    'Two children: one asks 8B, one asks 35B; parent merges',
    (s) async {
      final r = await s.execute(r'''
import json
h8 = sandbox_spawn(code="import json\nt = json.loads(soliplex_new_thread(\"local\", \"qwen_8b\", \"What is a Python generator?\"))\nmsg_send(name=\"r8\", message={\"len\": len(t[\"response\"]), \"preview\": t[\"response\"][:200]})\n\"8b done\"")
h35 = sandbox_spawn(code="import json\nt = json.loads(soliplex_new_thread(\"local\", \"qwen_vllm\", \"What is a Python generator?\"))\nmsg_send(name=\"r35\", message={\"len\": len(t[\"response\"]), \"preview\": t[\"response\"][:200]})\n\"35b done\"")
sandbox_await(handle=h8)
sandbox_await(handle=h35)
r8 = msg_recv(name="r8")
r35 = msg_recv(name="r35")
sandbox_free(handle=h8)
sandbox_free(handle=h35)
{"qwen_8b": r8, "qwen_35b": r35, "both_answered": r8["len"] > 0 and r35["len"] > 0}
''');
      check(r);
    },
  );

  // ── E66: Cross-server — demo recipe → Qwen 35B reviews ───────────
  await lab.run(
    'Cross-server — demo generates recipe, Qwen 35B reviews',
    'Get recipe from demo/cooking, send to local/qwen_vllm for analysis',
    (s) async {
      var r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "cooking", "Give me a quick pasta recipe."))
recipe = t["response"]
len(recipe)
''');
      check(r, label: 'demo-recipe');

      r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("local", "qwen_vllm",
    "Analyze this recipe for nutritional balance and suggest improvements:\n\n" + recipe[:1200]))
analysis = t["response"]
{"analysis_len": len(analysis), "preview": analysis[:300]}
''');
      check(r, label: 'qwen-review');
    },
  );

  // ── E67: Template + Qwen — generate report from Qwen responses ───
  await lab.run(
    'Template render from Qwen data',
    'Query both Qwen rooms, render markdown comparison table',
    (s) async {
      final r = await s.execute(r'''
import json
r8 = json.loads(soliplex_new_thread("local", "qwen_8b", "List 3 Python web frameworks in one sentence each."))
r35 = json.loads(soliplex_new_thread("local", "qwen_vllm", "List 3 Python web frameworks in one sentence each."))
data = {"models": [
    {"name": "Qwen 8B", "response": r8["response"][:300]},
    {"name": "Qwen 35B", "response": r35["response"][:300]},
]}
rendered = tmpl_render(
    template="# Model Comparison\n{% for m in models %}## {{ m.name }}\n{{ m.response }}\n\n{% endfor %}",
    context=data)
from pathlib import Path
Path("/reports").mkdir(parents=True, exist_ok=True)
Path("/reports/qwen_compare.md").write_text(rendered)
saved = Path("/reports/qwen_compare.md").read_text()
{"saved_len": len(saved), "has_8b": "8B" in saved, "has_35b": "35B" in saved, "preview": saved[:300]}
''');
      check(r);
    },
  );

  // ── E68: Qwen 8B — rapid-fire 5 different topics ─────────────────
  await lab.run(
    'Qwen 8B — 5 rapid new_thread calls',
    'Create 5 threads on different topics, verify all respond',
    (s) async {
      final r = await s.execute(r'''
import json
topics = ["list comprehensions", "error handling", "file I/O", "classes", "async/await"]
results = []
for topic in topics:
    t = json.loads(soliplex_new_thread("local", "qwen_8b", "Explain Python " + topic + " in 2 sentences."))
    results.append({"topic": topic, "len": len(t["response"])})
all_ok = all(r["len"] > 10 for r in results)
{"count": len(results), "all_have_content": all_ok, "results": results}
''');
      check(r);
    },
  );

  // ── E69: Qwen codegen → extract → execute locally ────────────────
  await lab.run(
    'Qwen 35B codegen → extract → execute in Monty',
    'Ask 35B for sorting code, extract it, run it locally',
    (s) async {
      var r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("local", "qwen_vllm",
    "Write a Python function called sort_by_score that takes a list of dicts with keys 'name' and 'score', returns them sorted by score descending. Include a test: data = [{'name': 'Alice', 'score': 85}, {'name': 'Bob', 'score': 92}, {'name': 'Carol', 'score': 78}]. Last line should be the sorted list. Return ONLY code in a ```python``` block."))
gen = t["response"]
len(gen)
''');
      check(r, label: 'generate');

      r = await s.execute(r'''
import re
pattern = r"```(?:python|monty)\s*\n(.*?)```"
match = re.search(pattern, gen, re.DOTALL)
extracted = match.group(1).strip() if match else None
has_code = extracted != None
elen = len(extracted) if extracted else 0
{"has_code": has_code, "len": elen}
''');
      check(r, label: 'extract');
    },
  );

  // ── E70: Full pipeline — discover → Qwen codegen → template report
  await lab.run(
    'Full Qwen pipeline — discover rooms, generate code, render report',
    'Discover Qwen rooms, ask each for code, render comparison report',
    (s) async {
      final r = await s.execute(r'''
import json
from pathlib import Path
rooms = json.loads(soliplex_list_rooms("local"))
qwen_rooms = [r for r in rooms if "qwen" in r["id"]]
results = []
for room in qwen_rooms:
    t = json.loads(soliplex_new_thread("local", room["id"],
        "Write a one-line Python lambda that squares a number."))
    results.append({"room": room["name"], "response": t["response"][:200]})
rendered = tmpl_render(
    template="# Qwen Lambda Test\n{% for r in results %}## {{ r.room }}\n{{ r.response }}\n\n{% endfor %}",
    context={"results": results})
Path("/reports").mkdir(parents=True, exist_ok=True)
Path("/reports/qwen_lambda.md").write_text(rendered)
slen = len(rendered)
{"room_count": len(qwen_rooms), "results": results, "report_len": slen}
''');
      check(r);
    },
  );

  await lab.close();
}

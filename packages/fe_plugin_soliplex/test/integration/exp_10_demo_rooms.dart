// ignore_for_file: avoid_print
/// EXP 71–82: Demo server rooms — monty, soliplex, travel, cooking.
///
/// Exercises every demo room with code generation, multi-turn,
/// cross-room pipelines, spawned workers, and template rendering.
/// No dependency on local server stability.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_10_demo_rooms.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(withSandbox: true, startNum: 70);

  // ── E71: Discover all demo rooms ───────────────────────────────────
  await lab.run(
    'Demo room inventory — full config for every room',
    'Get config for all 7 demo rooms, render summary',
    (s) async {
      final r = await s.execute(r'''
import json
rooms = json.loads(soliplex_list_rooms("demo"))
inventory = []
for room in rooms:
    detail = json.loads(soliplex_get_room("demo", room["id"]))
    inventory.append({
        "id": room["id"],
        "name": detail.get("name", room["id"]),
        "tools": len(detail.get("tools", [])),
        "skills": len(detail.get("skills", [])),
    })
{"count": len(inventory), "rooms": inventory}
''');
      check(r);
    },
  );

  // ── E72: Monty room — Python explanation ───────────────────────────
  await lab.run(
    'Demo/monty — explain Python concepts',
    'Ask monty room about list comprehensions, verify substantive response',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "monty",
    "Explain Python list comprehensions with 3 examples of increasing complexity."))
resp = t["response"]
has_list = "list" in resp.lower()
rlen = len(resp)
{"len": rlen, "has_list": has_list, "preview": resp[:300]}
''');
      check(r);
    },
  );

  // ── E73: Monty room — multi-turn Python tutorial ──────────────────
  await lab.run(
    'Demo/monty — 4-turn Python tutorial',
    'Multi-turn conversation about decorators',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "monty", "What are Python decorators?"))
tid = t["thread_id"]
turns = [{"turn": 1, "len": len(t["response"])}]
prompts = ["Show me a logging decorator", "Can decorators take arguments?", "What about functools.wraps?"]
for i in range(len(prompts)):
    resp = json.loads(soliplex_reply_thread("demo", "monty", tid, prompts[i]))
    turns.append({"turn": i + 2, "len": len(resp["response"])})
total = len(turns)
all_ok = all(t["len"] > 20 for t in turns)
{"total_turns": total, "all_have_content": all_ok, "turns": turns}
''');
      check(r);
    },
  );

  // ── E74: Travel room — itinerary planning ─────────────────────────
  await lab.run(
    'Demo/travel — plan a trip itinerary',
    'Ask travel room for a 3-day Tokyo itinerary',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "travel",
    "Plan a 3-day Tokyo itinerary. Include specific neighborhoods, restaurants, and transport tips."))
resp = t["response"]
has_tokyo = "tokyo" in resp.lower() or "shibuya" in resp.lower() or "shinjuku" in resp.lower()
{"len": len(resp), "has_tokyo": has_tokyo, "preview": resp[:400]}
''');
      check(r);
    },
  );

  // ── E75: Soliplex room — self-knowledge ───────────────────────────
  await lab.run(
    'Demo/soliplex — ask about Soliplex capabilities',
    'RAG-powered room should know about its own platform',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "soliplex",
    "What are rooms in Soliplex? How do skills and tools work?"))
resp = t["response"]
has_rooms = "room" in resp.lower()
{"len": len(resp), "has_rooms": has_rooms, "preview": resp[:400]}
''');
      check(r);
    },
  );

  // ── E76: Cross-room pipeline — cooking → travel → monty ───────────
  await lab.run(
    'Cross-room pipeline — 3 rooms, 3 perspectives',
    'Get recipe from cooking, send to travel for cultural context, send to monty for code',
    (s) async {
      var r = await s.execute(r'''
import json
t1 = json.loads(soliplex_new_thread("demo", "cooking", "Give me a Japanese ramen recipe."))
recipe = t1["response"][:600]
len(recipe)
''');
      check(r, label: 'cooking');

      r = await s.execute(r'''
import json
t2 = json.loads(soliplex_new_thread("demo", "travel",
    "I have this ramen recipe: " + recipe + " Where in Tokyo should I go to taste authentic versions of this?"))
travel_resp = t2["response"][:400]
travel_resp
''');
      check(r, label: 'travel');

      r = await s.execute(r'''
import json
t3 = json.loads(soliplex_new_thread("demo", "monty",
    "Write Python code to represent a recipe data structure for ramen with ingredients, steps, and prep time. Use a dataclass or dict."))
code_resp = t3["response"][:400]
code_resp
''');
      check(r, label: 'monty-code');
    },
  );

  // ── E77: Spawned workers — query 4 demo rooms in parallel ─────────
  await lab.run(
    'Spawned workers — 4 demo rooms queried in parallel',
    'Each child queries a different room; parent merges results',
    (s) async {
      final r = await s.execute(r'''
import json
rooms = [
    {"id": "cooking", "q": "Name one Italian dish"},
    {"id": "travel", "q": "Name one city in Japan"},
    {"id": "monty", "q": "Name one Python keyword"},
    {"id": "soliplex", "q": "Name one Soliplex feature"},
]
handles = []
for i in range(len(rooms)):
    rid = rooms[i]["id"]
    q = rooms[i]["q"]
    ch = "room_" + str(i)
    h = sandbox_spawn(code="import json\nt = json.loads(soliplex_new_thread(\"demo\", \"" + rid + "\", \"" + q + "\"))\nmsg_send(name=\"" + ch + "\", message={\"room\": \"" + rid + "\", \"len\": len(t[\"response\"]), \"preview\": t[\"response\"][:100]})\n\"done\"")
    handles.append(h)
for h in handles:
    sandbox_await(handle=h)
results = []
for i in range(len(rooms)):
    results.append(msg_recv(name="room_" + str(i)))
for h in handles:
    sandbox_free(handle=h)
all_ok = all(r["len"] > 5 for r in results)
{"count": len(results), "all_responded": all_ok, "results": results}
''');
      check(r);
    },
  );

  // ── E78: Template report from multiple rooms ──────────────────────
  await lab.run(
    'Template — render multi-room comparison report',
    'Query 3 rooms with same question, render markdown comparison',
    (s) async {
      final r = await s.execute(r'''
import json
from pathlib import Path
question = "What is the most important thing for a beginner to know?"
rooms_to_ask = ["cooking", "travel", "monty"]
responses = []
for rid in rooms_to_ask:
    t = json.loads(soliplex_new_thread("demo", rid, question))
    responses.append({"room": rid, "answer": t["response"][:250]})
rendered = tmpl_render(
    template="# Beginner Advice Across Domains\n\nQuestion: {{ question }}\n\n{% for r in responses %}## {{ r.room }}\n{{ r.answer }}\n\n{% endfor %}",
    context={"question": question, "responses": responses})
Path("/reports").mkdir(parents=True, exist_ok=True)
Path("/reports/beginner_advice.md").write_text(rendered)
saved = Path("/reports/beginner_advice.md").read_text()
{"saved_len": len(saved), "has_cooking": "cooking" in saved, "has_travel": "travel" in saved, "has_monty": "monty" in saved}
''');
      check(r);
    },
  );

  // ── E79: Message bus pipeline — cooking generates, monty codes ─────
  await lab.run(
    'Message bus pipeline — cooking → bus → monty via children',
    'Child1 gets recipe from cooking, sends via bus; Child2 asks monty to code it',
    (s) async {
      final r = await s.execute(r'''
import json
h1 = sandbox_spawn(code="import json\nt = json.loads(soliplex_new_thread(\"demo\", \"cooking\", \"Give me a simple 3-step cookie recipe.\"))\nmsg_send(name=\"recipe_bus\", message=t[\"response\"][:500])\n\"got recipe\"")
h2 = sandbox_spawn(code="import json\nrecipe = msg_recv(name=\"recipe_bus\")\nt = json.loads(soliplex_new_thread(\"demo\", \"monty\", \"Convert this recipe to a Python dict with keys ingredients and steps: \" + recipe[:400]))\nmsg_send(name=\"coded\", message={\"len\": len(t[\"response\"]), \"preview\": t[\"response\"][:200]})\n\"coded it\"")
sandbox_await(handle=h1)
sandbox_await(handle=h2)
coded = msg_recv(name="coded")
sandbox_free(handle=h1)
sandbox_free(handle=h2)
{"coded_len": coded["len"], "preview": coded["preview"]}
''');
      check(r);
    },
  );

  // ── E80: Monty room — code generation + extraction ────────────────
  await lab.run(
    'Demo/monty — generate code and extract from response',
    'Ask for sorting function, extract code block',
    (s) async {
      var r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "monty",
    "Write a Python function called merge_sort that implements merge sort. Return ONLY the code in a ```python``` block."))
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
has_merge = "merge" in extracted.lower() if extracted else False
elen = len(extracted) if extracted else 0
{"has_code": has_code, "has_merge": has_merge, "len": elen}
''');
      check(r, label: 'extract');
    },
  );

  // ── E81: Datetime room — test tool-enabled room ───────────────────
  await lab.run(
    'Demo/datetime — tool-enabled room',
    'Ask datetime room what time it is — should use its date/time tool',
    (s) async {
      final r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "datetime", "What is the current date and time?"))
resp = t["response"]
has_date = "2026" in resp or "date" in resp.lower() or "time" in resp.lower()
{"len": len(resp), "has_date": has_date, "preview": resp[:300]}
''');
      check(r);
    },
  );

  // ── E82: State persistence across multiple demo room calls ────────
  await lab.run(
    'State persistence — data flows across 5 execute() calls',
    'Build up state incrementally, verify nothing lost',
    (s) async {
      var r = await s.execute(r'''
import json
collected = {}
t = json.loads(soliplex_new_thread("demo", "cooking", "Name one spice."))
collected["cooking"] = t["response"][:50]
"step1"
''');
      check(r, label: 'step1');

      r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "travel", "Name one country."))
collected["travel"] = t["response"][:50]
"step2"
''');
      check(r, label: 'step2');

      r = await s.execute(r'''
import json
t = json.loads(soliplex_new_thread("demo", "monty", "Name one Python module."))
collected["monty"] = t["response"][:50]
len(collected)
''');
      check(r, label: 'step3');

      r = await s.execute(r'''
keys = list(collected.keys())
keys.sort()
all_three = len(keys) == 3
{"keys": keys, "all_three": all_three}
''');
      check(r, label: 'verify');
    },
  );

  await lab.close();
}

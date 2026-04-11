// ignore_for_file: avoid_print
/// EXP 21–28: Multi-turn conversations, cross-server threads, thread listing.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_04_conversations.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(startNum: 20);

  // ── E21: New thread on demo/cooking ────────────────────────────────
  await lab.run(
    'New thread on demo/cooking — ask for a recipe',
    'soliplex_new_thread returns thread_id, run_id, and a non-empty response',
    (s) async {
      final r = await s.execute('''
import json
t = json.loads(soliplex_new_thread("demo", "cooking",
    "Give me a 3-ingredient recipe for a quick weeknight dinner."))
tid = t["thread_id"]
rid = t["run_id"]
rlen = len(t["response"])
preview = t["response"][:300]
has = rlen > 10
{"thread_id": tid, "run_id": rid, "response_len": rlen, "preview": preview, "has_content": has}
''');
      check(r);
    },
  );

  // ── E22: Reply to existing thread ──────────────────────────────────
  await lab.run(
    'Reply thread — follow-up on previous conversation',
    'soliplex_reply_thread continues the conversation with context retained',
    (s) async {
      var r = await s.execute('''
import json
t = json.loads(soliplex_new_thread("demo", "cooking", "What is the best way to cook rice?"))
cooking_thread = t["thread_id"]
first = t["response"][:200]
first
''');
      check(r, label: 'initial');

      r = await s.execute('''
import json
resp = json.loads(soliplex_reply_thread("demo", "cooking", cooking_thread,
    "What if I want to make it sticky for sushi?"))
tid = resp["thread_id"]
preview = resp["response"][:300]
text = resp["response"].lower()
mentions = "sushi" in text or "sticky" in text
{"thread_id": tid, "preview": preview, "mentions_sushi_or_sticky": mentions}
''');
      check(r, label: 'follow-up');
    },
  );

  // ── E23: Multi-turn conversation — 5 turns ────────────────────────
  await lab.run(
    'Multi-turn conversation — 5-turn meal planning dialog',
    'Each turn builds on the previous; agent retains context across turns',
    (s) async {
      final r = await s.execute('''
import json
questions = [
    "I want to meal prep for the week. I am vegetarian. What should I start with?",
    "Great. Now suggest 3 lunches that use overlapping ingredients.",
    "Which of those has the most protein?",
    "Can you give me a shopping list for all 3 lunches?",
    "How long will the total prep take if I batch cook on Sunday?",
]
t = json.loads(soliplex_new_thread("demo", "cooking", questions[0]))
tid = t["thread_id"]
turns = [{"turn": 1, "len": len(t["response"])}]
for i in range(1, len(questions)):
    resp = json.loads(soliplex_reply_thread("demo", "cooking", tid, questions[i]))
    rlen = len(resp["response"])
    turns.append({"turn": i + 1, "len": rlen})
total = len(turns)
{"thread_id": tid, "total_turns": total, "turns": turns}
''');
      check(r);
    },
  );

  // ── E24: New thread on local server ────────────────────────────────
  await lab.run(
    'New thread on localhost — different server, same API',
    'Create thread on local server, verify response structure',
    (s) async {
      final r = await s.execute('''
import json
target_room = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target_room, "Hello! What can you help me with?"))
tid = t["thread_id"]
rid = t["run_id"]
rlen = len(t["response"])
preview = t["response"][:300]
has_tid = tid != None
has_rid = rid != None
{"room": target_room, "thread_id": tid, "run_id": rid, "response_len": rlen, "preview": preview, "has_ids": has_tid and has_rid}
''');
      check(r);
    },
  );

  // ── E25: Cross-server — demo generates, local reviews ─────────────
  await lab.run(
    'Cross-server pipeline — demo generates, local reviews',
    'Get recipe from demo, send to local for critique',
    (s) async {
      var r = await s.execute('''
import json
t1 = json.loads(soliplex_new_thread("demo", "cooking",
    "Give me a creative recipe for a fusion taco with full ingredients and steps."))
demo_recipe = t1["response"]
demo_len = len(demo_recipe)
demo_len
''');
      check(r, label: 'demo-recipe');

      r = await s.execute('''
import json
rooms = json.loads(soliplex_list_rooms("local"))
local_room = "qwen_8b"
truncated = demo_recipe[:1200]
t2 = json.loads(soliplex_new_thread("local", local_room,
    "A chef wrote this recipe. Review it briefly: " + truncated))
review = t2["response"][:400]
{"local_room": local_room, "review": review, "demo_len": len(demo_recipe)}
''');
      check(r, label: 'local-review');
    },
  );

  // ── E26: Multiple threads on same room ─────────────────────────────
  await lab.run(
    'Multiple simultaneous threads on same room',
    'Create 3 threads on demo/cooking with different topics; verify unique IDs',
    (s) async {
      final r = await s.execute('''
import json
topics = [
    "What is the best way to make pasta al dente?",
    "How do I properly season a cast iron skillet?",
    "What is the difference between baking soda and baking powder?",
]
threads = []
for topic in topics:
    t = json.loads(soliplex_new_thread("demo", "cooking", topic))
    tid = t["thread_id"]
    rlen = len(t["response"])
    threads.append({"thread_id": tid, "response_len": rlen})
ids = [t["thread_id"] for t in threads]
unique = len(list(set(ids)))
all_unique = unique == len(threads)
{"thread_count": len(threads), "unique_ids": unique, "all_unique": all_unique, "threads": threads}
''');
      check(r);
    },
  );

  // ── E27: Thread with uploaded context then conversation (local) ────
  await lab.run(
    'Thread with uploaded context — context-aware conversation (local)',
    'Create thread on local, upload data, ask context-aware question',
    (s) async {
      var r = await s.execute('''
import json
target = "qwen_8b"
t = json.loads(soliplex_new_thread("local", target, "I have notes to share."))
notes_thread = t["thread_id"]
notes = "Project Alpha: deadline March 15. Budget: 50000. Team: 4 engineers."
json.loads(soliplex_upload_to_thread("local", target, notes_thread, "project.txt", notes, "text/plain"))
notes_thread
''');
      check(r, label: 'setup');

      r = await s.execute('''
import json
target = "qwen_8b"
resp = json.loads(soliplex_reply_thread("local", target, notes_thread,
    "Read project.txt. What is the budget per engineer?"))
preview = resp["response"][:400]
{"response": preview}
''');
      check(r, label: 'context-aware');
    },
  );

  // ── E28: List threads after creation ───────────────────────────────
  await lab.run(
    'List threads — verify created threads appear',
    'soliplex_list_threads returns threads on demo/cooking',
    (s) async {
      final r = await s.execute('''
import json
threads = json.loads(soliplex_list_threads("demo", "cooking"))
count = len(threads)
sample = threads[:3] if count >= 3 else threads
has_ids = True
for t in threads:
    if "id" not in t:
        has_ids = False
{"thread_count": count, "sample": sample, "has_ids": has_ids}
''');
      check(r);
    },
  );

  await lab.close();
}

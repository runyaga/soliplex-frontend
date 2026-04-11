// ignore_for_file: avoid_print
/// EXP 39–46: Advanced parent↔child communication patterns.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_06_cross_comm.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(withSandbox: true, startNum: 38);

  // ── E39: Structured task dispatch ──────────────────────────────────
  await lab.run(
    'Task dispatch — parent sends work, child returns weighted average',
    'Parent sends items+weights; child computes and replies via bus',
    (s) async {
      final r = await s.execute(r'''
h = sandbox_spawn(code="task = msg_recv(name=\"task_39\")\nitems = task[\"items\"]\nweights = task[\"weights\"]\ntw = 0\nws = 0\nfor i in range(len(items)):\n    ws = ws + items[i] * weights[i]\n    tw = tw + weights[i]\navg = ws / tw if tw > 0 else 0\nmsg_send(name=\"result_39\", message={\"weighted_avg\": avg, \"total_weight\": tw})\n\"done\"")
msg_send(name="task_39", message={"items": [85, 92, 78, 95, 88], "weights": [10, 20, 30, 25, 15]})
sandbox_await(handle=h)
result = msg_recv(name="result_39")
sandbox_free(handle=h)
expected = (85*10 + 92*20 + 78*30 + 95*25 + 88*15) / 100
diff = abs(result["weighted_avg"] - expected)
ok = diff < 0.01
{"result": result, "expected": expected, "ok": ok}
''');
      check(r);
    },
  );

  // ── E40: Two children ping-pong ────────────────────────────────────
  await lab.run(
    'Two children exchange — A sends to B, B doubles, A reports',
    'Child A→B→A round trip via message bus',
    (s) async {
      final r = await s.execute(r'''
h_a = sandbox_spawn(code="msg_send(name=\"a2b\", message={\"value\": 10})\nresp = msg_recv(name=\"b2a\")\nmsg_send(name=\"a_final\", message={\"original\": 10, \"doubled\": resp[\"result\"]})\n\"A done\"")
h_b = sandbox_spawn(code="task = msg_recv(name=\"a2b\")\nresult = task[\"value\"] * 2\nmsg_send(name=\"b2a\", message={\"result\": result})\n\"B done\"")
sandbox_await(handle=h_a)
sandbox_await(handle=h_b)
final_result = msg_recv(name="a_final")
sandbox_free(handle=h_a)
sandbox_free(handle=h_b)
ok = final_result["doubled"] == 20
{"final": final_result, "correct": ok}
''');
      check(r);
    },
  );

  // ── E41: Producer-consumer ─────────────────────────────────────────
  await lab.run(
    'Producer-consumer — one produces 5 items, another aggregates',
    'Producer sends items then DONE sentinel; consumer reads until sentinel',
    (s) async {
      final r = await s.execute(r'''
h_p = sandbox_spawn(code="items = [{\"name\": \"a\", \"val\": 10}, {\"name\": \"b\", \"val\": 20}, {\"name\": \"c\", \"val\": 30}, {\"name\": \"d\", \"val\": 40}, {\"name\": \"e\", \"val\": 50}]\nfor item in items:\n    msg_send(name=\"wq41\", message=item)\nmsg_send(name=\"wq41\", message={\"name\": \"DONE\", \"val\": 0})\n\"produced\"")
h_c = sandbox_spawn(code="collected = []\nwhile True:\n    item = msg_recv(name=\"wq41\")\n    if item[\"name\"] == \"DONE\":\n        break\n    collected.append(item)\ntotal = 0\nfor c in collected:\n    total = total + c[\"val\"]\nmsg_send(name=\"cr41\", message={\"count\": len(collected), \"total\": total})\n\"consumed\"")
sandbox_await(handle=h_p)
sandbox_await(handle=h_c)
result = msg_recv(name="cr41")
sandbox_free(handle=h_p)
sandbox_free(handle=h_c)
cnt_ok = result["count"] == 5
tot_ok = result["total"] == 150
{"result": result, "count_ok": cnt_ok, "total_ok": tot_ok}
''');
      check(r);
    },
  );

  // ── E42: Fan-out + fan-in — 5 workers ──────────────────────────────
  await lab.run(
    'Fan-out + fan-in — 5 workers compute powers independently',
    'Parent distributes base^exp tasks, gathers results',
    (s) async {
      final r = await s.execute(r'''
tasks = [{"id": 0, "b": 2, "e": 10}, {"id": 1, "b": 3, "e": 8}, {"id": 2, "b": 5, "e": 6}, {"id": 3, "b": 7, "e": 5}, {"id": 4, "b": 11, "e": 4}]
handles = []
for t in tasks:
    ch = "fi_" + str(t["id"])
    h = sandbox_spawn(code="task = msg_recv(name=\"" + ch + "\")\nresult = 1\nfor i in range(task[\"e\"]):\n    result = result * task[\"b\"]\nmsg_send(name=\"fo42\", message={\"id\": task[\"id\"], \"result\": result})\nresult")
    handles.append(h)
    msg_send(name=ch, message=t)
for h in handles:
    sandbox_await(handle=h)
results = []
for i in range(5):
    results.append(msg_recv(name="fo42"))
for h in handles:
    sandbox_free(handle=h)
actual = [0, 0, 0, 0, 0]
for r in results:
    actual[r["id"]] = r["result"]
expected = [1024, 6561, 15625, 16807, 14641]
ok = actual == expected
{"actual": actual, "expected": expected, "all_correct": ok}
''');
      check(r);
    },
  );

  // ── E43: Round-robin relay — 3 children ────────────────────────────
  await lab.run(
    'Round-robin — 3-child relay, each transforms value',
    'Start=1: child1 +10, child2 *3, child3 -5 → expect 28',
    (s) async {
      final r = await s.execute(r'''
h1 = sandbox_spawn(code="val = msg_recv(name=\"rr_start\")\nmsg_send(name=\"rr_12\", message=val + 10)\n\"c1\"")
h2 = sandbox_spawn(code="val = msg_recv(name=\"rr_12\")\nmsg_send(name=\"rr_23\", message=val * 3)\n\"c2\"")
h3 = sandbox_spawn(code="val = msg_recv(name=\"rr_23\")\nmsg_send(name=\"rr_end\", message=val - 5)\n\"c3\"")
msg_send(name="rr_start", message=1)
sandbox_await(handle=h1)
sandbox_await(handle=h2)
sandbox_await(handle=h3)
final_val = msg_recv(name="rr_end")
sandbox_free(handle=h1)
sandbox_free(handle=h2)
sandbox_free(handle=h3)
ok = final_val == 28
{"final": final_val, "expected": 28, "correct": ok, "chain": "1+10=11 *3=33 -5=28"}
''');
      check(r);
    },
  );

  // ── E44: Cross-server via children ─────────────────────────────────
  await lab.run(
    'Cross-server via children — child1 queries demo, child2 queries local',
    'Parallel server queries merged by parent',
    (s) async {
      final r = await s.execute(r'''
import json
h_d = sandbox_spawn(code="import json\nrooms = json.loads(soliplex_list_rooms(\"demo\"))\nnames = [r[\"name\"] for r in rooms]\nmsg_send(name=\"dr44\", message={\"server\": \"demo\", \"rooms\": names})\n\"done\"")
h_l = sandbox_spawn(code="import json\nrooms = json.loads(soliplex_list_rooms(\"local\"))\nnames = [r[\"name\"] for r in rooms]\nmsg_send(name=\"lr44\", message={\"server\": \"local\", \"rooms\": names})\n\"done\"")
sandbox_await(handle=h_d)
sandbox_await(handle=h_l)
dr = msg_recv(name="dr44")
lr = msg_recv(name="lr44")
sandbox_free(handle=h_d)
sandbox_free(handle=h_l)
total = len(dr["rooms"]) + len(lr["rooms"])
both = len(dr["rooms"]) > 0 and len(lr["rooms"]) > 0
{"demo": dr, "local": lr, "total_rooms": total, "both_have_rooms": both}
''');
      check(r);
    },
  );

  // ── E45: Template in child → bus → parent saves to FS ──────────────
  await lab.run(
    'Template in child → bus → parent saves to filesystem',
    'Child renders markdown table; parent writes to MemoryFs',
    (s) async {
      final r = await s.execute(r'''
import json
from pathlib import Path
h = sandbox_spawn(code="import json\ndata = {\"title\": \"Inventory\", \"items\": [{\"name\": \"demo\", \"status\": \"online\"}, {\"name\": \"local\", \"status\": \"online\"}]}\nrendered = tmpl_render(template=\"# {{ title }}\\n{% for i in items %}* {{ i.name }}: {{ i.status }}\\n{% endfor %}\", context=data)\nmsg_send(name=\"rpt45\", message={\"md\": rendered})\n\"done\"")
sandbox_await(handle=h)
report = msg_recv(name="rpt45")
sandbox_free(handle=h)
Path("/reports").mkdir(parents=True, exist_ok=True)
Path("/reports/inv.md").write_text(report["md"])
saved = Path("/reports/inv.md").read_text()
has_title = "Inventory" in saved
has_table = "demo" in saved and "local" in saved
slen = len(saved)
{"saved_len": slen, "has_title": has_title, "has_servers": has_table, "preview": saved[:200]}
''');
      check(r);
    },
  );

  // ── E46: Broadcast — parent sends to 4 children, different ops ─────
  await lab.run(
    'Broadcast — 4 children each apply different transform',
    'Same data [10,20,30,40,50]; children compute sum, max, min, avg',
    (s) async {
      final r = await s.execute(r'''
ops = ["sum", "max", "min", "avg"]
handles = []
for op in ops:
    ch = "bc_" + op
    h = sandbox_spawn(code="d = msg_recv(name=\"" + ch + "\")\nnums = d[\"numbers\"]\nop = d[\"op\"]\nif op == \"sum\":\n    r = 0\n    for n in nums:\n        r = r + n\nelif op == \"max\":\n    r = nums[0]\n    for n in nums:\n        if n > r:\n            r = n\nelif op == \"min\":\n    r = nums[0]\n    for n in nums:\n        if n < r:\n            r = n\nelif op == \"avg\":\n    t = 0\n    for n in nums:\n        t = t + n\n    r = t / len(nums)\nelse:\n    r = None\nmsg_send(name=\"bc_out\", message={\"op\": op, \"result\": r})\nr")
    handles.append(h)
    msg_send(name=ch, message={"numbers": [10, 20, 30, 40, 50], "op": op})
for h in handles:
    sandbox_await(handle=h)
results = {}
for i in range(4):
    r = msg_recv(name="bc_out")
    results[r["op"]] = r["result"]
for h in handles:
    sandbox_free(handle=h)
s_ok = results.get("sum") == 150
mx_ok = results.get("max") == 50
mn_ok = results.get("min") == 10
a_ok = abs(results.get("avg", 0) - 30.0) < 0.01
{"results": results, "sum_ok": s_ok, "max_ok": mx_ok, "min_ok": mn_ok, "avg_ok": a_ok}
''');
      check(r);
    },
  );

  await lab.close();
}

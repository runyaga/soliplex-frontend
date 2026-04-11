// ignore_for_file: avoid_print
/// EXP 29–38: SandboxPlugin — spawn child interpreters, parallel execution,
/// plugin inheritance, fan-out, pipeline, depth.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_05_sandbox_spawn.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(withSandbox: true, startNum: 28);

  // ── E29: Spawn single child, await result ──────────────────────────
  await lab.run(
    'Spawn single child — compute Fibonacci',
    'sandbox_spawn + sandbox_await returns child result',
    (s) async {
      final r = await s.execute('''
h = sandbox_spawn(code="def fib(n):\\n    a = 0\\n    b = 1\\n    res = []\\n    for i in range(n):\\n        res.append(a)\\n        t = a + b\\n        a = b\\n        b = t\\n    return res\\nfib(15)")
result = sandbox_await(handle=h)
output = sandbox_get_output(handle=h)
sandbox_free(handle=h)
count = len(result) if isinstance(result, list) else 0
{"fibonacci": result, "output": output, "count": count}
''');
      check(r);
    },
  );

  // ── E30: Spawn 3 children, gather results ──────────────────────────
  await lab.run(
    'Spawn 3 children — gather attributed results',
    'sandbox_gather returns [{handle, value, output}] for each child',
    (s) async {
      final r = await s.execute(r'''
h0 = sandbox_spawn(code="print('worker-A')\n100 + 1")
h1 = sandbox_spawn(code="print('worker-B')\n200 + 2")
h2 = sandbox_spawn(code="print('worker-C')\n300 + 3")
results = sandbox_gather(handles=[h0, h1, h2])
v0 = results[0]["value"]
v1 = results[1]["value"]
v2 = results[2]["value"]
ok = v0 == 101 and v1 == 202 and v2 == 303
{"count": len(results), "values": [v0, v1, v2], "all_correct": ok}
''');
      check(r);
    },
  );

  // ── E31: Child inherits MessageBusPlugin ───────────────────────────
  await lab.run(
    'Child inherits MessageBusPlugin — parent↔child messaging',
    'Parent sends task via msg_send, child receives, processes, replies',
    (s) async {
      final r = await s.execute(r'''
h = sandbox_spawn(code="task = msg_recv(name=\"work_31\")\ntotal = 0\nfor item in task[\"numbers\"]:\n    total = total + item\nmsg_send(name=\"result_31\", message={\"sum\": total, \"count\": len(task[\"numbers\"])})\n\"child done\"")
msg_send(name="work_31", message={"numbers": [10, 20, 30, 40, 50]})
sandbox_await(handle=h)
result = msg_recv(name="result_31")
sandbox_free(handle=h)
sum_ok = result["sum"] == 150
cnt_ok = result["count"] == 5
{"child_result": result, "sum_correct": sum_ok, "count_correct": cnt_ok}
''');
      check(r);
    },
  );

  // ── E32: Child inherits SoliplexPlugin ─────────────────────────────
  await lab.run(
    'Child inherits SoliplexPlugin — child lists servers',
    'Spawned child calls soliplex_list_servers() independently',
    (s) async {
      final r = await s.execute(r'''
import json
h = sandbox_spawn(code="import json\nservers = json.loads(soliplex_list_servers())\nids = [sv[\"id\"] for sv in servers]\nids")
result = sandbox_await(handle=h)
sandbox_free(handle=h)
has_demo = "demo" in result if isinstance(result, list) else False
has_local = "local" in result if isinstance(result, list) else False
{"child_saw": result, "has_demo": has_demo, "has_local": has_local}
''');
      check(r);
    },
  );

  // ── E33: Child with timeout ────────────────────────────────────────
  await lab.run(
    'Child with timeout — fast child completes within limit',
    'sandbox_spawn with timeout_ms; child finishes before deadline',
    (s) async {
      final r = await s.execute('''
h = sandbox_spawn(code="42 * 42", timeout_ms=5000)
alive = sandbox_is_alive(handle=h)
result = sandbox_await(handle=h)
sandbox_free(handle=h)
ok = result == 1764
{"result": result, "correct": ok, "was_alive": alive}
''');
      check(r);
    },
  );

  // ── E34: Fan-out — 4 workers query rooms in parallel ───────────────
  await lab.run(
    'Fan-out — 4 workers query servers in parallel',
    'Spawn 4 children, each does a different server query',
    (s) async {
      final r = await s.execute(r'''
import json
h0 = sandbox_spawn(code="import json\nrooms = json.loads(soliplex_list_rooms(\"demo\"))\n[r[\"id\"] for r in rooms]")
h1 = sandbox_spawn(code="import json\nrooms = json.loads(soliplex_list_rooms(\"local\"))\n[r[\"id\"] for r in rooms]")
h2 = sandbox_spawn(code="import json\nroom = json.loads(soliplex_get_room(\"demo\", \"cooking\"))\nroom[\"name\"]")
h3 = sandbox_spawn(code="import json\nservers = json.loads(soliplex_list_servers())\nlen(servers)")
results = sandbox_gather(handles=[h0, h1, h2, h3])
demo_rooms = results[0]["value"]
local_rooms = results[1]["value"]
cooking = results[2]["value"]
scount = results[3]["value"]
ok = demo_rooms != None and local_rooms != None
{"demo_rooms": demo_rooms, "local_rooms": local_rooms, "cooking_name": cooking, "server_count": scount, "ok": ok}
''');
      check(r);
    },
  );

  // ── E35: Pipeline — child1 → msgbus → child2 → msgbus → parent ────
  await lab.run(
    'Pipeline — 2-stage child pipeline via message bus',
    'Child1 produces, sends to bus; Child2 transforms, sends to parent',
    (s) async {
      final r = await s.execute(r'''
h1 = sandbox_spawn(code="data = {\"numbers\": [1, 2, 3, 4, 5], \"op\": \"square\"}\nmsg_send(name=\"s1out\", message=data)\n\"s1 done\"")
h2 = sandbox_spawn(code="data = msg_recv(name=\"s1out\")\nnums = data[\"numbers\"]\nsq = []\nfor n in nums:\n    sq.append(n * n)\ntot = 0\nfor v in sq:\n    tot = tot + v\nmsg_send(name=\"s2out\", message={\"squared\": sq, \"sum\": tot})\n\"s2 done\"")
sandbox_await(handle=h1)
sandbox_await(handle=h2)
result = msg_recv(name="s2out")
sandbox_free(handle=h1)
sandbox_free(handle=h2)
sq_ok = result["squared"] == [1, 4, 9, 16, 25]
sum_ok = result["sum"] == 55
{"pipeline_result": result, "squared_ok": sq_ok, "sum_ok": sum_ok}
''');
      check(r);
    },
  );

  // ── E36: Spawn depth — parent → child → grandchild ─────────────────
  await lab.run(
    'Spawn depth — parent → child → grandchild (depth 2)',
    'Child spawns its own child; grandchild computes, bubbles up',
    (s) async {
      final r = await s.execute(r'''
h = sandbox_spawn(code="gc = sandbox_spawn(code=\"7 * 7 * 7\")\ngc_r = sandbox_await(handle=gc)\nsandbox_free(handle=gc)\ngc_r + 1")
result = sandbox_await(handle=h)
sandbox_free(handle=h)
gc_val = result - 1
ok = result == 344
{"grandchild_val": gc_val, "child_result": result, "correct": ok}
''');
      check(r);
    },
  );

  // ── E37: Filesystem isolation between parent and child ─────────────
  await lab.run(
    'Spawn with filesystem — child has isolated MemoryFs',
    'Parent writes file; child writes its own; verify isolation',
    (s) async {
      var r = await s.execute('''
from pathlib import Path
Path("/pdata").mkdir(parents=True, exist_ok=True)
Path("/pdata/secret.txt").write_text("parent-only")
"parent wrote file"
''');
      check(r, label: 'parent-write');

      r = await s.execute(r'''
h = sandbox_spawn(code="from pathlib import Path\np_exists = Path(\"/pdata/secret.txt\").exists()\nPath(\"/cdata\").mkdir(parents=True, exist_ok=True)\nPath(\"/cdata/child.txt\").write_text(\"child-only\")\nc_content = Path(\"/cdata/child.txt\").read_text()\n{\"parent_visible\": p_exists, \"child_content\": c_content}")
child_result = sandbox_await(handle=h)
sandbox_free(handle=h)
from pathlib import Path
parent_ok = Path("/pdata/secret.txt").read_text() == "parent-only"
child_file = Path("/cdata/child.txt").exists()
{"child": child_result, "parent_intact": parent_ok, "child_file_in_parent": child_file}
''');
      check(r, label: 'isolation');
    },
  );

  // ── E38: Child uses all plugins — template + msgbus + soliplex ─────
  await lab.run(
    'Child uses all plugins — template + msgbus + soliplex',
    'Child renders template with server data and sends via bus',
    (s) async {
      final r = await s.execute(r'''
import json
h = sandbox_spawn(code="import json\nservers = json.loads(soliplex_list_servers())\nids = [sv[\"id\"] for sv in servers]\nrendered = tmpl_render(template=\"Servers: {% for s in servers %}{{ s }}{% if not loop.last %}, {% endif %}{% endfor %}\", context={\"servers\": ids})\nmsg_send(name=\"full38\", message={\"rendered\": rendered, \"count\": len(ids)})\n\"done\"")
sandbox_await(handle=h)
result = msg_recv(name="full38")
sandbox_free(handle=h)
has_demo = "demo" in result["rendered"]
has_local = "local" in result["rendered"]
{"rendered": result["rendered"], "count": result["count"], "has_demo": has_demo, "has_local": has_local}
''');
      check(r);
    },
  );

  await lab.close();
}

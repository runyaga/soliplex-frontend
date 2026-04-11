// ignore_for_file: avoid_print
/// EXP 07–14: Each plugin exercised in isolation.
///
/// DinjaTemplatePlugin, MessageBusPlugin, MemoryFsProvider, TimeOsProvider,
/// EnvOsProvider — all host functions tested individually.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_02_single_plugin.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(startNum: 6);

  // ── E07: Template — simple variable substitution ────────────────────
  await lab.run(
    'Template render — variable substitution',
    'tmpl_render with {{ name }} and {{ count }} produces correct output',
    (s) async {
      final r = await s.execute('''
ctx = {"name": "Soliplex", "count": 42}
result = tmpl_render(template="Hello {{ name }}, you have {{ count }} items.", context=ctx)
result
''');
      check(r);
    },
  );

  // ── E08: Template — for loop ────────────────────────────────────────
  await lab.run(
    'Template render — for loop over list',
    'tmpl_render iterates items and produces numbered markdown list',
    (s) async {
      final r = await s.execute(r'''
items = ["Foundation", "Framing", "Roofing", "Plumbing", "Electrical"]
ctx = {"items": items}
tmpl = "## Tasks\n{% for item in items %}{{ loop.index }}. {{ item }}\n{% endfor %}"
result = tmpl_render(template=tmpl, context=ctx)
result
''');
      check(r);
    },
  );

  // ── E09: Template — conditionals ───────────────────────────────────
  await lab.run(
    'Template render — if/else conditional',
    'tmpl_render branches on boolean and renders correct path',
    (s) async {
      final r = await s.execute(r'''
ctx = {"weather": "rain", "outdoor_jobs": 3, "indoor_jobs": 2}
tmpl = "{% if weather == 'rain' %}RAIN: {{ indoor_jobs }} indoor jobs only{% else %}CLEAR: all {{ outdoor_jobs + indoor_jobs }} jobs go{% endif %}"
result = tmpl_render(template=tmpl, context=ctx)
result
''');
      check(r);
    },
  );

  // ── E10: Message bus — send and recv ───────────────────────────────
  await lab.run(
    'Message bus — basic send/recv round-trip',
    'msg_send then msg_recv on same channel returns exact payload',
    (s) async {
      final r = await s.execute('''
payload = {"type": "task", "data": [1, 2, 3], "meta": "test"}
msg_send(name="test_ch", message=payload)
received = msg_recv(name="test_ch")
match = received == payload
{"sent": payload, "received": received, "match": match}
''');
      check(r);
    },
  );

  // ── E11: Message bus — multiple channels ───────────────────────────
  await lab.run(
    'Message bus — multiple independent channels',
    'Messages on channel A do not leak to channel B',
    (s) async {
      final r = await s.execute('''
msg_send(name="alpha", message="hello-alpha")
msg_send(name="beta", message="hello-beta")
msg_send(name="gamma", message="hello-gamma")
a = msg_recv(name="alpha")
b = msg_recv(name="beta")
g = msg_recv(name="gamma")
{"alpha": a, "beta": b, "gamma": g, "isolated": a != b and b != g}
''');
      check(r);
    },
  );

  // ── E12: Message bus — peek (non-blocking) ────────────────────────
  await lab.run(
    'Message bus — peek without consuming',
    'msg_peek returns front of queue without removing it; msg_recv still gets it',
    (s) async {
      final r = await s.execute('''
msg_send(name="peek_ch", message={"val": 99})
peeked = msg_peek(name="peek_ch")
still_there = msg_recv(name="peek_ch")
empty_after = msg_peek(name="peek_ch")
is_empty = empty_after == None
did_match = peeked == still_there
{"peeked": peeked, "recv_after_peek": still_there, "empty_after_recv": is_empty, "peek_matched": did_match}
''');
      check(r);
    },
  );

  // ── E13: Message bus — stats telemetry ────────────────────────────
  await lab.run(
    'Message bus — channel statistics',
    'msg_stats returns send_count, recv_count, queue_depth after operations',
    (s) async {
      final r = await s.execute('''
msg_send(name="stats_ch", message="a")
msg_send(name="stats_ch", message="b")
msg_send(name="stats_ch", message="c")
msg_recv(name="stats_ch")
stats = msg_stats(name="stats_ch")
sc = stats["send_count"]
rc = stats["recv_count"]
qd = stats["queue_depth"]
depth_ok = qd == 2
{"send_count": sc, "recv_count": rc, "queue_depth": qd, "expected_depth_2": depth_ok}
''');
      check(r);
    },
  );

  // ── E14: Filesystem — write, read, mkdir, exists ──────────────────
  await lab.run(
    'MemoryFsProvider — full filesystem round-trip',
    'mkdir, write_text, read_text, exists, iterdir all work on in-memory FS',
    (s) async {
      final r = await s.execute(r'''
from pathlib import Path
Path("/workspace").mkdir(parents=True, exist_ok=True)
Path("/workspace/data").mkdir(parents=True, exist_ok=True)
Path("/workspace/data/report.txt").write_text("Line 1\nLine 2\nLine 3")
Path("/workspace/data/config.json").write_text('{"key": "value"}')
content = Path("/workspace/data/report.txt").read_text()
exists_report = Path("/workspace/data/report.txt").exists()
exists_missing = Path("/workspace/data/nope.txt").exists()
files = [str(p) for p in Path("/workspace/data").iterdir()]
line_count = len(content.split("\n"))
{"content": content, "exists_report": exists_report, "exists_missing": exists_missing, "files": files, "line_count": line_count}
''');
      check(r);
    },
  );

  await lab.close();
}

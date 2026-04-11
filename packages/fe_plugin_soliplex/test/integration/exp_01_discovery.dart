// ignore_for_file: avoid_print
/// EXP 01–06: Server, room, and function discovery.
///
/// Validates that both servers are reachable, rooms are enumerable,
/// room configs are detailed, and all registered host functions are visible.
///
/// Run:
///   cd packages/fe_plugin_soliplex
///   dart run test/integration/exp_01_discovery.dart
import 'exp_helpers.dart';

Future<void> main() async {
  final lab = Lab.start(startNum: 0);

  // ── E01 ─────────────────────────────────────────────────────────────
  await lab.run(
    'List all connected servers',
    'soliplex_list_servers() returns both "demo" and "local"',
    (s) async {
      final r = await s.execute('''
import json
servers = json.loads(soliplex_list_servers())
ids = [s["id"] for s in servers]
ids.sort()
ids
''');
      check(r);
    },
  );

  // ── E02 ─────────────────────────────────────────────────────────────
  await lab.run(
    'List rooms on demo.toughserv.com',
    'soliplex_list_rooms("demo") returns at least cooking, chat, soliplex',
    (s) async {
      final r = await s.execute('''
import json
rooms = json.loads(soliplex_list_rooms("demo"))
result = []
for room in rooms:
    result.append({"id": room["id"], "name": room["name"]})
result
''');
      check(r);
    },
  );

  // ── E03 ─────────────────────────────────────────────────────────────
  await lab.run(
    'List rooms on localhost:8000',
    'soliplex_list_rooms("local") returns rooms including chat',
    (s) async {
      final r = await s.execute('''
import json
rooms = json.loads(soliplex_list_rooms("local"))
result = []
for room in rooms:
    result.append({"id": room["id"], "name": room["name"]})
result
''');
      check(r);
    },
  );

  // ── E04 ─────────────────────────────────────────────────────────────
  await lab.run(
    'Get full room config for demo/cooking',
    'soliplex_get_room returns name, tools, skills, welcome_message',
    (s) async {
      final r = await s.execute('''
import json
room = json.loads(soliplex_get_room("demo", "cooking"))
result = {
    "id": room["id"],
    "name": room["name"],
    "has_tools": len(room.get("tools", [])) > 0,
    "has_skills": len(room.get("skills", [])) > 0,
    "has_welcome": room.get("welcome_message", "") != "",
    "tools": room.get("tools", []),
    "skills": room.get("skills", []),
    "attachments": room.get("enable_attachments", False),
    "mcp": room.get("allow_mcp", False),
}
result
''');
      check(r);
    },
  );

  // ── E05 ─────────────────────────────────────────────────────────────
  await lab.run(
    'Discover ALL registered host functions via help()',
    'help() enumerates every function from every plugin namespace',
    (s) async {
      final r = await s.execute(r'''
import json
raw = help()
lines = raw.strip().split("\n") if isinstance(raw, str) else []
functions = []
for line in lines:
    line = line.strip()
    if line and not line.startswith("#") and not line.startswith("-"):
        if "(" in line:
            name = line.split("(")[0].strip()
            if name:
                functions.append(name)
result = {
    "total_functions": len(functions),
    "functions": functions,
    "has_soliplex": any(f.startswith("soliplex_") for f in functions),
    "has_tmpl": any(f.startswith("tmpl_") for f in functions),
    "has_msg": any(f.startswith("msg_") for f in functions),
    "has_sandbox": any(f.startswith("sandbox_") for f in functions),
}
result
''');
      check(r);
    },
  );

  // ── E06 ─────────────────────────────────────────────────────────────
  await lab.run(
    'Cross-server room comparison',
    'Enumerate rooms on both servers and compare — find which room IDs overlap',
    (s) async {
      final r = await s.execute('''
import json
demo_rooms = json.loads(soliplex_list_rooms("demo"))
local_rooms = json.loads(soliplex_list_rooms("local"))
demo_ids = [r["id"] for r in demo_rooms]
local_ids = [r["id"] for r in local_rooms]
overlap = [rid for rid in demo_ids if rid in local_ids]
only_demo = [rid for rid in demo_ids if rid not in local_ids]
only_local = [rid for rid in local_ids if rid not in demo_ids]
result = {
    "demo_count": len(demo_ids),
    "local_count": len(local_ids),
    "overlap": overlap,
    "only_demo": only_demo,
    "only_local": only_local,
}
result
''');
      check(r);
    },
  );

  await lab.close();
}

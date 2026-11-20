#!/usr/bin/env bash
set -euo pipefail
# Host only. Claude reviews this file before running it. Never enable xtrace.
set +x
umask 077
fail() { printf '%s\n' "$*" >&2; exit 1; }
readonly ENV_FILE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/workbench.env"
readonly STACK_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKBENCH_PACKAGE="$(cd -- "$STACK_SCRIPT_DIR/../backend/soliplex_a2ui_workbench" && pwd)"
test -f "$ENV_FILE" || fail 'Missing workbench/stack/workbench.env. Copy workbench.env.example and fill in the required values.'
# This is a trusted shell env file. Suppress diagnostics that could contain secrets.
source "$ENV_FILE" >/dev/null 2>&1 || fail 'Could not load workbench/stack/workbench.env. Check its shell syntax locally.'
set +x
for name in DEV_ROOT MODEL_HOST OLLAMA_HOST WB_ADMIN_USER WB_ADMIN_EMAIL WB_ADMIN_PASSWORD; do
  test -n "${!name:-}" || fail "Required variable $name is empty or missing in workbench/stack/workbench.env."
done
LOGFIRE_ENV_FILE="${LOGFIRE_ENV_FILE:-$DEV_ROOT/.env}"
SOLIPLEX_WORKBENCH_ROOMS="${SOLIPLEX_WORKBENCH_ROOMS:-workbench,workbench-e4b}"
export DEV_ROOT MODEL_HOST OLLAMA_HOST WB_ADMIN_USER WB_ADMIN_EMAIL WB_ADMIN_PASSWORD LOGFIRE_ENV_FILE SOLIPLEX_WORKBENCH_ROOMS STACK_SCRIPT_DIR WORKBENCH_PACKAGE
readonly PROJECT=soliplex-a2ui-workbench
readonly TARGET="$DEV_ROOT/soliplex-a2ui-workbench"
readonly TEMPLATE="$DEV_ROOT/soliplex-template"
# Frozen copies. Port upstream changes deliberately (owner decision 2026-11-19).
readonly LAB="$DEV_ROOT/soliplex-a2ui-workbench-build/lab-snapshot"
readonly FRONTEND="$DEV_ROOT/soliplex-frontend-wt/exp-workbench-preview"
readonly SCRATCH="$DEV_ROOT/soliplex-a2ui-workbench-build"
readonly PIN=4d9b4b8e639b38289d2893187343baa8df65bfa3
export PROJECT TARGET TEMPLATE LAB FRONTEND SCRATCH PIN
unset COMPOSE_FILE COMPOSE_PATH_SEPARATOR COMPOSE_PROFILES COMPOSE_ENV_FILES
export COMPOSE_PROJECT_NAME="$PROJECT"
unset COMPOSE_DISABLE_ENV_FILE
# Subprocesses in the template use plain docker compose. Fix both project and cwd.
export COMPOSE_PROJECT_DIRECTORY="$TARGET"
guard() {
  python3 - <<'PY'
import os
from pathlib import Path
blocked = {'soliplex-dojo', 'soliplex-a2ui-lab', 'soliplex-afsoc'}
assert os.environ['PROJECT'] not in blocked
assert os.environ['PROJECT'] == 'soliplex-a2ui-workbench'
for key, expected in [('TARGET', os.environ['DEV_ROOT'] + '/soliplex-a2ui-workbench'),
                      ('SCRATCH', os.environ['DEV_ROOT'] + '/soliplex-a2ui-workbench-build')]:
    p = Path(os.environ[key])
    assert str(p) == expected and str(p.resolve()) == expected, f'Unsafe {key}'
    assert not (set(p.parts) & blocked), f'Protected path {p}'
    # The scratch build tree holds Flutter-created symlinks by design.
    if key == 'TARGET' and p.exists():
        for root, dirs, files in os.walk(p):
            for name in dirs + files:
                q = Path(root) / name
                assert not q.is_symlink(), f'Refusing output tree symlink {q}'
PY
}
py() { uv run --no-project --python 3.12 --with pyyaml --with pydantic --with mako python - "$@"; }
need_stack() {
  guard
  test -f "$TARGET/.workbench-generated" || fail 'Run step1 first. Partial generation needs host review.'
  cd "$TARGET"
}
dc() { (cd "$TARGET" && docker compose --project-name "$PROJECT" --project-directory "$TARGET" "$@"); }
check_compose() {
  dc config --format json | python3 -c '
import json, os, sys
c = json.load(sys.stdin)
assert c["name"] == "soliplex-a2ui-workbench"
ports = []
for name, s in c["services"].items():
    assert not s.get("container_name"), "Explicit container name refused"
    assert s.get("network_mode") != "host"
    for p in s.get("ports", []):
        n = int(p["published"])
        assert n in (9700,9743), f"Unexpected published port {n}"
        assert name == "nginx"
        ports.append(n)
    for v in s.get("volumes", []):
        if v["type"] == "bind":
            assert v["source"].startswith(os.environ["TARGET"] + "/"), v
for kind in ("volumes", "networks"):
    for v in c.get(kind, {}).values():
        assert not v.get("external"), "External resource refused"
        if v.get("name"):
            assert v["name"].startswith("soliplex-a2ui-workbench_"), v
assert sorted(ports) == [9700,9743]
print("Compose isolation and published ports verified")'
}
step1() {
  # Prepare a reviewed template and generate once. No commits are created.
  guard
  for cmd in git uv python3 rsync docker flutter dcm; do command -v "$cmd" >/dev/null || fail "Missing $cmd"; done
  mkdir -p "$SCRATCH"
  if test -f "$TARGET/.workbench-generated"; then
    printf 'Generation already complete\n'
    return
  fi
  if test -d "$TARGET" && test -n "$(ls -A "$TARGET")"; then fail 'Nonempty target refused. Review partial generation manually.'; fi
  test -z "$(git -C "$TEMPLATE" status --porcelain)" || fail 'Template is dirty. No update performed.'
  if test "$(git -C "$TEMPLATE" branch --show-current)" = main; then
    git -C "$TEMPLATE" fetch origin main
    git -C "$TEMPLATE" merge --ff-only origin/main
    printf '%s\n' "$TEMPLATE" > "$SCRATCH/template-path"
  else
    test ! -e "$SCRATCH/template" || fail 'Review existing scratch template before retrying step1.'
    git clone --branch main --single-branch "$(git -C "$TEMPLATE" remote get-url origin)" "$SCRATCH/template"
    printf '%s\n' "$SCRATCH/template" > "$SCRATCH/template-path"
  fi
  local src
  src=$(cat "$SCRATCH/template-path")
  test "$(git -C "$src" rev-parse HEAD)" = "$PIN" || fail 'BLOCKER: upstream template drift. Review changes and refresh this script before generating.'
  python3 - <<'PY'
import json, os
from pathlib import Path
p = dict(project_name=os.environ['PROJECT'], server_name='soliplex-a2ui-workbench.localhost',
         nginx_http=9700, nginx_https=9743, ollama_base_url='http://127.0.0.1:11434',
         chat_model='Inferact/Muse-Glimmer-30B-NVFP4-W4A4', chat_model_alt='gemma4:e4b',
         title_model='Inferact/Muse-Glimmer-30B-NVFP4-W4A4',
         rag_qa_model='Inferact/Muse-Glimmer-30B-NVFP4-W4A4',
         rag_embed_model='nvidia/llama-nemotron-embed-vl-1b-v2', rag_embed_dim=2048,
         include_gitea=False, include_tui=False, enable_sandbox=False)
Path(os.environ['SCRATCH'], 'params.json').write_text(json.dumps(p, indent=2)+'\n')
PY
  # stdout AND stderr are discarded. Failures never replay secret-bearing logs.
  if ! uv run "$src/skills/soliplex-template/scripts/generate_soliplex_project.py" \
      --out "$TARGET" --params "$SCRATCH/params.json" --no-git >/dev/null 2>&1; then
    fail 'Generator failed. Output withheld because it may contain secrets. Review target locally.'
  fi
  touch "$TARGET/.workbench-generated"
}
step2() {
  # Rotate exactly once, before any database volume can exist.
  need_stack
  if test -f .workbench-rotated; then printf 'Initial rotation already complete\n'; return; fi
  if docker volume inspect "${PROJECT}_postgres_data" >/dev/null 2>&1; then fail 'Database volume exists. Initial rotation refused.'; fi
  test -z "$(dc ps -aq)" || fail 'Containers exist. Initial rotation refused.'
  python3 - <<'PY'
import os, re, secrets
from pathlib import Path
p = Path(os.environ['TARGET'])
paths = sorted(set(re.findall(r'\./(\.secrets/[^\s]+\.gen)', (p/'docker-compose.yml').read_text())))
assert len(paths) == 6, 'Secret declarations changed. Review template.'
lengths = []
for rel in paths:
    q = p/rel
    old = q.read_text()
    value = secrets.token_hex(32)
    assert value != old
    with q.open('w') as f:
        f.write(value)
    q.chmod(0o600)
    lengths.append(len(value))
(p/'.workbench-rotated').touch()
print(f'Rotated count={len(paths)} lengths={lengths}')
PY
}
step3() {
  # Configure models, room, Docker 29 workaround, and Authelia without starting it.
  need_stack
  test -f .workbench-rotated || fail 'Run step2 first'
  local src
  src=$(cat "$SCRATCH/template-path")
  export TEMPLATE_SCRIPTS="$src/skills/soliplex-template/scripts"
  # --no-up avoids the fresh-store add bug and lets port fixes precede first start.
  uv run "$TEMPLATE_SCRIPTS/install_authelia.py" --project-dir "$TARGET" \
    --admin-email "$WB_ADMIN_EMAIL" --no-up >/dev/null 2>&1 || fail 'Authelia configuration failed. Output withheld.'
  py <<'PY'
import os, re, shutil
from pathlib import Path
import yaml
import sys
sys.path.insert(0, os.environ['STACK_SCRIPT_DIR'])
from compose_config import configure_workbench_storage, install_workbench_backend
p = Path(os.environ['TARGET'])
lab = Path(os.environ['LAB'])
def write(q, text):
    q.parent.mkdir(parents=True, exist_ok=True)
    with q.open('w') as f:
        f.write(text)
def save(q, value):
    write(q, yaml.safe_dump(value, sort_keys=False))
compose_path = p/'docker-compose.yml'
compose = yaml.safe_load(compose_path.read_text())
save(compose_path, configure_workbench_storage(compose))
router_name = install_workbench_backend(p, os.environ['WORKBENCH_PACKAGE'])
assert router_name == 'soliplex_a2ui_workbench.workbench_routes.guarded_router'
for rel, expected in [('backend/Dockerfile', 2), ('soliplex-dev/Dockerfile', 1)]:
    q = p/rel
    s = q.read_text()
    s = re.sub(r'(COPY --link [^\n]+ /tmp/[^\n]+\n)(?!RUN chmod 1777 /tmp\n)',
               r'\1RUN chmod 1777 /tmp\n', s)
    assert s.count('RUN chmod 1777 /tmp') == expected
    write(q, s)
q = p/'backend/environment/installation.yaml'
data = yaml.safe_load(q.read_text())
for a in data['agent_configs']:
    for old in ('usage_limits', 'run_timeout_seconds'):
        a.pop(old, None)
    if a['id'] == 'alternate_chat':
        a.update(model_name='gemma4:e4b', provider_type='ollama',
                 provider_base_url=f"http://{os.environ['OLLAMA_HOST']}:11434/v1",
                 model_settings={'max_tokens': 4096,
                 # Ollama ignores think:false on streamed /v1 calls. reasoning_effort none holds.
                 'extra_body': {'think': False, 'reasoning_effort': 'none'}})
        a.pop('context_window', None)
    else:
        a.update(provider_type='vllm', provider_base_url=f"http://{os.environ['MODEL_HOST']}:11450/v1",
                 context_window=131072, model_settings={'max_tokens': 32768,
                 'extra_body': {'chat_template_kwargs': {'reasoning_strength': 'medium'}}})
# Both room variants retain the same explicit Monty authoring instructions.
for name in ('monty-python', 'a2ui-client', 'python-retry'):
    dest = p/'backend/environment/skills'/name
    shutil.copytree(lab/'backend/environment/skills'/name, dest, dirs_exist_ok=True)
    if not any(x['skill_name'] == name for x in data.setdefault('skill_configs', [])):
        data['skill_configs'].append({'skill_name': name, 'kind': 'filesystem'})
save(q, data)
for rel in ('backend/environment/haiku.rag.yaml', 'haiku.rag/haiku.rag.yaml'):
    q = p/rel
    data = yaml.safe_load(q.read_text())
    data['embeddings'] = {'model': {'name': 'nvidia/llama-nemotron-embed-vl-1b-v2',
        'provider': 'vllm', 'base_url': f"http://{os.environ['MODEL_HOST']}:11438/v1", 'vector_dim': 2048}}
    if rel.startswith('backend/'):
        data['reranking'] = {'model': {'name': 'nvidia/llama-nemotron-rerank-vl-1b-v2',
            'provider': 'vllm', 'base_url': f"http://{os.environ['MODEL_HOST']}:11434"}}
        data['qa'] = {'model': {'name': 'Inferact/Muse-Glimmer-30B-NVFP4-W4A4',
            'provider': 'openai', 'base_url': f"http://{os.environ['MODEL_HOST']}:11450/v1"}}
    save(q, data)
# a2ui_lab imports a2ui_action from its own package. Copy both, rename the import.
for mod in ('a2ui_lab.py', 'a2ui_action.py'):
    text = (lab/'src/soliplex_a2ui_lab/src/soliplex_a2ui_lab'/mod).read_text()
    text = text.replace('from soliplex_a2ui_lab import', 'from soliplex_a2ui_workbench import')
    assert 'import soliplex_a2ui_lab' not in text and 'from soliplex_a2ui_lab' not in text, mod
    dest = p/'src/soliplex_a2ui_workbench/src/soliplex_a2ui_workbench'/mod
    # Seed once. Workbench edits to these modules are never overwritten.
    if not dest.exists():
        write(dest, text)
for room_id, agent in [('a2ui-lab','default_chat'), ('a2ui-lab-e4b','alternate_chat')]:
    source = lab/'backend/environment/rooms/a2ui-lab'
    data = yaml.safe_load((source/'room_config.yaml').read_text())
    data['id'] = room_id
    data['name'] = 'A2UI Lab' if agent == 'default_chat' else 'A2UI Lab E4B'
    data['agent']['template_id'] = agent
    for t in data['tools']:
        t['tool_name'] = t['tool_name'].replace('soliplex_a2ui_lab.', 'soliplex_a2ui_workbench.')
    save(p/'backend/environment/rooms'/room_id/'room_config.yaml', data)
    acl = yaml.safe_load((source/'authz.yaml').read_text())
    acl['room_id'] = room_id
    save(p/'backend/environment/rooms'/room_id/'authz.yaml', acl)
sys.path.insert(0, str(Path(os.environ['WORKBENCH_PACKAGE'])/'src'))
from soliplex_a2ui_workbench.workbench_schemas import MINIMUM_ROOM_TOOL_MANIFEST
for room_id, agent, model in [('workbench','default_chat','Glimmer'),
                              ('workbench-e4b','alternate_chat','Gemma 4 E4B')]:
    room = yaml.safe_load((lab/'backend/environment/rooms/a2ui-lab/room_config.yaml').read_text())
    room['id'] = room_id
    room['name'] = f'Workbench ({model})'
    from soliplex_a2ui_workbench.workbench_teaching import ROOM_SUGGESTIONS, WELCOME_MESSAGE
    room['welcome_message'] = WELCOME_MESSAGE
    room['suggestions'] = list(ROOM_SUGGESTIONS)
    room['agent']['template_id'] = agent
    room['tools'] = [{'tool_name': f"soliplex_a2ui_workbench.workbench_agent_tools.{name}"}
                     for name in MINIMUM_ROOM_TOOL_MANIFEST]
    save(p/'backend/environment/rooms'/room_id/'room_config.yaml', room)
    acl = yaml.safe_load((lab/'backend/environment/rooms/a2ui-lab/authz.yaml').read_text())
    acl['room_id'] = room_id
    save(p/'backend/environment/rooms'/room_id/'authz.yaml', acl)
    skill_name = f'{room_id}-workbench'
    # Combined guide includes generated catalog teaching without legacy lab tools.
    room['skills'] = {'installation_skill_names': [{'name': skill_name, 'defer_loading': False}]}
    save(p/'backend/environment/rooms'/room_id/'room_config.yaml', room)
    skill = p/'backend/environment/skills'/skill_name
    skill.mkdir(parents=True, exist_ok=True)
    from soliplex_a2ui_workbench.workbench_teaching import room_skill
    (skill/'SKILL.md').write_text(room_skill(skill_name))

installation = yaml.safe_load((p/'backend/environment/installation.yaml').read_text())
for room_id in ('workbench', 'workbench-e4b'):
    if not any(x['skill_name'] == f'{room_id}-workbench' for x in installation['skill_configs']):
        installation['skill_configs'].append({'skill_name': f'{room_id}-workbench', 'kind': 'filesystem'})
data = installation
# persist SOLIPLEX_WORKBENCH_ROOMS in the stack .env so a plain `docker compose up` keeps it.
env_path = p/'.env'
lines = env_path.read_text().splitlines() if env_path.exists() else []
lines = [l for l in lines if not l.startswith('SOLIPLEX_WORKBENCH_ROOMS=')]
lines.append('SOLIPLEX_WORKBENCH_ROOMS=' + os.environ['SOLIPLEX_WORKBENCH_ROOMS'])
with env_path.open('w') as f:
    f.write('\n'.join(lines) + '\n')
save(p/'backend/environment/installation.yaml', data)
q = p/'nginx/nginx.conf'
s = q.read_text()
if 'map $http_host $request_host_port' not in s:
    s = s.replace('    map $http_x_forwarded_port $backend_port {',
        '    map $http_host $request_host_port {\n'
        '      ~:(?<hp>[0-9]+)$ $hp;\n      default $server_port;\n    }\n\n'
        '    map $http_x_forwarded_port $backend_port {')
    s = s.replace('""      $server_port;', '""      $request_host_port;')
assert '""      $request_host_port;' in s
s = re.sub(r'(gzip_types[^\n]*)(;)', lambda m: m[0] if 'application/wasm' in m[1]
           else m[1]+' application/wasm;', s)
asset = '''        # Workbench static assets
        location ~* ^/(?!api/|mcp/|authelia/|ingester/|error-pages/).+\\.(?:js|wasm|css|json|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf)$ {
            limit_rate 0;
            try_files $uri =404;
        }

'''
if '# Workbench static assets' not in s:
    assert s.count('        location / {') == 2
    s = s.replace('        location / {', asset+'        location / {')
assert s.count('# Workbench static assets') == 2
write(q, s)
for rel, old, new in [
    ('authelia/configuration.yml', 'tcp://:9443/authelia', 'tcp://:9743/authelia'),
    ('nginx/conf.d/authelia.conf', 'https://authelia:9443/', 'https://authelia:9743/'),
    ('compose.authelia.yaml', 'https://localhost:9443/api/health', 'https://localhost:9743/api/health')]:
    q = p/rel
    s = q.read_text()
    assert old in s or new in s
    write(q, s.replace(old, new))
# A valid, empty file backend must exist before Authelia starts.
q = p/'authelia/users.yml'
if not q.exists():
    save(q, {'users': {}})
q = p/'.gitignore'
s = q.read_text()
for line in ('/frontend-web/', '/evidence/', '/.workbench-*'):
    if line not in s.splitlines():
        s += '\n'+line+'\n'
write(q, s)
# Logfire: token from LOGFIRE_ENV_FILE into a backend-only secret file. Value never printed.
env = Path(os.environ['LOGFIRE_ENV_FILE']).read_text().splitlines()
tok = [l.split('=', 1)[1].strip().strip('"').strip("'") for l in env if l.startswith('LOGFIRE_TOKEN=')]
assert len(tok) == 1 and tok[0], 'LOGFIRE_TOKEN missing in LOGFIRE_ENV_FILE'
q = p/'.secrets/logfire_token.gen'
with q.open('w') as f:
    f.write(tok[0])
q.chmod(0o600)
q = p/'docker-compose.yml'
s = q.read_text()
if 'logfire_token:' not in s:
    s = s.replace('      - url_safe_token_secret\n', '      - url_safe_token_secret\n      - logfire_token\n', 1)
    s = s.rstrip('\n') + '\n    logfire_token:\n      file: ./.secrets/logfire_token.gen\n'
    write(q, s)
q = p/'backend/environment/installation.yaml'
data = yaml.safe_load(q.read_text())
if not any(x.get('secret_name') == 'LOGFIRE_TOKEN' for x in data['secrets']):
    data['secrets'].append({'secret_name': 'LOGFIRE_TOKEN',
        'sources': [{'kind': 'file_path', 'file_path': '/run/secrets/logfire_token'}]})
data['logfire_config'] = {'token': 'secret:LOGFIRE_TOKEN', 'service_name': 'soliplex-a2ui-workbench',
    'environment': 'workbench', 'send_to_logfire': True}
save(q, data)
print('Logfire wired: service soliplex-a2ui-workbench, token length', len(tok[0]))
PY
  check_compose
}
step4() {
  # Build and initialize only this compose project. Capture operations that can
  # include credentials in errors. Never dump their logs to the terminal.
  need_stack
  check_compose
  dc build
  dc run --rm --quiet-build stack-init
  local src
  src=$(cat "$SCRATCH/template-path")
  export TEMPLATE_SCRIPTS="$src/skills/soliplex-template/scripts"
  if ! py >/dev/null 2>&1 <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, os.environ['TEMPLATE_SCRIPTS'])
import install_authelia
install_authelia.create_authelia_database(Path(os.environ['TARGET']))
PY
  then fail 'Authelia database setup failed. Output withheld.'; fi
  # Bootstrap a valid file backend before its first start. The final reset in
  # step5 still uses the reset tool's _generate_hash against the live service.
  if ! py >/dev/null 2>&1 <<'PYBOOT'
import os, re, subprocess
from pathlib import Path
import yaml
p = Path(os.environ['TARGET'])
q = p/'authelia/users.yml'
data = yaml.safe_load(q.read_text()) or {}
if not data.get('users'):
    r = subprocess.run(['docker','compose','run','--rm','--no-deps','-T','authelia',
        'authelia','crypto','hash','generate','argon2','--password',os.environ['WB_ADMIN_PASSWORD']],
        cwd=p, capture_output=True, text=True)
    if r.returncode:
        raise SystemExit('Bootstrap hash failed. Output withheld.')
    match = re.search(r'\$argon2\S*', r.stdout)
    assert match, 'No bootstrap digest returned'
    data['users'] = {os.environ['WB_ADMIN_USER']: {'displayname':os.environ['WB_ADMIN_USER'],
        'email':os.environ['WB_ADMIN_EMAIL'],'password':match[0]}}
    with q.open('w') as f:
        yaml.safe_dump(data, f, sort_keys=False)
PYBOOT
  then fail 'Authelia bootstrap failed. Output withheld.'; fi
  dc up -d --wait authelia
  touch .workbench-initialized
}
step5() {
  # Avoid export-before-add on a fresh store. Reuse a persisted UUID on retries.
  need_stack
  test -f .workbench-initialized || fail 'Run step4 first'
  local src
  src=$(cat "$SCRATCH/template-path")
  export TEMPLATE_SCRIPTS="$src/skills/soliplex-template/scripts"
  if ! py >/dev/null 2>&1 <<'PY'
import os, sys, uuid, subprocess
from pathlib import Path
import yaml
sys.path.insert(0, os.environ['TEMPLATE_SCRIPTS'])
import authelia_users as users
p = Path(os.environ['TARGET'])
q = p/'authelia'/f"workbench-{os.environ['WB_ADMIN_USER']}-sub"
if not q.exists():
    q.write_text(str(uuid.uuid4()))
sub = q.read_text().strip()
uuid.UUID(sub)
base = ['docker','compose','exec','-T','authelia','authelia','-c',
        '/config/configuration.yml','storage','user','identifiers']
# A duplicate on a retry is accepted only after export proves its identity.
added = subprocess.run(base+['add',os.environ['WB_ADMIN_USER'],'--identifier',sub], cwd=p,
                       capture_output=True, text=True)
export_name = 'identifiers-'+uuid.uuid4().hex+'.yml'
subprocess.run(base+['export','--file','/config/'+export_name], cwd=p,
               check=True, capture_output=True, text=True)
export_path = p/'authelia'/export_name
text = export_path.read_text()
entries = yaml.safe_load(text).get('identifiers', [])
assert any(x.get('username') == os.environ['WB_ADMIN_USER'] and x.get('identifier') == sub for x in entries), 'Identifier mismatch'
with (p/'authelia/identifiers.yml').open('w') as f:
    f.write(text)
export_path.unlink()
q = p/'authelia/users.yml'
data = yaml.safe_load(q.read_text()) or {}
data.setdefault('users', {})[os.environ['WB_ADMIN_USER']] = {
    'displayname': os.environ['WB_ADMIN_USER'], 'email': os.environ['WB_ADMIN_EMAIL'],
    'password': users._generate_hash(p, os.environ['WB_ADMIN_PASSWORD']), 'groups': ['admins']}
# In-place write preserves the inode of any single-file bind mount.
with q.open('w') as f:
    yaml.safe_dump(data, f, sort_keys=False)
q.chmod(0o600)
users._add_admin(p, sub)
PY
  then fail 'User setup failed. Output withheld. Review identifier state locally before retrying.'; fi
  # Force the file backend to reload without relying on watcher timing.
  dc restart authelia
  printf 'Authelia user and Soliplex admin configured\n'
}
step6() {
  # Copy the app AND local dependency. Pub/build writes stay in scratch.
  need_stack
  mkdir -p "$SCRATCH/frontend" "$SCRATCH/deps/dart_monty2"
  rsync -a --delete --delete-excluded --exclude .git --exclude build --exclude .dart_tool --exclude ephemeral --exclude .symlinks --exclude Pods \
    "$FRONTEND/" "$SCRATCH/frontend/"
  rsync -a --delete --exclude .git --exclude build --exclude .dart_tool \
    "$DEV_ROOT/dart_monty2/" "$SCRATCH/deps/dart_monty2/"
  guard
  py <<'PY'
import os
from pathlib import Path
import yaml
p = Path(os.environ['SCRATCH'])
q = p/'frontend/packages/soliplex_monty/pubspec.yaml'
data = yaml.safe_load(q.read_text())
data['dependencies']['dart_monty']['path'] = str(p/'deps/dart_monty2/packages/dart_monty')
with q.open('w') as f:
    yaml.safe_dump(data, f, sort_keys=False)
q = p/'frontend/packages/soliplex_monty/example/pubspec.yaml'
data = yaml.safe_load(q.read_text())
for section in ('dependencies', 'dev_dependencies'):
    if 'dart_monty' in (data.get(section) or {}):
        data[section]['dart_monty']['path'] = str(p/'deps/dart_monty2/packages/dart_monty')
with q.open('w') as f:
    yaml.safe_dump(data, f, sort_keys=False)
# dart2js wraps a shift by 32 to zero, and Random.nextInt(0) throws on the web.
shifts = [str(f) for f in (p/'frontend').rglob('*.dart')
          if '/build/' not in str(f) and '<< 32' in f.read_text(errors='ignore')]
assert not shifts, f'Shift by 32 breaks dart2js: {shifts}'
assert '_anotherTextFieldHasFocus' in (p/'frontend/lib/src/modules/room/ui/room_screen.dart').read_text()
# DCM reads options from package config files, not an --options CLI flag.
options = (p/'frontend/packages/soliplex_agent/dcm_options.yaml').read_text()
for rel in ('frontend/dcm_options.yaml',
            'frontend/packages/soliplex_monty/dcm_options.yaml',
            'frontend/packages/soliplex_monty/example/dcm_options.yaml'):
    with (p/rel).open('w') as f:
        f.write(options)

PY
  (
    cd "$SCRATCH/frontend"
    # Resolve every package before analysis. Gates on the copied lab code are
    # reported, not blocking: the deploy is a copy of exp-dojo-a2ui as-is.
    flutter pub get
    (cd packages/soliplex_monty && flutter pub get)
    (cd packages/soliplex_monty/example && flutter pub get)
    gates="$SCRATCH/gates.txt"
    : > "$gates"
    gate() { if "$@" > "$SCRATCH/gate.log" 2>&1; then r=0; else r=$?; fi; printf '%s exit=%s %s\n' "$*" "$r" "$(tail -1 "$SCRATCH/gate.log")" >> "$gates"; }
    gate flutter analyze
    gate dcm analyze packages/soliplex_monty
    gate dcm calculate-metrics packages/soliplex_monty
    (cd packages/soliplex_monty && gate flutter test && gate flutter test --platform chrome)
    cat "$gates"
    if grep -q -v ' exit=0 ' "$gates" && test "${WORKBENCH_ALLOW_GATE_FAILURES:-0}" != 1; then
      fail 'Gate failure. Fix it, or set WORKBENCH_ALLOW_GATE_FAILURES=1 to deploy anyway.'
    fi
    cd packages/soliplex_monty/example
    flutter build web --target lib/main.dart --release --no-tree-shake-icons --no-web-resources-cdn \
      --dart-define=WORKBENCH_ROOMS=workbench,workbench-e4b
  )
  test -s "$SCRATCH/frontend/packages/soliplex_monty/example/build/web/assets/packages/dart_monty/lib/assets/dart_monty_worker.wasm"
  mkdir -p "$TARGET/frontend-web"
  rsync -a --delete "$SCRATCH/frontend/packages/soliplex_monty/example/build/web/" "$TARGET/frontend-web/"
  # Own this one-purpose override. Refuse to clobber an unrelated override.
  py <<'PY'
import os
from pathlib import Path
p = Path(os.environ['TARGET'])/'docker-compose.override.yml'
text = '''# workbench-managed frontend mount
services:
  nginx:
    volumes:
      - type: bind
        source: ./frontend-web
        target: /app/build/web
        read_only: true
'''
assert not p.exists() or p.read_text().startswith('# workbench-managed'), 'Unmanaged override'
with p.open('w') as f:
    f.write(text)
PY
  check_compose
  dc up -d --wait
  # The workbench_data volume is created root-owned. The backend runs as soliplex.
  dc exec -T -u root backend mkdir -p /data/workbench/workdirs
  dc exec -T -u root backend chown soliplex:soliplex /data/workbench /data/workbench/workdirs
  for room in a2ui-lab a2ui-lab-e4b workbench workbench-e4b; do
    dc run --rm -T --quiet-build soliplex-dev /app/.venv/bin/soliplex-cli \
      room-authz from-yaml /environment "$room" < "$TARGET/backend/environment/rooms/$room/authz.yaml"
  done
  dc restart backend nginx
  dc exec -T nginx nginx -t
}
step7() {
  # Live model probes and transport checks. Browser acceptance remains manual.
  need_stack
  check_compose
  dc ps
  python3 - <<'PY'
import json, os, urllib.request

def post(url, body):
    req = urllib.request.Request(url, json.dumps(body).encode(), {'Content-Type':'application/json'})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)
post(f"http://{os.environ['MODEL_HOST']}:11450/v1/chat/completions", {
    'model':'Inferact/Muse-Glimmer-30B-NVFP4-W4A4', 'messages':[{'role':'user','content':'Reply OK'}],
    'max_tokens':4096, 'chat_template_kwargs':{'reasoning_strength':'medium'}})
x = post(f"http://{os.environ['MODEL_HOST']}:11438/v1/embeddings", {
    'model':'nvidia/llama-nemotron-embed-vl-1b-v2','input':'dimension probe'})
assert len(x['data'][0]['embedding']) == 2048
post(f"http://{os.environ['MODEL_HOST']}:11434/rerank", {
    'model':'nvidia/llama-nemotron-rerank-vl-1b-v2','query':'hello','documents':['hello']})
# Soliplex streams, and Ollama treats streamed requests differently. Probe streamed.
req = urllib.request.Request(f"http://{os.environ['OLLAMA_HOST']}:11434/v1/chat/completions", json.dumps({
    'model':'gemma4:e4b','stream':True,'messages':[{'role':'user','content':'Reply OK'}],
    'max_tokens':4096,'think':False,'reasoning_effort':'none'}).encode(), {'Content-Type':'application/json'})
reasoning = content = 0
with urllib.request.urlopen(req, timeout=300) as r:
    for line in r:
        line = line.decode().strip()
        if not line.startswith('data:') or '[DONE]' in line:
            continue
        d = json.loads(line[5:])['choices'][0]['delta']
        reasoning += len(d.get('reasoning') or d.get('reasoning_content') or '')
        content += len(d.get('content') or '')
assert reasoning == 0, 'BLOCKER: E4B thinking is not off'
assert content, 'E4B did not answer'
print('Host model probes passed. Container reachability still needs room checks.')
PY
  local base=https://soliplex-a2ui-workbench.localhost:9743
  for path in / /version.json /api/ok /api/login /authelia/api/health /authelia/.well-known/openid-configuration /assets/packages/dart_monty/lib/assets/dart_monty_worker.js; do
    curl --fail --silent --show-error --insecure --output /dev/null "$base$path"
    printf 'HTTP success %s\n' "$path"
  done
  curl --fail --silent --show-error --insecure -H 'Accept-Encoding: gzip' -D - \
    --output /dev/null "$base/assets/packages/dart_monty/lib/assets/dart_monty_worker.wasm"
  test "$(curl --silent --show-error --insecure --output /dev/null --write-out '%{http_code}' "$base/api/v1/rooms")" = 401
  printf 'Browser acceptance and screenshots remain TODO (host). See STACK.md\n'
}
help() {
  printf '%s\n' 'Host review required. Run steps in order:' \
    'step1 template update or clone and generation' 'step2 initial secret rotation' \
    'step3 model, room, Docker and auth configuration' 'step4 image build and initialization' \
    'step5 configured user and admin' 'step6 copy, validate, build and deploy frontend' \
    'step7 probes and HTTP verification' 'all runs step1 through step7'
}
guard
case "${1:-help}" in
  step1|step2|step3|step4|step5|step6|step7) "$1" ;;
  all) step1; step2; step3; step4; step5; step6; step7 ;;
  help|--help|-h) help ;;
  *) fail 'Unknown step. Use help.' ;;
esac

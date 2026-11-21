import { spawn } from 'node:child_process';
import { mkdir, readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cleanEvidence, cleanupCreatedThreads, failedAssertions, loadCases, parseCredentials, redactor, writeReport } from './lib/core.mjs';

import { parseScenarioArgs } from './lib/options.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const repository = resolve(root, '../..');
const base = 'https://soliplex-a2ui-workbench.localhost:9743';
const alias = process.env.WB_SERVER_ALIAS || 'soliplex-a2ui-workbench-localhost-9743';
const stack = process.env.WB_STACK_DIR || resolve(homedir(), 'dev/soliplex-a2ui-workbench');

async function backendScript(source, config) {
  // Configuration travels over stdin. No credentials in process arguments,
  // temporary files, Docker env flags, or child stdout/stderr forwarded to logs.
  const bootstrap = 'import json,sys\nSCENARIO_CONFIG=json.loads(sys.stdin.readline())\nexec(compile(sys.stdin.read(), "scenario-seed", "exec"))';
  const child = spawn('docker', [
    'compose', '--project-name', 'soliplex-a2ui-workbench', '--project-directory', stack,
    'exec', '-T', 'backend', '/app/.venv/bin/python', '-B', '-c', bootstrap,
  ], { cwd: stack, stdio: ['pipe', 'pipe', 'pipe'] });
  let output = '';
  const done = new Promise(resolveChild => {
    const timer = setTimeout(() => { child.kill('SIGKILL'); resolveChild(false); }, 120000);
    const finish = success => { clearTimeout(timer); resolveChild(success); };
    child.on('error', () => finish(false));
    child.on('close', () => finish(true));
    child.stdout.on('data', chunk => {
      output += chunk;
      if (output.length > 65536) { child.kill('SIGKILL'); finish(false); }
    });
    child.stderr.on('data', () => {});
    child.stdin.on('error', () => {});
  });
  child.stdin.end(`${JSON.stringify(config)}\n${source}`);
  if (!await done) throw new Error('Backend harness operation failed');
  return JSON.parse(output);
}

async function seed(credentials, recordThread) {
  const source = await readFile(`${root}/deterministic/seed.py`, 'utf8');
  const seeds = await backendScript(source, { user: credentials.WB_ADMIN_USER, email: credentials.WB_ADMIN_EMAIL, room: 'workbench' });
  if (!Array.isArray(seeds)) throw new Error('Invalid seed response');
  for (const item of seeds) {
    const id = item.cleanup_thread_id || item.thread_id;
    if (id) recordThread('workbench', id);
  }
  return seeds;
}

async function main() {
  const selected = parseScenarioArgs(process.argv.slice(2));
  if (!selected) {
    console.log('Usage: workbench/scenarios/run.sh --deterministic | --models | --all | --probes');
    return;
  }
  // WB_CASES=id1,id2 runs only those cases.
  const only = new Set((process.env.WB_CASES || '').split(',').map(id => id.trim()).filter(Boolean));
  const pick = cases => (only.size ? cases.filter(item => only.has(item.id)) : cases);
  if (selected.probes) {
    const { runProbes } = await import('./probes/run_probes.mjs');
    return runProbes({ repository, base, alias });
  }
  const deterministic = pick(await loadCases(`${root}/deterministic/cases.json`));
  const prompts = pick(await loadCases(`${root}/model/prompts.yaml`, { prompts: true }));
  const timestamp = new Date().toISOString();
  const stamp = timestamp.replace('T', '-').replace(/:/g, '').replace('.', '-');
  const directory = `${repository}/workbench/docs/evidence/scenarios/${stamp}`;
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const results = [];
  let redact = redactor();
  let browser;
  let credentials;
  const createdThreads = new Map();
  const recordThread = (room, threadId) => {
    if (!['workbench', 'workbench-e4b'].includes(room) || !/^[0-9a-f-]{36}$/.test(threadId)) throw new Error('Invalid recorded thread');
    createdThreads.set(`${room}/${threadId}`, { room, thread_id: threadId });
  };
  let setupStage = 'Read literal credentials from workbench.env';
  const record = async result => {
    // Sanitize before persistence and before printing even a case label.
    const clean = cleanEvidence(result, redact);
    results.push(clean);
    await writeReport(directory, results, timestamp, redact);
    console.log(redact(`${clean.model} ${clean.id}: ${clean.pass ? 'PASS' : 'FAIL'}`));
  };
  try {
    credentials = parseCredentials(await readFile(`${repository}/workbench/stack/workbench.env`, 'utf8'));
    redact = redactor(Object.values(credentials));
    setupStage = 'Seed deterministic threads in the backend container';
    const seeds = selected.deterministic ? await seed(credentials, recordThread) : [];
    setupStage = 'Import Playwright, launch Chrome, and sign in';
    const { openBrowser } = await import('./lib/browser.mjs');
    const opened = await openBrowser(base, credentials);
    browser = opened.browser;
    const common = { page: opened.page, base, alias, directory, credentials, record, recordThread };
    setupStage = 'Run selected browser suites';
    if (selected.deterministic) {
      const { checkDeterministic } = await import('./deterministic/check.mjs');
      await checkDeterministic({ ...common, seeds, cases: deterministic });
    }
    if (selected.models) {
      const { checkModels } = await import('./model/run.mjs');
      const timeoutMs = Number(process.env.WB_RUN_TIMEOUT_MS || 240000);
      if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) throw new Error('Invalid run timeout');
      await checkModels({ ...common, timeoutMs, cases: prompts });
    }
  } catch (error) {
    if (String(error?.message).startsWith('Sign-in ')) process.stderr.write(`${error.message}\n`);
    // Keep infrastructure failures reviewable without echoing a library
    // exception containing DOM snapshots, authentication URLs, or DB settings.
    const pending = [
      ...(selected.deterministic ? deterministic.map(item => ({ id: item.id, model: 'No model', assertions: item.assertions })) : []),
      ...(selected.models ? ['Glimmer', 'Gemma 4 E4B'].flatMap(model => prompts.map(item => ({ id: item.id, model, assertions: item.assertions }))) : []),
    ];
    for (const item of pending) {
      if (!results.some(r => r.id === item.id && r.model === item.model)) {
        await record({ ...item, pass: false, assertions: failedAssertions(item.assertions, 'Not evaluated because harness setup failed'), error: `Harness setup failed during: ${setupStage}` });
      }
    }
  } finally {
    await browser?.close().catch(() => { process.exitCode = 1; });
    if (credentials && createdThreads.size) {
      try {
        const source = await readFile(`${root}/deterministic/cleanup.py`, 'utf8');
        await cleanupCreatedThreads([...createdThreads.values()], async threads => {
          const result = await backendScript(source, { user: credentials.WB_ADMIN_USER, threads });
          if (result.failed) throw new Error('Thread cleanup incomplete');
        });
      } catch {
        console.error('Could not delete all recorded scenario threads');
        process.exitCode = 1;
      }
    }
    await writeReport(directory, results, timestamp, redact);
  }
  console.log(`Report: ${directory}/report.md`);
  if (!results.length || results.some(result => !result.pass)) process.exitCode = 1;
}

main().catch(() => {
  console.error('Scenario harness failed before it could complete its report');
  process.exitCode = 1;
});

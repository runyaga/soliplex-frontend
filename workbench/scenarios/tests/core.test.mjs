import { workspaceMatches } from '../lib/selectors.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdir, readlink } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { cleanEvidence, cleanupCreatedThreads, failedAssertions, regionSelector, loadCases, parseCredentials, parseSSE, redactor, renderReport, summarizeEvents, validateCases, writeReport, isProgramOutputError } from '../lib/core.mjs';
import { hasVisibleInk } from '../lib/png.mjs';

const root = new URL('../', import.meta.url);
const valid = () => [{ id: 'intake', prompt: 'Make a form', assertions: [{ kind: 'role', role: 'textbox', name: 'Question', region: 'left' }] }];

const AT = '@';

test('repair examples explicitly enable checking and can run again after repair', async () => {
  const prompts = await loadCases(new URL('model/prompts.yaml', root), { prompts: true });
  const nameError = prompts.find(p => p.id === 'name_error_ai_fix');
  const runs = nameError.actions.filter(a => a.kind === 'run_program');
  assert.equal(runs.length, 2);
  assert.equal(runs[0].expectRepair, true);
  assert.equal(runs[1].expectRepair, false);
  assert.ok(runs.every(a => a.expectedOutput === '766228'));
  const typeCheck = prompts.find(p => p.id === 'type_check_ai_fix');
  assert.ok(typeCheck.actions.some(a => a.kind === 'check' && a.name === 'Type check'));
  for (const item of [nameError, typeCheck]) {
    assert.ok(item.actions.some(a => a.kind === 'check' && a.name === 'AI Fix'));
    assert.ok(item.actions.find(a => a.kind === 'run_program').assertions.some(a => a.name === 'Run 2'));
    assert.ok(item.assertions.some(a => a.name === 'ok'));
  }
});

test('prompt corpus has twenty-two independent cases and checked follow-up prerequisites', async () => {
  const prompts = await loadCases(new URL('model/prompts.yaml', root), { prompts: true });
  assert.equal(prompts.length, 22);
  assert.ok(prompts.find(p => p.id === 'fix_program').setup.length);
  for (const prompt of prompts.filter(p => p.setup)) assert.ok(prompt.setup_assertions.length);
  assert.ok(prompts.some(p => p.actions?.some(a => a.name === 'Run')));
  const deterministic = await loadCases(new URL('deterministic/cases.json', root));
  assert.equal(deterministic.length, 10);
  assert.equal(deterministic.find(c => c.id === 'reload_replay').reload, true);
});

test('schema rejects missing, ambiguous, and malformed expectations', () => {
  assert.doesNotThrow(() => validateCases(valid(), { prompts: true }));
  for (const mutate of [
    data => data.push(data[0]),
    data => { delete data[0].id; },
    data => { data[0].prompt = ''; },
    data => { data[0].assertions = []; },
    data => { data[0].assertions[0].absent = true; },
    data => { data[0].reload = 'yes'; },
    data => { data[0].assertions[0].region = 'timeline'; },
    data => { data[0].assertions[0].role = 'invented'; },
    data => { data[0].assertions[0].count = 0; },
    data => { data[0].assertions[0].count = 1; data[0].assertions[0].absent = true; },
    data => { data[0].setup = ['']; },
    data => { data[0].setup_assertions = []; },
    data => { data[0].actions = [{ role: 'textbox', name: 'Run' }]; },
    data => { data[0].assertions[0] = { kind: 'source', name: 'Python source' }; },
  ]) {
    const data = valid();
    mutate(data);
    assert.throws(() => validateCases(data, { prompts: true }));
  }
});

test('literal env parsing preserves shell characters without shell evaluation', () => {
  const parsed = parseCredentials('WB_ADMIN_USER="fixture-user"\nWB_ADMIN_EMAIL=fixture' + AT + 'example.invalid\nWB_ADMIN_PASSWORD=\'literal $() `cmd` ! # value\'\nUNRELATED=$HOME');
  assert.equal(parsed.WB_ADMIN_PASSWORD, 'literal $() `cmd` ! # value');
  assert.equal(Object.keys(parsed).length, 3);
  assert.throws(() => parseCredentials('WB_ADMIN_PASSWORD="$(command)"'));
  assert.throws(() => parseCredentials('WB_ADMIN_USER=x'));
});

test('credential redaction happens before JSON escaping or markdown transformation', () => {
  const fixture = 'fixture"\\|secret,with punctuation';
  const redact = redactor([fixture, `fixture${AT}example.invalid`]);
  const result = cleanEvidence({ finalMessage: `Value: ${fixture}`, turns: [{ runErrors: ['Bearer abc123', 'token=arbitrary'], submissions: [{ context: { question: fixture } }] }] }, redact);
  assert.equal(result.finalMessage, 'Value: [redacted]');
  assert.equal(result.turns[0].submissions[0].context.question, '[redacted]');
  assert.ok(!JSON.stringify(result).includes('abc123'));
  assert.ok(!JSON.stringify(result).includes('arbitrary'));
  assert.equal(redact(encodeURIComponent(fixture)), '[redacted]');
});

test('SSE decoder handles comments, CRLF, multiline JSON and lifecycle failure', () => {
  const body = ': heartbeat\r\n\r\nid: 1\r\ndata: {"type":\r\ndata: "RUN_ERROR", "message": "bad tool"}\r\n\r\ndata: [DONE]\r\n\r\n';
  assert.deepEqual(parseSSE(body), [{ type: 'RUN_ERROR', message: 'bad tool' }]);
  assert.throws(() => parseSSE('data: not json\n\n'));
  const summary = summarizeEvents([
    { type: 'TEXT_MESSAGE_START', messageId: 'a', role: 'assistant' },
    { type: 'TEXT_MESSAGE_CONTENT', messageId: 'a', delta: 'First' },
    { type: 'TOOL_CALL_START', toolCallName: 'place_form' },
    { type: 'TEXT_MESSAGE_START', messageId: 'b', role: 'assistant' },
    { type: 'TEXT_MESSAGE_CONTENT', messageId: 'b', delta: 'Final ' },
    { type: 'TEXT_MESSAGE_CONTENT', messageId: 'b', delta: 'answer' },
    { type: 'RUN_ERROR', message: 'bad tool' },
    { type: 'RUN_FINISHED' },
  ]);
  assert.equal(summary.finalMessage, 'Final answer');
  assert.deepEqual(summary.toolCalls, ['place_form']);
  assert.deepEqual(summary.runErrors, ['bad tool']);
  assert.equal(summary.completed, true);
});

test('assertions scope to semantic regions independently of composer geometry', () => {
  assert.equal(regionSelector('canvas'), '[aria-label="Workbench region canvas"]');
  assert.equal(regionSelector('left'), '[aria-label="Workbench region left"]');
  assert.equal(regionSelector('chat'), '[aria-label="Workbench region chat"]');
  const workspace = regionSelector();
  for (const role of ['left', 'right', 'canvas', 'tray']) assert.ok(workspace.includes(`Workbench region ${role}`));
  assert.ok(!workspace.includes('chat'));
  assert.throws(() => regionSelector('invented'));
});

test('pixel check rejects blank paint and decodes all five PNG scanline filters', () => {
  const blank = 'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAEklEQVR4nGP4TwRgGFU0GBUBAED3rmB80DyYAAAAAElFTkSuQmCC';
  const painted = [
    'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAGklEQVR4nGP4TwRgoIEiBgwwnBQRFQSUKgIA8R1CzMPP/ZQAAAAASUVORK5CYII=',
    'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAIElEQVR4nGP8//8/AyHASANFjIyMaHIIqaGvCA+gniIAWIw16b/eP/oAAAAASUVORK5CYII=',
    'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAH0lEQVR4nGP6TwRgYiACkKiIEQOQa9JgVIQZhjSwDgBG7DX1gTPraAAAAABJRU5ErkJggg==',
    'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAALklEQVR4nGP+//9/AyHADMQMhACJihgZGRtRAVwKoQgoimbAEFGEGYZw1dQLTAD/EkVDfbykwAAAAABJRU5ErkJggg==',
    'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAJklEQVR4nGP5//8/AyHAQlAF6YoYGRnR5OAuoYV1dFaEJ1SpZx0AE0YJK4H4mr8AAAAASUVORK5CYII=',
  ];
  assert.equal(hasVisibleInk(Buffer.from(blank, 'base64')), false);
  for (const png of painted) assert.equal(hasVisibleInk(Buffer.from(png, 'base64')), true);
  assert.throws(() => hasVisibleInk(Buffer.from('not PNG')));
});

test('report preserves failing evidence, escapes tables, and applies prose rules', () => {
  const skipped = failedAssertions(valid()[0].assertions, 'Setup failed');
  assert.equal(skipped.length, 1);
  assert.equal(skipped[0].pass, false);
  assert.match(skipped[0].label, /textbox Question in left/);
  const report = renderReport([
    { id: 'form', model: 'No model', pass: true, screenshot: 'form.png', assertions: [{ label: 'Question', pass: true }] },
    { id: 'counter', model: 'Glimmer', pass: false, finalMessage: 'a|b\ntext — fixture-secret; done', runErrors: ['Run failed'], timelineTools: ['run_python_client'], assertions: [{ label: 'Run', pass: false, detail: '0 matches' }] },
  ], '2026-11-19T00:00:00Z', redactor(['fixture-secret']));
  assert.match(report, /\| form \| No model \| PASS/);
  assert.match(report, /\| counter \| Glimmer \| FAIL/);
  assert.match(report, /\[Screenshot\]\(form.png\)/);
  assert.match(report, /a\\\|b/);
  assert.match(report, /Run failed/);
  assert.match(report, /run_python_client/);
  assert.ok(!report.includes('fixture-secret'));
  assert.ok(!report.includes('—'));
  assert.ok(!report.includes(';'));
});

test('dated report serialization creates parseable, redacted evidence', async () => {
  // Artifacts stay under this worktree, including offline report fixtures.
  const directory = fileURLToPath(new URL('tests/.output/', root));
  await mkdir(directory, { recursive: true });
  await writeReport(directory, [{ id: 'fixture', model: 'No model', pass: false, finalMessage: 'fixture-secret', runErrors: ['Error | detail\nhttps://example.invalid/evidence'], assertions: [{ label: 'Question', pass: false, detail: '0 visible matches' }] }], '2026-11-19T00:00:00Z', redactor(['fixture-secret']));
  const json = JSON.parse(await readFile(`${directory}/results.json`, 'utf8'));
  assert.equal(json[0].finalMessage, '[redacted]');
  assert.equal(json[0].pass, false);
  assert.match(await readFile(`${directory}/report.md`, 'utf8'), /\| fixture \| No model \| FAIL/);
});

test('Playwright symlink reuses the existing probe dependency when present', async () => {
  try {
    assert.equal(await readlink(new URL('node_modules', root)), process.env.WB_NODE_MODULES || `${process.env.HOME}/dev/soliplex-embed-probe/node_modules`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
});

test('cleanup deletes only recorded ids by default and honors the keep flag', async () => {
  const created = [{ room: 'workbench', thread_id: 'first' }, { room: 'workbench-e4b', thread_id: 'second' }];
  const deleted = [];
  await cleanupCreatedThreads(created, async threads => deleted.push(...threads), false);
  assert.deepEqual(deleted, created);
  await cleanupCreatedThreads(created, async () => { throw new Error('keep must skip deletion'); }, true);
  await assert.rejects(cleanupCreatedThreads(created, async () => { throw new Error('cleanup failure'); }, false));
});

test('canvas matches use container ancestry even when composer geometry overlaps', async () => {
  const target = (name, x) => ({ name, boundingBox: async () => ({ x, y: 100, width: 100, height: 30 }), isVisible: async () => true });
  const canvas = target('Run', 800);
  const chat = target('Run', 100);
  const left = target('Submit', 20);
  const byContainer = { canvas: [canvas], chat: [chat], left: [left], right: [], tray: [] };
  const page = {
    // Calling unscoped composer or text lookups is an error in this fixture.
    getByRole() { throw new Error('Unscoped geometry lookup'); },
    locator(selector) {
      const targets = Object.entries(byContainer).flatMap(([role, nodes]) => selector.includes(`Workbench region ${role}`) ? nodes : []);
      return { getByRole(_role, { name }) {
        const matches = targets.filter(item => name.test(item.name));
        return { count: async () => matches.length, nth: index => matches[index] };
      } };
    },
  };
  const assertion = { kind: 'role', role: 'button', name: 'Run', region: 'canvas' };
  assert.deepEqual((await workspaceMatches(page, assertion)).map(item => item.target), [canvas]);
  assert.deepEqual((await workspaceMatches(page, { ...assertion, region: 'workspace' })).map(item => item.target), [canvas]);
  assert.deepEqual((await workspaceMatches(page, { ...assertion, name: 'Submit', region: 'left' })).map(item => item.target), [left]);
});

test('window scope distinguishes identical controls in neighbouring windows', async () => {
  const target = { boundingBox: async () => ({ x: 1, y: 1, width: 80, height: 30 }), isVisible: async () => true };
  const page = { locator(selector) {
    assert.equal(selector, '[aria-label="Workbench region canvas"] [aria-label="Workbench window Monty GUI demo"]');
    return { getByRole(role, { name }) {
      assert.equal(role, 'button');
      assert.ok(name.test('Run'));
      return { count: async () => 1, nth: () => target };
    } };
  } };
  assert.equal((await workspaceMatches(page, { kind: 'role', role: 'button', name: 'Run', region: 'canvas', window: 'Monty GUI demo' })).length, 1);
  for (const window of ['', 42, 'x'.repeat(81)]) {
    const data = valid(); data[0].assertions[0].window = window;
    assert.throws(() => validateCases(data, { prompts: true }));
    delete data[0].assertions[0].window;
    data[0].actions = [{ role: 'button', name: 'Run', window }];
    assert.throws(() => validateCases(data, { prompts: true }));
  }
});

test('chart scenarios require image semantics with title and series', async () => {
  const deterministic = await loadCases(new URL('../deterministic/cases.json', import.meta.url));
  const model = await loadCases(new URL('../model/prompts.yaml', import.meta.url), { prompts: true });
  for (const item of [...deterministic, ...model]) {
    if (!['chart_on_canvas', 'move_panel', 'bar_chart', 'move_chart_right'].includes(item.id)) continue;
    for (const assertion of [...item.assertions, ...(item.setup_assertions ?? [])]) {
      assert.equal(assertion.kind, 'role');
      assert.equal(assertion.role, 'img');
      assert.match(assertion.name, /bar chart: Scenario regions; North: 80, South: 76/);
    }
  }

});

test('initial viewport checks reject clipped, offscreen and scrolled controls without scrolling', async () => {
  let scrolls = 0;
  let rect = { left: 110, top: 110, right: 190, bottom: 140 };
  const parent = {
    parentElement: null, scrollTop: 0, scrollLeft: 0,
    getBoundingClientRect: () => ({ left: 100, top: 100, right: 300, bottom: 300 }),
  };
  const element = { parentElement: parent, getBoundingClientRect: () => rect };
  const target = {
    scrollIntoViewIfNeeded: async () => { scrolls++; },
    boundingBox: async () => ({ x: rect.left, y: rect.top, width: rect.right - rect.left, height: rect.bottom - rect.top }),
    isVisible: async () => true,
    evaluate: async callback => callback(element),
  };
  const page = { locator: () => ({ getByRole: () => ({ count: async () => 1, nth: () => target }) }) };
  const a = { kind: 'role', role: 'button', name: '+1', region: 'canvas', window: 'Counter app', initialViewport: true };
  const old = { width: globalThis.innerWidth, height: globalThis.innerHeight, style: globalThis.getComputedStyle };
  globalThis.innerWidth = 1000;
  globalThis.innerHeight = 800;
  globalThis.getComputedStyle = () => ({ overflowX: 'hidden', overflowY: 'auto' });
  try {
    assert.equal((await workspaceMatches(page, a)).length, 1);
    rect = { ...rect, top: 290, bottom: 320 };
    assert.equal((await workspaceMatches(page, a)).length, 0);
    rect = { left: 110, top: 110, right: 190, bottom: 140 };
    parent.scrollTop = 10;
    assert.equal((await workspaceMatches(page, a)).length, 0);
    parent.scrollTop = 0;
    rect = { ...rect, right: 1100 };
    assert.equal((await workspaceMatches(page, a)).length, 0);
    assert.equal(scrolls, 0);
    await workspaceMatches(page, { ...a, initialViewport: false });
    assert.equal(scrolls, 1);
    const data = valid(); data[0].assertions[0].initialViewport = 'yes';
    assert.throws(() => validateCases(data, { prompts: true }));
  } finally {
    globalThis.innerWidth = old.width;
    globalThis.innerHeight = old.height;
    globalThis.getComputedStyle = old.style;
  }
});

test('counter and demo corpus scope live controls to the app at its initial viewport', async () => {
  const model = await loadCases(new URL('../model/prompts.yaml', import.meta.url), { prompts: true });
  const tally = model.find(c => c.id === 'tally_counter');
  for (const a of tally.assertions.filter(a => ['+1', '-1', 'Reset'].includes(a.name))) {
    assert.equal(a.window, 'Scenario program window app');
    assert.equal(a.initialViewport, true);
  }
  const demo = model.find(c => c.id === 'monty_demo');
  for (const a of demo.actions[0].assertions.filter(a => a.window)) {
    assert.equal(a.window, 'Monty GUI demo app');
    assert.equal(a.initialViewport, true);
  }
  assert.equal(demo.actions[0].window, 'Monty GUI demo');
  assert.equal(demo.assertions.find(a => a.name === 'Python source').window, 'Monty GUI demo');
});

test('program tracebacks inside a workbench window are output, app errors are not', () => {
  const traceback = 'Traceback (most recent call last):\nValueError: scenario deliberate failure';
  assert.equal(isProgramOutputError(traceback, true), true);
  assert.equal(isProgramOutputError(traceback, false), false);
  assert.equal(isProgramOutputError('Run failed: workbenchAction is server-owned', true), false);
  assert.equal(isProgramOutputError('Workbench is unavailable', true), false);
});

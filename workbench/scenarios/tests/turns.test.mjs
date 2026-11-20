import test from 'node:test';
import assert from 'node:assert/strict';
import { csvCell, parseCsv } from '../lib/csv.mjs';
import { performActions } from '../lib/actions.mjs';
import { captureProgramTurns, captureTurn } from '../lib/turns.mjs';
import { assertTurn, intakeSubmissions, loadCases, replyExpectation, validateCases } from '../lib/core.mjs';

const noWait = async () => {};
const options = { room: 'workbench', threadId: 'thread-id', timeoutMs: 1000 };
const url = 'https://example.invalid/api/v1/rooms/workbench/agui/thread-id/run-id';
const context = { question: 'Scenario zebra question', districts: ['north'], acknowledged: true };
const storedInput = {
  forwardedProps: { workbenchFormReceipt: { filename: 'intake.csv' } },
  messages: [
    { role: 'assistant', toolCalls: [{ id: 'call-id', function: { name: 'workbench_intake' } }] },
    { role: 'tool', toolCallId: 'call-id', content: JSON.stringify({ kind: 'untrusted_user_submitted_data', actionSchemaVersion: 'intake.submit@1', context }) },
  ],
};

test('demo corpus checks Run, each counter click, window open and close in order', async () => {
  const model = await loadCases(new URL('../model/prompts.yaml', import.meta.url), { prompts: true });
  const deterministic = await loadCases(new URL('../deterministic/cases.json', import.meta.url));
  const demo = model.find(c => c.id === 'monty_demo');
  assert.equal(demo.prompt, 'Open the Monty GUI demo.');
  assert.deepEqual(demo.actions, deterministic.find(c => c.id === 'monty_demo').actions);
  assert.deepEqual(demo.actions.map(a => a.name), ['Run', 'Close log window', '+1', '+1', 'Open log window', 'Close log window']);
  assert.ok(demo.actions[0].assertions.some(a => a.role === 'button' && a.name === 'Bar Start: 0'));
  for (const count of [1, 2]) {
    assert.ok(demo.actions[count + 1].assertions.some(a => a.name === `Count: ${count}`));
    assert.ok(demo.actions[count + 1].assertions.some(a => a.name === `last event: plus, count ${count}`));
  }
  assert.ok(demo.actions[4].assertions.some(a => a.role === 'group' && a.name === 'Workbench window Monty event log' && !a.absent));
  assert.ok(demo.actions[5].assertions.some(a => a.role === 'group' && a.name === 'Workbench window Monty event log' && a.absent));
  assert.ok(demo.actions.filter(a => ['Run', 'Open log window', 'Close log window'].includes(a.name)).every(a => a.awaitTurn));
});

test('action assertions are inspected before the next click and stop on failure', async () => {
  const { page, operations } = fixture();
  const actions = [
    { role: 'button', name: 'North', region: 'left', assertions: [{ kind: 'text', name: 'Count: 1' }] },
    { role: 'button', name: 'South', region: 'left' },
  ];
  await performActions(page, actions, options, undefined, noWait, async assertions => {
    assert.deepEqual(operations, ['click:North']);
    assert.equal(assertions[0].name, 'Count: 1');
    operations.push('inspect');
    return [{ pass: true }];
  });
  assert.deepEqual(operations, ['click:North', 'inspect', 'click:South']);
  for (const inspector of [async () => [{ pass: false }], async () => [], undefined]) {
    operations.length = 0;
    await assert.rejects(performActions(page, actions, options, undefined, noWait, inspector), /assertions/);
    assert.deepEqual(operations, ['click:North']);
  }
});

test('action assertion schema rejects empty, turn-only and malformed checks', () => {
  const item = assertions => [{ id: 'demo', assertions: [{ kind: 'text', name: 'Demo' }], actions: [{ role: 'button', name: 'Run', assertions }] }];
  assert.doesNotThrow(() => validateCases(item([{ kind: 'text', name: 'Count: 0' }])));
  for (const assertions of [[], null, [{ kind: 'reply', includes: 'No inference' }], [{ kind: 'role', name: 'Chart', role: 'unknown' }]]) {
    assert.throws(() => validateCases(item(assertions)));
  }
});

function fixture({ events, actionName = 'submit_intake', httpOk = true, csvStatus = 200, missingFile = false } = {}) {
  const operations = [];
  const nodes = [
    ['textbox', 'Scenario intake Question Districts'],
    ['button', 'North'], ['button', 'South'], ['checkbox', 'Acknowledged'], ['button', 'Submit'],
  ].map(([role, name]) => ({
    role, name,
    isVisible: async () => true,
    boundingBox: async () => ({ x: 1, y: 1, width: 100, height: 30 }),
    checked: false,
    async click() {
      operations.push(`click:${name}`);
      if (role === 'checkbox') this.checked = !this.checked;
      if (name === 'Submit') await page.trigger();
    },
    async getAttribute(attribute) { return attribute === 'aria-checked' && role === 'checkbox' ? String(this.checked) : null; },
  }));
  let handler;
  const page = {
    keyboard: { press: async key => operations.push(`key:${key}`), type: async value => operations.push(`type:${value}`) },
    locator(selector) {
      assert.match(selector, /Workbench region left/);
      return { getByRole(role, { name }) {
        const matches = nodes.filter(n => n.role === role && name.test(n.name));
        return { count: async () => matches.length, nth: i => matches[i] };
      } };
    },
    route: async (_pattern, callback) => { handler = callback; operations.push('route'); },
    unroute: async (_pattern, callback) => { assert.equal(callback, handler); operations.push('unroute'); },
    request: { get: async (address, options) => {
      assert.equal(options.headers.authorization, 'Bearer fake-token', 'every public read carries the app bearer header');
      if (address === url) {
        operations.push('read-input');
        return { ok: () => true, json: async () => ({ run_input: storedInput }) };
      }
      const base = 'https://example.invalid/api/v1/workdirs/workbench/thread/thread-id';
      if (address === base) {
        operations.push('list-files');
        return { ok: () => true, json: async () => ({ files: missingFile ? [] : [{ filename: 'intake.csv', url: 'https://untrusted.invalid/avoid' }] }) };
      }
      assert.equal(address, base + '/file/intake.csv', 'download stays on the authenticated origin');
      operations.push('download-csv');
      return { ok: () => csvStatus === 200, status: () => csvStatus, text: async () => 'submitted_at,submission_id,question,districts,acknowledged\r\n2026-11-20T00:00:00+00:00,submit-id,Scenario zebra question,"[""north""]",true\r\n' };
    } },
    async trigger() {
      assert.ok(handler, 'capture is installed before clicking');
      const body = (events ?? [
        { type: 'RUN_STARTED' },
        { type: 'TEXT_MESSAGE_START', messageId: 'a', role: 'assistant' },
        { type: 'TEXT_MESSAGE_CONTENT', messageId: 'a', delta: 'Received zebra.' },
        { type: 'RUN_FINISHED' },
      ]).map(e => `data: ${JSON.stringify(e)}\n\n`).join('');
      await handler({
        request: () => ({ method: () => 'POST', url: () => url, allHeaders: async () => ({ authorization: 'Bearer fake-token' }), postDataJSON: () => ({ forwardedProps: { a2uiAction: { submissionId: 'submit-id', userAction: { name: actionName } } } }) }),
        fetch: async () => ({ text: async () => body, status: () => httpOk ? 200 : 422, ok: () => httpOk }),
        fulfill: async response => { assert.equal(response.body, body); operations.push('fulfill'); },
        abort: async () => operations.push('abort'),
      });
    },
  };
  return { page, operations, nodes };
}

test('fill uses whole-word merged textbox labels and Flutter key events', async () => {
  const { page, operations } = fixture();
  await performActions(page, [{ kind: 'fill', name: 'Question', value: context.question, region: 'left' }], undefined, undefined, noWait);
  assert.deepEqual(operations, ['click:Scenario intake Question Districts', 'key:ControlOrMeta+A', 'key:Backspace', 'type:Scenario zebra question', 'key:Tab']);
});

test('choose/select use visible option labels and check sets the named checkbox', async () => {
  const { page, operations, nodes } = fixture();
  await performActions(page, [
    { kind: 'choose', name: 'North', region: 'left' },
    { kind: 'check', name: 'Acknowledged', region: 'left' },
  ], undefined, undefined, noWait);
  assert.deepEqual(operations, ['click:North', 'click:Acknowledged']);
  // A checked box is not clicked again, so check never toggles it off.
  await performActions(page, [{ kind: 'check', name: 'Acknowledged', region: 'left' }], undefined, undefined, noWait);
  assert.equal(operations.length, 2);
  nodes.find(n => n.name === 'North').getAttribute = async name => name === 'aria-pressed' ? 'true' : null;
  await performActions(page, [{ kind: 'select', name: 'North', region: 'left' }], undefined, undefined, noWait);
  assert.equal(operations.length, 2, 'a selected chip is not toggled off');
});

test('awaitTurn captures the action stream and server-authored intake input before returning', async () => {
  const { page, operations } = fixture();
  const turns = [];
  await performActions(page, [{ role: 'button', name: 'Submit', region: 'left', awaitTurn: true }], options, turn => turns.push(turn), noWait);
  assert.deepEqual(operations, ['route', 'click:Submit', 'fulfill', 'read-input', 'list-files', 'download-csv', 'unroute']);
  assert.equal(turns.length, 1);
  assert.ok(!JSON.stringify(turns).includes('fake-token'), 'the bearer header stays out of the turn record');
  assert.equal(turns[0].completed, true);
  assert.equal(assertTurn({ kind: 'reply', includes: 'zebra' }, turns[0]).pass, true);
  assert.equal(assertTurn({ kind: 'submission', name: 'workbench_intake', context }, turns[0]).pass, true);
  assert.equal('input' in turns[0], false, 'raw run input must not reach evidence');
});

test('reply assertions require the latest successful captured turn, never earlier text', () => {
  const a = { kind: 'reply', includes: 'zebra' };
  assert.equal(assertTurn(a, { completed: true, finalMessage: 'Zebra received', runErrors: [] }).pass, true);
  for (const turn of [undefined, { completed: false, finalMessage: 'zebra' }, { completed: true, finalMessage: 'another answer' }, { completed: true, finalMessage: 'zebra', runErrors: ['failure'] }]) assert.equal(assertTurn(a, turn).pass, false);
});

test('submission assertion binds a tool result to the synthetic call and exact submitted values', () => {
  assert.deepEqual(intakeSubmissions(storedInput), [{ name: 'workbench_intake', context }]);
  assert.deepEqual(intakeSubmissions({ messages: [storedInput.messages[1]] }), []);
  const a = { kind: 'submission', name: 'workbench_intake', context };
  const turn = { completed: true, actionName: 'submit_intake', runErrors: [], submissions: intakeSubmissions(storedInput) };
  assert.equal(assertTurn(a, turn).pass, true);
  assert.equal(assertTurn({ ...a, context: { ...context, question: 'wrong' } }, turn).pass, false);
  assert.equal(assertTurn(a, { ...turn, actionName: undefined }).pass, false);
});

test('capture removes its route on HTTP failure, missing RUN_FINISHED and timeout', async () => {
  for (const settings of [{ httpOk: false }, { events: [{ type: 'RUN_STARTED' }] }]) {
    const { page, operations } = fixture(settings);
    await assert.rejects(captureTurn(page, options, () => page.trigger()));
    assert.equal(operations.at(-1), 'unroute');
  }
  const { page, operations } = fixture();
  await assert.rejects(captureTurn(page, { ...options, timeoutMs: 5 }, noWait), /timed out/);
  assert.equal(operations.at(-1), 'unroute');
});

test('new corpus cases validate actions, followup and computed result expectations', async () => {
  const corpus = await loadCases(new URL('../model/prompts.yaml', import.meta.url), { prompts: true });
  const form = corpus.find(c => c.id === 'submit_form');
  assert.equal(form.actions.at(-1).awaitTurn, true);
  assert.deepEqual(form.assertions[0].context, context);
  const repl = corpus.find(c => c.id === 'repl_result');
  assert.equal(repl.followup[0], 'What number did the program print? Reply with the number only.');
  assert.equal(repl.expectFail, undefined, 'the existing run-result path should work');
  const [base, exponent, modulus] = repl.assertions.at(-1).includes.pow.map(BigInt);
  assert.equal(replyExpectation(repl.assertions.at(-1).includes), String(base ** exponent % modulus));
  assert.equal(replyExpectation({ pow: [3, 0, 1] }), '0');
});

test('validation rejects malformed new fields and accepts explicit expected-failure reasons', () => {
  const valid = () => [{ id: 'fixture', prompt: 'Publish', followup: ['Answer'], actions: [{ kind: 'fill', name: 'Question', value: 'value' }], assertions: [{ kind: 'reply', includes: 'value' }] }];
  assert.doesNotThrow(() => validateCases([{ ...valid()[0], expectFail: 'Owner decision pending' }], { prompts: true }));
  for (const mutate of [
    c => { c.followup = 'Answer'; }, c => { c.followup = []; }, c => { c.followup = ['']; },
    c => { c.expectFail = true; }, c => { c.expectFail = ''; },
    c => { c.actions = {}; }, c => { c.actions = [null]; }, c => { c.actions[0].kind = 'invented'; },
    c => { delete c.actions[0].value; }, c => { c.actions[0].region = 'chat'; },
    c => { c.actions[0].role = 'button'; }, c => { c.actions[0].awaitTurn = true; },
    c => { c.actions = [{ role: 'button', name: 'Submit', awaitTurn: 'yes' }]; },
    c => { c.assertions[0].includes = ''; }, c => { c.assertions[0].includes = { pow: [7, -1, 3] }; },
    c => { c.assertions[0].includes = { pow: [7, 1, 0] }; }, c => { c.assertions[0].includes = { pow: [7, 1, 3.5] }; },
    c => { c.assertions[0].region = 'canvas'; },
    c => { c.assertions = [{ kind: 'submission', name: 'workbench_intake', context: { ...context, acknowledged: false } }]; },
  ]) {
    const data = valid(); mutate(data[0]);
    assert.throws(() => validateCases(data, { prompts: true }));
  }
  assert.throws(() => validateCases(valid()));
});


test('custom form assertions require a paired persisted submission, exact values, and its action turn', async () => {
  const context = { surfaceId: 'surface-survey', title: 'Scenario survey', values: { name: 'Scenario walrus', color: 'Blue', subscribe: true } };
  const input = { messages: [
    { role: 'assistant', toolCalls: [{ id: 'form-call', function: { name: 'workbench_form' } }] },
    { role: 'tool', toolCallId: 'form-call', content: JSON.stringify({ kind: 'untrusted_user_submitted_data', actionSchemaVersion: 'form.submit@1', context }) },
  ] };
  assert.deepEqual(intakeSubmissions(input), [{ name: 'workbench_form', context }]);
  const assertion = { kind: 'submission', name: 'workbench_form', context: { title: context.title, values: context.values } };
  const turn = { completed: true, actionName: 'submit_form', submissions: intakeSubmissions(input), runErrors: [] };
  assert.equal(assertTurn(assertion, turn).pass, true);
  assert.equal(assertTurn(assertion, { ...turn, actionName: 'submit_intake' }).pass, false);
  assert.equal(assertTurn({ ...assertion, context: { ...assertion.context, values: { ...context.values, color: 'Red' } } }, turn).pass, false);
  assert.equal(assertTurn(assertion, { ...turn, submissions: [...turn.submissions, ...turn.submissions] }).pass, false);
  input.messages[1].toolCallId = 'unpaired';
  assert.deepEqual(intakeSubmissions(input), []);
  const cases = await loadCases(new URL('../model/prompts.yaml', import.meta.url), { prompts: true });
  const custom = cases.find(c => c.id === 'custom_form');
  assert.equal(custom.actions[1].role, 'radio');
  assert.equal(custom.actions.at(-1).awaitTurn, true);
  assert.ok(cases.find(c => c.id === 'credential_form').assertions.some(a => a.absent && a.name === 'Password'));
  assert.throws(() => validateCases([{ id: 'bad', prompt: 'Test', assertions: [{ ...assertion, context: { title: 'T', values: [] } }] }], { prompts: true }));
});

test('a custom form submit also reads the stored run input', async () => {
  const { page, operations } = fixture({ actionName: 'submit_form' });
  const turns = [];
  await performActions(page, [{ role: 'button', name: 'Submit', region: 'left', awaitTurn: true }], options, turn => turns.push(turn), noWait);
  assert.ok(operations.includes('read-input'));
  assert.equal(turns[0].actionName, 'submit_form');
});


test('CSV assertions bind the downloaded last row to the action submission and values', async () => {
  const { page } = fixture();
  const turn = await captureTurn(page, options, () => page.trigger());
  const assertion = { kind: 'csv', filename: 'intake.csv', values: context };
  assert.equal(assertTurn(assertion, turn).pass, true);
  for (const changes of [
    { filename: 'other.csv' }, { rowCount: 0 }, { submissionId: 'other-id' },
    { lastRow: { ...turn.savedCsv.lastRow, question: 'wrong' } },
    { lastRow: { ...turn.savedCsv.lastRow, submitted_at: 'wrong' } },
  ]) assert.equal(assertTurn(assertion, { ...turn, savedCsv: { ...turn.savedCsv, ...changes } }).pass, false);
  assert.equal(assertTurn(assertion, { ...turn, completed: false }).pass, false);
  assert.equal(assertTurn(assertion, { ...turn, runErrors: ['failed'] }).pass, false);
  assert.equal(assertTurn(assertion, {}).pass, false);
  for (const settings of [{ missingFile: true }, { csvStatus: 404 }]) {
    const { page, operations } = fixture(settings);
    await assert.rejects(captureTurn(page, options, () => page.trigger()), /CSV/);
    assert.equal(operations.at(-1), 'unroute');
  }
});

test('CSV parser handles escaped quotes, commas, CRLF, multiline cells and rejects corruption', () => {
  assert.deepEqual(parseCsv('a,b,c\r\n"one,two","three""four","five\nline\rbreak"\r\n'), [
    ['a', 'b', 'c'], ['one,two', 'three"four', 'five\nline\rbreak'],
  ]);
  assert.deepEqual(parseCsv('a,b\n1,""'), [['a', 'b'], ['1', '']]);
  for (const invalid of ['a,b\n1', 'a,b\n"unterminated', 'a,b\n"x"oops,2', 'a,b\nquo"te,2']) assert.throws(() => parseCsv(invalid));
  for (const value of ['=x', '+x', '-1', '@x', '\tx', '\rx']) assert.equal(csvCell(value), "'" + value);
  assert.equal(csvCell(true), 'true');
  assert.equal(csvCell(['north']), '["north"]');
});

test('custom form corpus requires a saved filename reply and exact downloaded CSV values', async () => {
  const cases = await loadCases(new URL('../model/prompts.yaml', import.meta.url), { prompts: true });
  const custom = cases.find(c => c.id === 'custom_form');
  assert.ok(custom.assertions.some(a => a.kind === 'reply' && a.includes === 'scenario-survey.csv'));
  assert.deepEqual(custom.assertions.find(a => a.kind === 'csv').values, { name: 'Scenario walrus', color: 'Blue', subscribe: true });
  for (const filename of ['../escape.csv', 'https://evil.invalid/x', '']) {
    assert.throws(() => validateCases([{ ...custom, assertions: [{ kind: 'csv', filename, values: { name: 'x' } }] }], { prompts: true }));
  }
});

test('custom form submission and CSV checks ignore the case of model-chosen field names', () => {
  const submission = { name: 'workbench_form', context: { surfaceId: 's', title: 'Scenario survey', values: { Name: 'Scenario walrus', Color: 'Blue', Subscribe: true } } };
  const turn = { completed: true, actionName: 'submit_form', runErrors: [], submissions: [submission],
    savedCsv: { filename: 'scenario-survey.csv', rowCount: 1, submissionId: 'sub-1', lastRow: { submitted_at: '2026-11-20T00:00:00Z', submission_id: 'sub-1', Name: 'Scenario walrus', Color: 'Blue', Subscribe: 'true' } } };
  const values = { name: 'Scenario walrus', color: 'Blue', subscribe: true };
  assert.equal(assertTurn({ kind: 'submission', name: 'workbench_form', context: { title: 'Scenario survey', values } }, turn).pass, true);
  assert.equal(assertTurn({ kind: 'csv', filename: 'scenario-survey.csv', values }, turn).pass, true);
  assert.equal(assertTurn({ kind: 'csv', filename: 'scenario-survey.csv', values: { ...values, color: 'Red' } }, turn).pass, false);
});

function programFixture({ repair = true, arrive = true, success = true, unrelated = false } = {}) {
  let handler;
  const operations = [];
  const turn = async (name, context, events = []) => {
    const body = [...events, { type: 'RUN_FINISHED' }].map(e => `data: ${JSON.stringify(e)}\n\n`).join('');
    await handler({
      request: () => ({ method: () => 'POST', url: () => unrelated ? url.replace('thread-id', 'other-thread') : url,
        postDataJSON: () => ({ forwardedProps: { a2uiAction: { userAction: { name, context } } } }) }),
      fetch: async () => ({ text: async () => body, ok: () => true }),
      fulfill: async () => operations.push('fulfill'),
      abort: async () => operations.push('abort'),
      fallback: async () => operations.push('fallback'),
    });
  };
  const page = {
    route: async (_, callback) => { handler = callback; operations.push('route'); },
    unroute: async (_, callback) => { assert.equal(callback, handler); operations.push('unroute'); },
    async trigger() {
      if (!repair) return;
      await turn('workbench.program.repair', { result: { run: 1, aiFix: true, autoRun: true } }, [
        { type: 'TOOL_CALL_START', toolCallName: 'repair_program' },
        ...(arrive ? [{ type: 'ACTIVITY_SNAPSHOT' }] : []),
      ]);
      if (success) await turn('workbench.program.run_result', { outcome: 'success', output: '766228' });
    },
  };
  return { page, operations };
}

test('AI Fix off observes a full 20 seconds and records zero action turns', async () => {
  const { page, operations } = programFixture({ repair: false });
  const waits = [];
  const observation = await captureProgramTurns(page, options, () => page.trigger(), false, undefined, async ms => waits.push(ms));
  assert.deepEqual(waits, [20000]);
  assert.deepEqual(observation, { actionTurns: 0, repairRequests: 0, successfulRuns: 0, observationMs: 20000 });
  assert.deepEqual(operations, ['route', 'unroute']);
});

test('AI Fix off rejects any unexpected action and removes the observer', async () => {
  const { page, operations } = programFixture();
  await assert.rejects(captureProgramTurns(page, options, () => page.trigger(), false, undefined, noWait), /AI Fix off sent action turn/);
  assert.equal(operations.at(-1), 'unroute');
});

test('AI Fix on requires a repair publication and the next successful execution action', async () => {
  const { page, operations } = programFixture();
  const turns = [];
  const result = await captureProgramTurns(page, options, () => page.trigger(), true, t => turns.push(t));
  assert.equal(result.actionTurns, 2);
  assert.equal(result.repairRequests, 1);
  assert.equal(result.successfulRuns, 1);
  assert.equal(turns[1].programContext.output, '766228');
  assert.equal(operations.at(-1), 'unroute');
  const missing = programFixture({ arrive: false });
  await assert.rejects(captureProgramTurns(missing.page, options, () => missing.page.trigger(), true), /Expected one repair arrival/);
});

test('AI Fix on times out without automatic success and ignores other threads', async () => {
  for (const settings of [{ success: false }, { unrelated: true }]) {
    const { page, operations } = programFixture(settings);
    await assert.rejects(captureProgramTurns(page, { ...options, timeoutMs: 5 }, () => page.trigger(), true), /timed out/);
    assert.equal(operations.at(-1), 'unroute');
    if (settings.unrelated) assert.ok(operations.includes('fallback'));
  }
});

test('run_program actions validate and require room context', async () => {
  const cases = await loadCases(new URL('../model/prompts.yaml', import.meta.url), { prompts: true });
  for (const state of ['off', 'on']) {
    const item = cases.find(c => c.id === `ai_fix_${state}`);
    assert.equal(item.actions.at(-1).kind, 'run_program');
    assert.equal(item.actions.at(-1).expectRepair, state === 'on');
    assert.equal(item.actions.some(a => a.kind === 'check'), state === 'on');
    assert.ok(item.assertions.some(a => a.name === (state === 'on' ? replyExpectation({ pow: [7, 12345, 1000003] }) : 'scenario deliberate failure')));
    assert.throws(() => validateCases([{ ...item, actions: [{ kind: 'run_program', name: 'Run' }] }], { prompts: true }));
  }
  const { page } = fixture();
  await assert.rejects(performActions(page, [{ kind: 'run_program', name: 'Submit', expectRepair: false }], undefined, undefined, noWait), /requires room and thread/);
});

test('run_program clicks through the action dispatcher and returns observation counts', async () => {
  const { page, operations } = fixture();
  page.trigger = async () => {};
  const waits = [];
  const observations = await performActions(page, [{ kind: 'run_program', name: 'Submit', expectRepair: false }], options, undefined, async ms => waits.push(ms));
  assert.equal(observations[0].actionTurns, 0);
  assert.ok(operations.includes('click:Submit'));
  assert.ok(waits.includes(20000));
  assert.equal(operations.at(-1), 'unroute');
});

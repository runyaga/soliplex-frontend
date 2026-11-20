import test from 'node:test';
import assert from 'node:assert/strict';
import { performActions } from '../lib/actions.mjs';
import { captureTurn } from '../lib/turns.mjs';
import { assertTurn, intakeSubmissions, loadCases, replyExpectation, validateCases } from '../lib/core.mjs';

const noWait = async () => {};
const options = { room: 'workbench', threadId: 'thread-id', timeoutMs: 1000 };
const url = 'https://example.invalid/api/v1/rooms/workbench/agui/thread-id/run-id';
const context = { question: 'Scenario zebra question', districts: ['north'], acknowledged: true };
const storedInput = {
  messages: [
    { role: 'assistant', toolCalls: [{ id: 'call-id', function: { name: 'workbench_intake' } }] },
    { role: 'tool', toolCallId: 'call-id', content: JSON.stringify({ kind: 'untrusted_user_submitted_data', actionSchemaVersion: 'intake.submit@1', context }) },
  ],
};

function fixture({ events, actionName = 'submit_intake', httpOk = true } = {}) {
  const operations = [];
  const nodes = [
    ['textbox', 'Scenario intake Question Districts'],
    ['button', 'North'], ['button', 'South'], ['checkbox', 'Acknowledged'], ['button', 'Submit'],
  ].map(([role, name]) => ({
    role, name,
    isVisible: async () => true,
    boundingBox: async () => ({ x: 1, y: 1, width: 100, height: 30 }),
    click: async () => { operations.push(`click:${name}`); if (name === 'Submit') await page.trigger(); },
    setChecked: async value => operations.push(`check:${name}:${value}`),
    getAttribute: async () => null,
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
    request: { get: async address => {
      assert.equal(address, url);
      operations.push('read-input');
      return { ok: () => true, json: async () => ({ run_input: storedInput }) };
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
        request: () => ({ method: () => 'POST', url: () => url, postDataJSON: () => ({ forwardedProps: { a2uiAction: { userAction: { name: actionName } } } }) }),
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
  assert.deepEqual(operations, ['click:North', 'check:Acknowledged:true']);
  nodes.find(n => n.name === 'North').getAttribute = async name => name === 'aria-pressed' ? 'true' : null;
  await performActions(page, [{ kind: 'select', name: 'North', region: 'left' }], undefined, undefined, noWait);
  assert.equal(operations.length, 2, 'a selected chip is not toggled off');
});

test('awaitTurn captures the action stream and server-authored intake input before returning', async () => {
  const { page, operations } = fixture();
  const turns = [];
  await performActions(page, [{ role: 'button', name: 'Submit', region: 'left', awaitTurn: true }], options, turn => turns.push(turn), noWait);
  assert.deepEqual(operations, ['route', 'click:Submit', 'fulfill', 'read-input', 'unroute']);
  assert.equal(turns.length, 1);
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

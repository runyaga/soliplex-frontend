import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { validateCases } from '../lib/core.mjs';
import { watchWalkthrough } from '../lib/walkthrough.mjs';

const checkpoints = JSON.parse(await readFile(new URL('../model/walkthrough.json', import.meta.url)));
const cases = JSON.parse(await readFile(new URL('../model/prompts.yaml', import.meta.url)));

test('walkthrough corpus clicks Start and has ordered narrated surface checkpoints', () => {
  assert.equal(validateCases(cases, { prompts: true }).find(c => c.id === 'walkthrough').walkthrough, true);
  assert.equal(checkpoints.length, 17);
  assert(checkpoints.every(c => c.title && c.assertions.length));
  assert(checkpoints[6].assertions.some(a => a.includes === 'Sample visitor'));
  assert.match(checkpoints[15].title, /skipped/);
  assert(checkpoints.at(-1).assertions.some(a => a.absent));
});

function fakePage({ skip = -1, model = false } = {}) {
  let handler;
  let removed = false;
  let clicked;
  const page = {
    async route(pattern, callback) { handler = callback; },
    async unroute() { removed = true; },
    getByRole(role, options) {
      assert.equal(role, 'button');
      assert.equal(options.name, 'Start the walkthrough.');
      return { async click() {
        clicked = true;
        for (let i = 0; i < checkpoints.length; i++) {
          if (i === skip) continue;
          const events = [
            { type: 'RUN_STARTED', threadId: 'thread', runId: `run${i}` },
            ...(model ? [{ type: 'TOOL_CALL_START', toolCallId: 't', toolCallName: 'unexpected' }] : []),
            { type: 'TEXT_MESSAGE_START', messageId: `message${i}`, role: 'assistant' },
            { type: 'TEXT_MESSAGE_CONTENT', messageId: `message${i}`, delta: `Step ${i + 1} of ${checkpoints.length} · ${checkpoints[i].title}` },
            { type: 'TEXT_MESSAGE_END', messageId: `message${i}` },
            { type: 'RUN_FINISHED', threadId: 'thread', runId: `run${i}` },
          ];
          await handler({
            request: () => ({ method: () => 'POST', url: () => `https://example.test/api/v1/rooms/room/agui/thread/run${i}`, postDataJSON: () => i ? { forwardedProps: { a2uiAction: { userAction: { name: 'workbench.walkthrough.next' } } } } : {} }),
            fetch: async () => ({ ok: () => true, text: async () => events.map(e => `data: ${JSON.stringify(e)}\n\n`).join('') }),
            fulfill: async () => {}, abort: async () => {},
          });
        }
      } };
    },
  };
  return { page, removed: () => removed, clicked: () => clicked };
}

test('watcher inspects every step and finishes only at the wrap-up', async () => {
  const fake = fakePage();
  let inspections = 0, turns = 0;
  const assertions = await watchWalkthrough(fake.page, { room: 'room', threadId: 'thread', timeoutMs: 100 }, checkpoints, async (page, checks) => {
    assert.equal(page, fake.page);
    assert(checks[0].name.includes(`Step ${++inspections} of 17`));
    return [{ pass: true, label: checks[1].name }];
  }, () => { turns++; });
  assert.equal(turns, 17); assert.equal(inspections, 17);
  assert.equal(assertions.length, 17);
  assert(fake.clicked()); assert(fake.removed());
});

test('watcher rejects missing steps and model tools, and always detaches', async () => {
  for (const options of [{ skip: 5 }, { model: true }]) {
    const fake = fakePage(options);
    await assert.rejects(watchWalkthrough(fake.page, { room: 'room', threadId: 'thread', timeoutMs: 100 }, checkpoints, async () => [{ pass: true }]), /out of order|model\/tool/);
    assert(fake.removed());
  }
});


test('watcher rejects a failed visible surface checkpoint and detaches', async () => {
  const fake = fakePage();
  await assert.rejects(watchWalkthrough(fake.page, { room: 'room', threadId: 'thread', timeoutMs: 100 }, checkpoints, async () => [{ pass: false }]), /surface missing/);
  assert(fake.removed());
});

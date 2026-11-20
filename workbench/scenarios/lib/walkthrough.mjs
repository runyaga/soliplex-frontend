import { parseSSE, summarizeEvents } from './core.mjs';

// Keep interception installed for the whole tour, including its program-layout
// turns. Each checkpoint inspects visible pixels after delivery to the real app.
export async function watchWalkthrough(page, options, checkpoints, inspect, onTurn = () => {}) {
  let finish, reject;
  const complete = new Promise((resolve, fail) => { finish = resolve; reject = fail; });
  complete.catch(() => {});
  const pending = new Set();
  const assertions = [];
  let expected = 0;
  let failure;
  let queue = Promise.resolve();
  const handler = async route => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (request.method() !== 'POST' || !path.includes(`/rooms/${options.room}/agui/${options.threadId}/`) || path.split('/').length !== 8) return route.fallback();
    let response, body;
    try {
      response = await route.fetch({ timeout: options.timeoutMs });
      body = await response.text();
      await route.fulfill({ response, body });
    } catch (error) {
      failure ??= error;
      reject(error);
      await route.abort().catch(() => {});
      return;
    }
    // Check turns one at a time in arrival order. A slow checkpoint must
    // surface as its own failure, not as the next step arriving early.
    const task = queue = queue.then(async () => {
      if (failure) return;
      try {
        const events = parseSSE(body);
        if (!response.ok()) throw new Error(`Walkthrough HTTP ${response.status()}`);
        const turn = summarizeEvents(events);
        turn.threadId = options.threadId;
        if (!turn.completed || turn.runErrors.length || turn.toolCalls.length) throw new Error('Walkthrough called a model/tool or failed');
        await onTurn(turn);
        const input = request.postDataJSON();
        const action = input?.forwardedProps?.a2uiAction?.userAction?.name;
        if (action && !action.startsWith('workbench.walkthrough.')) return;
        const story = events.filter(e => e.type === 'TEXT_MESSAGE_CONTENT').map(e => e.delta).join('');
        const checkpoint = checkpoints[expected];
        if (!checkpoint || !story.includes(`Step ${expected + 1} of ${checkpoints.length}`) || !story.includes(checkpoint.title)) throw new Error(`Walkthrough narration out of order at step ${expected + 1}`);
        const checked = await inspect(page, [
          { kind: 'text', name: `Step ${expected + 1} of ${checkpoints.length}`, region: 'tray' },
          { kind: 'text', name: checkpoint.title, region: 'tray' },
          ...checkpoint.assertions,
        ], 12000);
        assertions.push(...checked.map(a => ({ ...a, label: `Walkthrough step ${expected + 1}: ${a.label}` })));
        if (checked.some(a => !a.pass)) throw new Error(`Walkthrough surface missing at step ${expected + 1}`);
        expected++;
        if (expected === checkpoints.length) finish();
      } catch (error) {
        failure ??= error;
        reject(error);
      }
    });
    pending.add(task);
    try { await task; } finally { pending.delete(task); }
  };
  await page.route('**/agui/**', handler);
  let timer;
  try {
    await page.getByRole('button', { name: 'Start the walkthrough.', exact: true }).click();
    await Promise.race([complete, new Promise((_, fail) => { timer = setTimeout(() => fail(new Error(`Walkthrough timed out at step ${expected + 1}`)), Math.max(options.timeoutMs, 240000)); })]);
    await Promise.all([...pending]);
    if (failure) throw failure;
    return assertions;
  } finally {
    clearTimeout(timer);
    await page.unroute('**/agui/**', handler);
  }
}

import { readFile } from 'node:fs/promises';
import { watchWalkthrough } from '../lib/walkthrough.mjs';
import { assertCanvas, freshThread, performActions, screenshot, sendPrompt, timelineTools, visibleErrors } from '../lib/browser.mjs';
import { assertTurn, failedAssertions } from '../lib/core.mjs';

export const MODELS = [
  { room: 'workbench', name: 'Glimmer' },
  { room: 'workbench-e4b', name: 'Gemma 4 E4B' },
];

export async function checkModels({ page, base, alias, cases, directory, credentials, timeoutMs, record, recordThread }) {
  const createdThreads = new Set();
  // WB_MODELS=workbench-e4b runs only those rooms.
  const rooms = new Set((process.env.WB_MODELS || '').split(',').map(room => room.trim()).filter(Boolean));
  for (const model of MODELS.filter(m => !rooms.size || rooms.has(m.room))) {
    for (const item of cases) {
      const result = { id: item.id, model: model.name, assertions: [], runErrors: [], toolCalls: [], timelineTools: [], turns: [] };
      let latestTurn;
      const remember = (turn, stage) => {
        latestTurn = turn;
        result.threadId = turn.threadId;
        result.turns.push({ stage, ...turn });
        result.runErrors.push(...turn.runErrors);
        result.toolCalls.push(...turn.toolCalls);
        result.finalMessage = turn.finalMessage;
        if (!turn.completed || turn.runErrors.length) throw new Error('Agent turn did not finish successfully');
      };
      try {
        result.threadId = await freshThread(page, base, alias, model.room, recordThread);
        if (createdThreads.has(result.threadId)) throw new Error('A prompt reused an earlier case thread');
        createdThreads.add(result.threadId);
        if (item.walkthrough) {
          const checkpoints = JSON.parse(await readFile(new URL('./walkthrough.json', import.meta.url), 'utf8'));
          result.assertions.push(...await watchWalkthrough(page, { room: model.room, threadId: result.threadId, timeoutMs }, checkpoints, assertCanvas, turn => remember(turn, 'walkthrough')));
        }
        for (const [index, prompt] of [...(item.setup ?? []), ...(item.walkthrough ? [] : [item.prompt])].entries()) {
          const turn = await sendPrompt(page, model.room, prompt, timeoutMs, result.threadId);
          remember(turn, index < (item.setup?.length ?? 0) ? 'setup' : 'prompt');
          if (index === (item.setup?.length ?? 0) - 1 && item.setup_assertions) {
            const setup = await assertCanvas(page, item.setup_assertions);
            result.assertions.push(...setup.map(a => ({ ...a, label: `Setup: ${a.label}` })));
            if (setup.some(a => !a.pass)) throw new Error('Required follow-up setup did not render');
          }
        }
        result.programRuns = await performActions(page, item.actions, { room: model.room, threadId: result.threadId, timeoutMs }, turn => remember(turn, 'action'), undefined, async assertions => {
          const checked = await assertCanvas(page, assertions);
          result.assertions.push(...checked.map(a => ({ ...a, label: `After action: ${a.label}` })));
          return checked;
        });
        for (const prompt of item.followup ?? []) {
          remember(await sendPrompt(page, model.room, prompt, timeoutMs, result.threadId), 'followup');
        }
      } catch (error) {
        result.error = error.message;
      }
      try {
        const canvas = item.assertions.filter(a => !['reply', 'submission', 'csv'].includes(a.kind));
        result.assertions.push(...await assertCanvas(page, canvas, result.error ? 0 : 12000));
        result.assertions.push(...item.assertions.filter(a => ['reply', 'submission', 'csv'].includes(a.kind)).map(a => assertTurn(a, latestTurn)));
      } catch {
        result.assertions.push(...failedAssertions(item.assertions, 'Canvas could not be inspected'));
        result.error ||= 'Canvas inspection failed';
      }
      result.timelineTools = await timelineTools(page, result.toolCalls).catch(() => []);
      result.runErrors.push(...await visibleErrors(page).catch(() => []));
      try {
        const filename = `model-${model.room}-${item.id}.png`;
        await screenshot(page, `${directory}/${filename}`, credentials, { room: model.room, threadId: result.threadId });
        result.screenshot = filename;
      } catch {
        result.error ||= 'Prompt screenshot failed';
      }
      result.pass = !result.error && result.runErrors.length === 0 && result.assertions.length > 0 && result.assertions.every(a => a.pass);
      if (item.expectFail) {
        result.expectFail = item.expectFail;
        result.unexpectedPass = result.pass;
        // Expected failures remain visible failures and keep the suite nonzero.
      }
      await record(result);
    }
  }
}

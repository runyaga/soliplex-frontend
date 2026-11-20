import { assertCanvas, freshThread, performActions, screenshot, sendPrompt, timelineTools, visibleErrors } from '../lib/browser.mjs';
import { failedAssertions } from '../lib/core.mjs';

export const MODELS = [
  { room: 'workbench', name: 'Glimmer' },
  { room: 'workbench-e4b', name: 'Gemma 4 E4B' },
];

export async function checkModels({ page, base, alias, cases, directory, credentials, timeoutMs, record }) {
  const createdThreads = new Set();
  for (const model of MODELS) {
    for (const item of cases) {
      const result = { id: item.id, model: model.name, assertions: [], runErrors: [], toolCalls: [], timelineTools: [], turns: [] };
      try {
        result.threadId = await freshThread(page, base, alias, model.room);
        if (createdThreads.has(result.threadId)) throw new Error('A prompt reused an earlier case thread');
        createdThreads.add(result.threadId);
        for (const [index, prompt] of [...(item.setup ?? []), item.prompt].entries()) {
          const turn = await sendPrompt(page, model.room, prompt, timeoutMs, result.threadId);
          result.threadId = turn.threadId;
          result.turns.push({ setup: index < (item.setup?.length ?? 0), ...turn });
          result.runErrors.push(...turn.runErrors);
          result.toolCalls.push(...turn.toolCalls);
          result.finalMessage = turn.finalMessage;
          if (turn.runErrors.length) throw new Error('Agent reported RUN_ERROR');
          if (index === (item.setup?.length ?? 0) - 1 && item.setup_assertions) {
            const setup = await assertCanvas(page, item.setup_assertions);
            result.assertions.push(...setup.map(a => ({ ...a, label: `Setup: ${a.label}` })));
            if (setup.some(a => !a.pass)) throw new Error('Required follow-up setup did not render');
          }
        }
        await performActions(page, item.actions);
      } catch (error) {
        result.error = error.message;
      }
      try {
        result.assertions.push(...await assertCanvas(page, item.assertions, result.error ? 0 : 12000));
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
      await record(result);
    }
  }
}

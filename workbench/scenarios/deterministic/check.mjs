import { assertCanvas, openThread, semantics, screenshot, visibleErrors, waitForComposer } from '../lib/browser.mjs';
import { failedAssertions } from '../lib/core.mjs';

export async function checkDeterministic({ page, base, alias, seeds, cases, directory, credentials, record }) {
  for (const item of cases) {
    const seed = seeds.find(s => s.scenario === item.id);
    const result = { id: item.id, model: 'No model', threadId: seed?.thread_id, assertions: [], runErrors: [] };
    try {
      if (!result.threadId) throw new Error('Backend seeding failed before a completed run was saved');
      await openThread(page, base, alias, 'workbench', result.threadId);
      result.assertions = await assertCanvas(page, item.assertions);
      if (item.reload) {
        await page.reload({ waitUntil: 'domcontentloaded' });
        await semantics(page);
        await waitForComposer(page);
        const replay = await assertCanvas(page, item.assertions);
        result.assertions.push(...replay.map(a => ({ ...a, label: `After reload: ${a.label}` })));
      }
      result.runErrors = await visibleErrors(page);
    } catch (error) {
      result.error = error.message;
      if (!result.assertions.length) result.assertions = failedAssertions(item.assertions, 'Not evaluated because scenario setup failed');
    }
    if (result.threadId) {
      try {
        const filename = `deterministic-${item.id}.png`;
        await screenshot(page, `${directory}/${filename}`, credentials, { threadId: result.threadId });
        result.screenshot = filename;
      } catch {
        result.error ||= 'Scenario screenshot failed';
      }
    }
    result.pass = !result.error && result.runErrors.length === 0 && result.assertions.length > 0 && result.assertions.every(a => a.pass);
    await record(result);
  }
}

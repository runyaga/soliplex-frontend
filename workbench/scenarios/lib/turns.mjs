import { intakeSubmissions, parseSSE, summarizeEvents } from './core.mjs';

export async function captureTurn(page, { room, threadId, timeoutMs }, trigger) {
  let settle;
  const captured = new Promise((resolve, reject) => { settle = { resolve, reject }; });
  captured.catch(() => {});
  let claimed = false;
  const handler = async route => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (request.method() !== 'POST' || !path.includes(`/rooms/${room}/agui/${threadId}/`) || path.split('/').length !== 8 || claimed) return route.fallback();
    claimed = true;
    try {
      // Fetch the actual Flutter request. Chrome cannot reliably reread SSE
      // response bodies after delivery, so fulfil with the captured full body.
      const response = await route.fetch({ timeout: timeoutMs });
      const body = await response.text();
      await route.fulfill({ response, body });
      settle.resolve({ status: response.status(), ok: response.ok(), url: request.url(), body, input: request.postDataJSON() });
    } catch (error) {
      settle.reject(error);
      await route.abort().catch(() => {});
    }
  };
  await page.route('**/agui/**', handler);
  let timer;
  try {
    const response = await Promise.race([
      (async () => { await trigger(); return captured; })(),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Agent stream timed out')), timeoutMs); }),
    ]);
    if (!response.ok) throw new Error(`Agent HTTP ${response.status}`);
    const summary = summarizeEvents(parseSSE(response.body));
    summary.threadId = threadId;
    summary.actionName = response.input?.forwardedProps?.a2uiAction?.userAction?.name;
    if (!summary.completed && summary.runErrors.length === 0) throw new Error('Agent stream ended without RUN_FINISHED');
    if (summary.actionName === 'submit_intake') {
      // The synthetic tool pair is server-authored and absent from the POST.
      // This public read uses the same authenticated Playwright context.
      const stored = await page.request.get(response.url, { timeout: timeoutMs });
      if (!stored.ok()) throw new Error(`Stored run HTTP ${stored.status()}`);
      summary.submissions = intakeSubmissions((await stored.json()).run_input);
    }
    return summary;
  } finally {
    clearTimeout(timer);
    await page.unroute('**/agui/**', handler);
  }
}

import { parseCsv } from './csv.mjs';
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
      // The app authenticates with a bearer header, not cookies. Keep it in
      // memory for the stored-run read and never record it.
      const authorization = (await request.allHeaders()).authorization;
      settle.resolve({ status: response.status(), ok: response.ok(), url: request.url(), body, input: request.postDataJSON(), authorization });
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
    if (['submit_intake', 'submit_form'].includes(summary.actionName)) {
      // The synthetic tool pair is server-authored and absent from the POST.
      // This public read uses the same authenticated Playwright context.
      const headers = response.authorization ? { authorization: response.authorization } : {};
      const stored = await page.request.get(response.url, { timeout: timeoutMs, headers });
      if (!stored.ok()) throw new Error(`Stored run HTTP ${stored.status()}`);
      const storedInput = (await stored.json()).run_input;
      summary.submissions = intakeSubmissions(storedInput);
      const filename = storedInput?.forwardedProps?.workbenchFormReceipt?.filename;
      if (typeof filename !== 'string' || !/^[a-z0-9-]+\.csv$/.test(filename)) throw new Error('Missing saved CSV receipt');
      const listingUrl = new URL(`/api/v1/workdirs/${encodeURIComponent(room)}/thread/${encodeURIComponent(threadId)}`, response.url);
      const listing = await page.request.get(listingUrl.href, { timeout: timeoutMs, headers });
      if (!listing.ok()) throw new Error(`Workdir listing HTTP ${listing.status()}`);
      if (!(await listing.json()).files?.some(file => file.filename === filename)) throw new Error('Saved CSV absent from public workdir listing');
      const download = await page.request.get(`${listingUrl.href}/file/${encodeURIComponent(filename)}`, { timeout: timeoutMs, headers });
      if (!download.ok()) throw new Error(`CSV download HTTP ${download.status()}`);
      const [columns, ...rows] = parseCsv(await download.text());
      if (!columns || !rows.length) throw new Error('Saved CSV has no data rows');
      summary.savedCsv = {
        filename, rowCount: rows.length, columns,
        lastRow: Object.fromEntries(columns.map((name, index) => [name, rows.at(-1)[index]])),
        submissionId: response.input.forwardedProps.a2uiAction.submissionId,
      };
    }
    return summary;
  } finally {
    clearTimeout(timer);
    await page.unroute('**/agui/**', handler);
  }
}

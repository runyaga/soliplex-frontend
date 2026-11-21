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

// Observe every action turn, including a repair followed by its automatic Run.
// Off must stay quiet for the full 20 seconds; a single captured turn is a failure.
// An expectedOutput without a repair instead requires a successful ordinary Run.
export async function captureProgramTurns(page, { room, threadId, timeoutMs, expectedOutput, expectRepairs }, trigger, expectRepair, onTurn = () => {}, wait = ms => new Promise(resolve => setTimeout(resolve, ms))) {
  const repairCount = expectRepairs ?? (expectRepair === true ? 1 : (expectRepair || 0));
  expectRepair = repairCount > 0;
  const expectSuccess = !expectRepair && Boolean(expectedOutput);
  const turns = [];
  let completed;
  let rejected;
  const finished = new Promise((resolve, reject) => { completed = resolve; rejected = reject; });
  finished.catch(() => {});
  const pending = new Set();
  let firstError;
  const handler = async route => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    if (request.method() !== 'POST' || !path.includes(`/rooms/${room}/agui/${threadId}/`) || path.split('/').length !== 8) return route.fallback();
    const task = (async () => {
      try {
        const input = request.postDataJSON();
        const response = await route.fetch({ timeout: timeoutMs });
        const body = await response.text();
        await route.fulfill({ response, body });
        if (!response.ok()) throw new Error(`Program action HTTP ${response.status()}`);
        const events = parseSSE(body);
        const summary = summarizeEvents(events);
        summary.threadId = threadId;
        const action = input?.forwardedProps?.a2uiAction?.userAction;
        summary.actionName = action?.name;
        summary.programContext = action?.context;
        summary.surfaceId = action?.surfaceId;
        summary.activitySnapshots = events.filter(e => e.type === 'ACTIVITY_SNAPSHOT').length;
        turns.push(summary);
        await onTurn(summary);
        if (!summary.completed || summary.runErrors.length) throw new Error('Program action turn failed');
        if (!expectRepair && !expectSuccess) throw new Error(`AI Fix off sent action turn: ${summary.actionName}`);
        if (summary.actionName === 'workbench.program.run_result' && summary.programContext?.outcome === 'success') completed();
      } catch (error) {
        firstError ??= error;
        rejected(error);
        await route.abort().catch(() => {});
      }
    })();
    pending.add(task);
    try { await task; } finally { pending.delete(task); }
  };
  await page.route('**/agui/**', handler);
  let timer;
  try {
    await trigger();
    await Promise.race([
      finished,
      new Promise((resolve, reject) => {
        if (expectRepair || expectSuccess) timer = setTimeout(() => reject(new Error('Program Run timed out')), timeoutMs);
        else wait(20000).then(resolve, reject);
      }),
    ]);
    await Promise.all([...pending]);
    if (firstError) throw firstError;
    const repairs = turns.filter(t => t.actionName === 'workbench.program.repair');
    const runs = turns.filter(t => t.actionName === 'workbench.program.run_result');
    const layouts = turns.filter(t => t.actionName === 'workbench.program.layout');
    const unexpected = turns.filter(t => !['workbench.program.repair', 'workbench.program.run_result', 'workbench.program.layout'].includes(t.actionName));
    if (expectSuccess && (repairs.length !== 0 || runs.length !== 1 || turns.length !== 1 || runs[0].programContext?.outcome !== 'success')) {
      throw new Error('Expected one successful Run and no repair');
    }
    if (expectRepair && (repairs.length !== repairCount ||
        repairs.some((repair, i) => repair.programContext?.result?.run !== i + 1 ||
          (repairCount > 1 && repair.programContext?.result?.attempt !== i + 1) ||
          repair.programContext?.result?.aiFix !== true || repair.programContext?.result?.autoRun !== true ||
          !repair.toolCalls.some(name => ['repair_program', 'run_python_client'].includes(name)) || repair.activitySnapshots < 1) ||
        runs.length !== 1 || runs[0].programContext?.outcome !== 'success' || turns.length !== repairCount + 1 + layouts.length || layouts.length > 1 || unexpected.length > 0)) {
      throw new Error(`Expected ${repairCount === 1 ? 'one' : repairCount} repair arrival and one automatic success: ${repairs.length} repairs, ${runs.length} results, ${turns.length} action turns`);
    }
    if (expectRepair && [...repairs, ...layouts].some(repair => !repair.surfaceId || repair.surfaceId !== runs[0].surfaceId ||
        (repair.actionName === 'workbench.program.repair' && (!repair.programContext.result.chainId || repair.programContext.result.chainId !== runs[0].programContext.chainId)))) {
      throw new Error('Automatic Run did not belong to the repaired program and chain');
    }
    if ((expectRepair || expectSuccess) && expectedOutput && !runs[0].programContext.output?.includes(expectedOutput)) {
      throw new Error('Program Run output did not match the expected value');
    }
    return { actionTurns: turns.length, repairRequests: repairs.length, successfulRuns: runs.length, observationMs: expectRepair || expectSuccess ? undefined : 20000 };
  } finally {
    clearTimeout(timer);
    await page.unroute('**/agui/**', handler);
  }
}

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { performance } from 'node:perf_hooks';
import { resolve } from 'node:path';
import { cleanEvidence, parseCredentials, parseSSE, redactor, regionSelector } from '../lib/core.mjs';

export const probePlan = [
  ['compute', 'Compute', 24], ['redraw', 'Redraw', 5], ['charts', 'Charts', 5],
  ['events', 'Events', 1], ['long', 'Long session', 300], ['files', 'Files', 4],
  ['state', 'App state', 8], ['types', 'Type check', 1],
  ['windows', 'Windows', 20], ['cycles', 'Window cycles', 40],
];

export async function driveProbePlan({ sample, onSample = async () => {}, afterGroup = async () => {} }) {
  const groups = [];
  for (const [probe, label, limit] of probePlan) {
    const samples = [];
    for (let index = 0; index < limit; index++) {
      let result;
      try {
        result = await sample({ probe, label, index });
      } catch (error) {
        result = { ...error?.observation, index, status: 'harness_error', error: String(error?.message ?? error) };
      }
      samples.push(result);
      await onSample(probe, result);
      if (['compute', 'windows', 'cycles', 'long'].includes(probe) && result.error && result.status !== 'harness_error') break;
    }
    const bounded = ['compute', 'windows', 'cycles'].includes(probe);
    const group = { probe, samples, censored: bounded && !samples.some(s => s.status === 'rejected') };
    groups.push(group);
    try {
      await afterGroup(group);
    } catch (error) {
      group.error = String(error?.message ?? error);
    }
  }
  return groups;
}

export function reportMarkdown(report) {
  const cell = value => String(value ?? '').replaceAll('|', '\\|').replaceAll('\n', ' ');
  const lines = ['# Platform probe report', '', `Started: ${report.started}`, '',
    `Thread: ${report.threadId ?? 'not created'}`, '',
    'Timings use the harness monotonic clock around Chrome click dispatch, the recorded program result, visible status and idle controls. Program outcomes are preserved separately from browser observations. Visibility, paint and harness failures are reported as harness_error, not platform rejections. Window timings also await the server response. Timings include transport, UI construction and frame scheduling; they are not isolated CPU timings. Type-check timings use a Dart Stopwatch around the checker, including worker startup.', '',
    'The workdir file is downloaded as probe-results.json; browser-results.json contains every click (including the 300-click session), errors and checker timings. app-snapshots.json records the actual outgoing app state and Glimmer replies. Threads are retained for inspection.', '',
    '| Probe | Sample | Click → result ms | Status | Detail |', '| --- | --- | --- | --- | --- |'];
  for (const group of report.groups ?? []) {
    for (const sample of group.samples) lines.push(`| ${cell(group.probe)} | ${cell(sample.size ?? sample.index + 1)} | ${sample.wall_ms?.toFixed(2) ?? ''} | ${cell(sample.status)} | ${cell(sample.error ?? sample.detail)} |`);
    if (group.error) lines.push(`| ${group.probe} | cleanup | | harness_error | ${cell(group.error)} |`);
    if (group.censored) lines.push(`| ${group.probe} | search cap | | censored | No rejection observed within the safety cap; ceiling unknown |`);
  }
  lines.push('', '## Observed boundaries', '');
  for (const group of report.groups ?? []) {
    const accepted = group.samples.filter(sample => sample.program_status === 'completed' || (!sample.error && sample.status === 'completed'));
    if (group.probe === 'compute') lines.push(`- Compute: largest tested success ${accepted.at(-1)?.size ?? 'none'} iterations; first rejection ${group.samples.find(s => s.status === 'rejected')?.size ?? 'not observed'}.`);
    if (group.probe === 'long') lines.push(`- Long session: last confirmed count ${accepted.at(-1)?.count ?? 0} after ${group.samples.length} clicks.`);
    if (['windows', 'cycles'].includes(group.probe)) lines.push(`- ${group.probe}: ${accepted.length} accepted requests; last accepted server tree had ${accepted.at(-1)?.server_nodes ?? 'unknown'} nodes and ${accepted.at(-1)?.open_windows ?? 'unknown'} open windows.`);
    if (group.probe === 'types') for (const sample of group.samples) for (const check of sample.checks ?? []) lines.push(`- ${cell(check.program)}: checker ${check.checker_ms} ms; click-to-idle ${check.wall_ms.toFixed(2)} ms.`);
  }
  if (report.error) lines.push('', `Harness failure: ${cell(report.error)}`);
  lines.push('', 'Compute reports the largest tested successful loop and first failing size, not an interpolated maximum. A feed CPU/memory limit can precede the five-second deadline. Redraw sizes count every UI component, including controls. A failed window request is not counted as an accepted window. Closing windows preserves server nodes, so cycles eventually reach the node budget.', '');
  return lines.join('\n');
}

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const APP = 'Platform probe app';
const PROGRAM = 'Platform probe';
const semanticText = locator => locator.evaluate(element => [element.textContent,
  ...Array.from(element.querySelectorAll('[aria-label]'), node => node.getAttribute('aria-label'))].join('\n'));

// A previous session count or a matching transcript alone cannot confirm a run.
export function matchProbeResult(book, { id, probe, count }) {
  return book.results.find(row => row.id === id && row.probe === probe
    && ['completed', 'requested', 'error'].includes(row.status)
    && (probe !== 'long' || row.count === count));
}

export function matchesProbeStatus(text, message) {
  return Boolean(message) && String(text ?? '').split(/\r?\n/).some(line => line.trim() === message);
}

async function statusTarget(scope, message) {
  const candidates = scope.getByText(message, { exact: true })
    .or(scope.locator(`[aria-label*=${JSON.stringify(message)}]`));
  for (const target of await candidates.all()) {
    if (matchesProbeStatus(await target.getAttribute('aria-label') || await target.innerText(), message)) return target;
  }
}

// Wheel events over the window's own scroll node reach Flutter's scroll
// controller. DOM scrollIntoView on a clipped semantics label can time out.
async function scrollApp(scope, deltaY) {
  const point = await scope.evaluate(root => {
    const scroll = Array.from(root.querySelectorAll('*')).find(element =>
      Array.from(element.children).some(child => child.tagName.toLowerCase() === 'flt-semantics-scroll-overflow')
      || (/auto|scroll/.test(getComputedStyle(element).overflowY) && element.scrollHeight > element.clientHeight));
    if (!scroll) return null;
    const rect = scroll.getBoundingClientRect(), window = root.getBoundingClientRect();
    const left = Math.max(rect.left, window.left, 0), right = Math.min(rect.right, window.right, innerWidth);
    const top = Math.max(rect.top, window.top, 0), bottom = Math.min(rect.bottom, window.bottom, innerHeight);
    if (right <= left || bottom <= top) return null;
    return { x: (left + right) / 2, y: (top + bottom) / 2, extent: scroll.scrollHeight };
  });
  if (point) {
    await scope.page().mouse.move(point.x, point.y);
    await scope.page().mouse.wheel(0, deltaY ?? -point.extent);
  }
}

export async function revealAppTarget(scope, locate, { top = false, wait = pause } = {}) {
  await scope.scrollIntoViewIfNeeded({ timeout: 2000 });
  if (top) {
    await scrollApp(scope);
    await wait(100);
  }
  for (let attempt = 0; attempt < 10; attempt++) {
    const target = await locate();
    if (target && await target.count()) {
      const delta = await target.evaluate(element => {
        const window = element.closest('[aria-label^="Workbench window "]');
        for (let parent = element.parentElement; parent && parent !== window; parent = parent.parentElement) {
          if (!Array.from(parent.children).some(child => child.tagName.toLowerCase() === 'flt-semantics-scroll-overflow')
            && !/auto|scroll/.test(getComputedStyle(parent).overflowY)) continue;
          const rect = element.getBoundingClientRect(), bounds = parent.getBoundingClientRect();
          if (rect.top < bounds.top || rect.bottom > bounds.bottom) return rect.top - bounds.top;
        }
        return 0;
      });
      if (delta) await scrollApp(scope, delta);
      await wait(100);
      const fresh = await locate();
      if (fresh && await fresh.count() && await fresh.isVisible() && await fresh.evaluate(element => {
        const rect = element.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0 || rect.top < 0 || rect.left < 0 || rect.bottom > innerHeight || rect.right > innerWidth) return false;
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          const style = getComputedStyle(parent), bounds = parent.getBoundingClientRect();
          if ((/hidden|clip|scroll|auto/.test(style.overflowY) && (rect.top < bounds.top - 1 || rect.bottom > bounds.bottom + 1))
            || (/hidden|clip|scroll|auto/.test(style.overflowX) && (rect.left < bounds.left - 1 || rect.right > bounds.right + 1))) return false;
        }
        return true;
      })) return fresh;
    }
    await wait(100);
  }
  throw new Error('App target was not visible after scrolling its window');
}

// Intercept only real browser action requests; preserve the response delivered
// to Flutter. Authorization remains in memory and is never added to evidence.
async function actionTurn(page, { room, threadId, timeoutMs }, trigger) {
  let resolveTurn, rejectTurn;
  const turn = new Promise((resolve, reject) => { resolveTurn = resolve; rejectTurn = reject; });
  turn.catch(() => {});
  const handler = async route => {
    const request = route.request();
    if (!new URL(request.url()).pathname.includes(`/rooms/${room}/agui/${threadId}/`)) return route.fallback();
    try {
      const response = await route.fetch({ timeout: timeoutMs });
      const body = await response.text();
      await route.fulfill({ response, body });
      const events = response.ok() ? parseSSE(body) : [];
      const errors = events.filter(e => e.type === 'RUN_ERROR').map(e => e.message);
      if (response.ok() && !events.some(e => e.type === 'RUN_FINISHED')) errors.push('Action stream ended without RUN_FINISHED');
      resolveTurn({ status: response.status(), error: response.ok() ? errors.join('\n') || undefined : body, events });
    } catch {
      rejectTurn(new Error('Program action transport failed'));
      await route.abort().catch(() => {});
    }
  };
  await page.route('**/agui/**', handler);
  let timer;
  try {
    await trigger();
    return await Promise.race([turn, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('No program action response')), timeoutMs);
    })]);
  } finally {
    clearTimeout(timer);
    await page.unroute('**/agui/**', handler);
  }
}

export async function runProbes({ repository, base, alias }) {
  const started = new Date().toISOString();
  const directory = resolve(repository, 'workbench/docs/evidence/probes', started.replace(/[:.]/g, '-'));
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const report = { started, groups: [] };
  const snapshots = [];
  let browser, page, authorization, download;
  let redact = redactor();
  let raw = null;
  let stage = 'credentials';
  const persist = async () => {
    const safe = value => JSON.stringify(cleanEvidence(value, redact), null, 2) + '\n';
    await writeFile(`${directory}/browser-results.json`, safe(report), { mode: 0o600 });
    await writeFile(`${directory}/app-snapshots.json`, safe(snapshots), { mode: 0o600 });
    if (raw) await writeFile(`${directory}/probe-results.json`, safe(raw), { mode: 0o600 });
    await writeFile(`${directory}/probe-report.md`, reportMarkdown(cleanEvidence(report, redact)), { mode: 0o600 });
  };
  try {
    const credentials = parseCredentials(await readFile(resolve(repository, 'workbench/stack/workbench.env'), 'utf8'));
    redact = redactor(Object.values(credentials));
    const timeoutMs = Number(process.env.WB_RUN_TIMEOUT_MS || 240000);
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) throw new Error('Invalid run timeout');
    stage = 'Chrome login';
    const { openBrowser, freshThread, sendPrompt, performActions } = await import('../lib/browser.mjs');
    const { narrowToExact } = await import('../lib/actions.mjs');
    const { workspaceMatches } = await import('../lib/selectors.mjs');
    const { hasVisibleInk } = await import('../lib/png.mjs');
    ({ browser, page } = await openBrowser(base, credentials));
    const room = 'workbench';
    page.on('request', request => {
      const url = new URL(request.url());
      if (url.origin === new URL(base).origin && url.pathname.includes(`/rooms/${room}/`)) authorization = request.headers().authorization || authorization;
    });
    stage = 'fresh thread and curated publication';
    const threadId = report.threadId = await freshThread(page, base, alias, room);
    const turnOptions = { room, threadId, timeoutMs };
    const opened = await sendPrompt(page, room, 'Open the platform probe.', timeoutMs, threadId);
    if (!opened.completed || opened.runErrors.length || !opened.toolCalls.includes('open_demo')) throw new Error('Curated publication failed');
    const scope = title => page.locator(regionSelector()).locator(`[aria-label="Workbench window ${title}"]`);
    const button = async (name, window = APP) => {
      if (window === APP) return revealAppTarget(scope(APP), () => scope(APP).getByRole('button', { name, exact: true }), { top: true });
      const matches = await narrowToExact(await workspaceMatches(page, { kind: 'role', role: 'button', name, window }), name);
      if (matches.length !== 1) throw new Error(`Missing unique ${window} button ${name}`);
      return matches[0].target;
    };
    const readBook = async () => {
      if (!authorization) throw new Error('No authenticated workdir request observed');
      const url = new URL(`/api/v1/rooms/${room}/threads/${threadId}/workbench/files/read`, base);
      const response = await page.request.post(url.href, { headers: { authorization }, data: { filename: 'probe-results.json' }, timeout: 15000 });
      if (!response.ok()) throw new Error(`Probe file read HTTP ${response.status()}`);
      raw = JSON.parse((await response.json()).text);
      return raw;
    };
    download = readBook;
    const waitIdle = async (title = PROGRAM) => {
      await scope(title).getByRole('button', { name: 'Run', exact: true }).waitFor({ state: 'visible', timeout: 45000 });
      const deadline = performance.now() + 45000;
      while (!await scope(title).getByRole('button', { name: 'Run', exact: true }).isEnabled()) {
        if (performance.now() > deadline) throw new Error('Interpreter did not become idle');
        await pause(20);
      }
    };
    const run = async (title = PROGRAM) => {
      const target = await button('Run', title);
      const start = performance.now();
      const wire = await actionTurn(page, turnOptions, () => target.click());
      await waitIdle(title);
      if (wire.error) throw new Error(`Run refused: ${wire.error}`);
      return performance.now() - start;
    };
    stage = 'initial Run';
    await run();
    await revealAppTarget(scope(APP), () => statusTarget(scope(APP), 'Probe ready'), { top: true });
    await readBook();
    const receipt = async value => {
      // The app, rather than the harness's HTTP client, appends observations.
      await revealAppTarget(scope(APP), () => scope(APP).getByRole('textbox', { name: /Probe receipt/ }), { top: true });
      await performActions(page, [{ kind: 'fill', name: 'Probe receipt', value: JSON.stringify(value), window: APP }]);
      await (await button('Save observation')).click();
      await waitIdle();
      const deadline = performance.now() + 15000;
      while ((await readBook()).results.find(row => row.id === value.id)?.observation?.index !== value.index) {
        if (performance.now() > deadline) throw new Error('Observation was not saved');
        await pause(100);
      }
      const message = raw.message ?? 'Probe ready';
      await revealAppTarget(scope(APP), () => statusTarget(scope(APP), message), { top: true });
    };
    const recordSample = async (probe, result) => {
      let group = report.groups.find(g => g.probe === probe);
      if (!group) report.groups.push(group = { probe, samples: [] });
      group.samples.push(result);
      await persist();
    };
    const sample = async ({ probe, label, index }) => {
      const observation = { index };
      try {
        stage = `${probe} sample ${index + 1}`;
        const before = await readBook();
        const previous = before.results.filter(r => r.probe === 'long').at(-1);
        const id = probe === 'long' && previous ? previous.id : before.results.length + 1;
        Object.assign(observation, { id });
        const expected = { id, probe, count: before.long + 1 };
        const target = await button(label);
        const previousOutput = await semanticText(scope(PROGRAM));
        const start = performance.now();
        let wire;
        const trigger = () => target.click();
        if (['windows', 'cycles', 'types'].includes(probe)) wire = await actionTurn(page, turnOptions, trigger);
        else await trigger();
        const deadline = start + 45000;
        let output = '', row;
        while (performance.now() < deadline) {
          const book = await readBook();
          row = matchProbeResult(book, expected);
          output = await semanticText(scope(PROGRAM));
          if (row || wire?.error || (output !== previousOutput && new RegExp(`Click: ${probe} · error`).test(output))) break;
          await pause(100);
        }
        await waitIdle();
        const book = await readBook();
        row = matchProbeResult(book, expected) ?? book.results.find(r => r.id === id && r.probe === probe);
        Object.assign(observation, { size: row?.size, count: row?.count, program_status: row?.status,
          program_error: row?.error, wall_ms: performance.now() - start });
        let error = wire?.error || row?.error;
        if (row?.status === 'started' && output !== previousOutput && new RegExp(`Click: ${probe} · error`).test(output)) error ||= output;
        if (!error && !matchProbeResult(book, expected)) throw new Error(`No recorded result for ${probe}`);
        if (row?.status === 'error') error ||= 'Program recorded an error';
        Object.assign(observation, { visible_redraw: false, status: error ? 'rejected' : 'completed', error, server_status: wire?.status });
        let visibleStatus;
        if (!error) {
          if (!row.message) throw new Error('Recorded result has no status message');
          visibleStatus = await revealAppTarget(scope(APP), () => statusTarget(scope(APP), row.message), { top: true });
          observation.visible_redraw = true;
        }
        observation.wall_ms = performance.now() - start;
        if (wire) {
          const layout = wire.events.map(e => e.content?.workbench).filter(Boolean).at(-1);
          if (layout?.nodes) {
            observation.server_nodes = layout.nodes.length;
            observation.open_windows = layout.nodes.filter(n => n.kind === 'window' && n.visibility === 'open').length;
          }
        }
        if (visibleStatus && ['redraw', 'charts'].includes(probe)) {
          const paintedTarget = probe === 'charts' ? await revealAppTarget(scope(APP), () =>
            scope(APP).getByRole('img', { name: new RegExp(`Probe ${row.kind === 'bar' ? 'bars' : 'lines'}`) })) : visibleStatus;
          const box = await paintedTarget.boundingBox();
          observation.painted = Boolean(box && hasVisibleInk(await page.screenshot({ clip: box, animations: 'disabled' })));
          if (!observation.painted) {
            throw new Error('Visible semantics had no painted pixels');
          }
          observation.detail = row.kind ? `${row.kind}: ${row.series ?? 1} series` : `${row.size} total UI nodes`;
        }
        if (probe === 'long') {
          observation.count = row?.count ?? before.long;
          if (observation.count !== expected.count) {
            observation.error ||= 'Long-session counter did not advance exactly once';
            observation.status = 'rejected';
          }
        }
        if (probe === 'files') observation.detail = `read ${row?.read_bytes ?? 'not reached'} bytes; exact match ${row?.matches ?? false}`;
        if (/Interpreter state was reset/.test(error ?? '')) await run();
        // One receipt at the end keeps 300 clicks in one uninterrupted session.
        if (probe !== 'long' || index === 299 || observation.error) await receipt({ ...observation, server_rejected: Boolean(wire?.error) });
        if (probe === 'state') {
          let sent;
          const observe = request => {
            if (request.method() === 'POST' && new URL(request.url()).pathname.includes(`/rooms/${room}/agui/${threadId}/`)) sent = request.postDataJSON()?.state?.workbenchApps;
          };
          page.on('request', observe);
          try {
            const reply = await sendPrompt(page, room, 'From the current app snapshot, give the exact length and final 24 characters of largest_field. If absent, say absent. Use only the current snapshot and do not modify the workbench.', timeoutMs, threadId);
            const fields = Object.values(sent ?? {}).map(app => app?.largest_field).filter(v => typeof v === 'string');
            const snapshot = { id, requested_bytes: row?.size, workbenchApps: sent ?? null,
              received_field_bytes: fields.map(v => Buffer.byteLength(v)), reply: reply.finalMessage, completed: reply.completed, errors: reply.runErrors };
            snapshots.push(snapshot);
            observation.detail = `outgoing field bytes: ${snapshot.received_field_bytes.join(',') || 'omitted'}; reply recorded`;
            await persist();
            await receipt({ ...observation, received_field_bytes: snapshot.received_field_bytes, model_reply: reply.finalMessage });
            if (!reply.completed || reply.runErrors.length) process.exitCode = 1;
          } finally { page.off('request', observe); }
        }
        if (probe === 'types' && !error) {
          const checks = observation.checks = [];
          for (const title of [PROGRAM, 'Probe type check 12000']) {
            await performActions(page, [{ kind: 'check', name: 'Type check', window: title }]);
            const wall_ms = await run(title);
            const text = await semanticText(scope(title));
            const match = text.match(/Type check: ([\d.]+) ms\./);
            if (!match) throw new Error(`Missing type-check measurement in ${title}`);
            checks.push({ program: title, checker_ms: Number(match[1]), wall_ms });
            await persist();
            // Untick so later compute/window events do not include the checker.
            await scope(title).getByRole('checkbox', { name: 'Type check', exact: true }).click();
          }
          observation.checks = checks;
          await receipt({ ...observation, checks });
        }
        return observation;
      } catch (error) {
        error.observation = observation;
        throw error;
      }
    };
    report.groups = await driveProbePlan({ sample, onSample: recordSample, afterGroup: async group => {
      Object.assign(report.groups.find(g => g.probe === group.probe), { censored: group.censored });
      if (group.probe === 'windows') {
        // Exclude refused ids; close accepted windows before testing node churn.
        for (const row of group.samples.filter(s => !s.error)) {
          const closed = await actionTurn(page, turnOptions, async () => { await (await button('Close probe windows')).click(); });
          if (closed.error) throw new Error('Probe window close was refused');
          await waitIdle();
        }
      }
      await persist();
      console.log(`Probe ${group.probe}: ${group.samples.length} observations${group.censored ? ' (ceiling not reached)' : ''}`);
    } });
    stage = 'final workdir download';
    await readBook();
    if (report.groups.some(group => group.error || group.samples.some(sample => sample.status === 'harness_error'))) process.exitCode = 1;
  } catch (error) {
    report.error = `During ${stage}: ${String(error?.message ?? 'probe harness failed').split('\n')[0]}`;
    process.exitCode = 1;
  } finally {
    await download?.().catch(() => {});
    await browser?.close().catch(() => { process.exitCode = 1; });
    authorization = undefined;
    await persist();
  }
  console.log(`Report: ${directory}/probe-report.md`);
  return report;
}

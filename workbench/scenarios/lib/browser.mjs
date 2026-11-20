import { chromium } from 'playwright';
import { assertionLabel, regionSelector, parseSSE, summarizeEvents } from './core.mjs';
import { hasVisibleInk } from './png.mjs';
import { workspaceMatches } from './selectors.mjs';
export { workspaceMatches } from './selectors.mjs';

const exact = name => new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
export const composer = page => page.getByRole('textbox', { name: 'Type a message...', exact: true });

export async function semantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  // Flutter keeps the placeholder off-screen, so a pointer click never lands.
  if (await placeholder.count()) await placeholder.first().evaluate(element => element.click());
}

export async function openBrowser(base, credentials) {
  const browser = await chromium.launch({
    channel: process.env.WB_BROWSER_CHANNEL || 'chrome', headless: true,
    args: ['--enable-webgl', '--use-gl=angle', '--use-angle=swiftshader',
      `--host-resolver-rules=MAP ${new URL(base).hostname} 127.0.0.1`],
  });
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 2400, height: 1800 } });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  // No console, HTTP, trace, video, cookie, or storage-state logging.
  let step = 'open';
  try {
    await page.goto(`${base}/#/`, { waitUntil: 'domcontentloaded' });
    const deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      await semantics(page);
      if (new URL(page.url()).hash.startsWith('#/lobby')) return { browser, context, page };
      const username = page.locator('#username-textfield');
      const password = page.locator('input[type="password"]');
      const consent = page.locator('#openid-consent-accept');
      if (await username.isVisible()) {
        step = 'username'; await username.fill(credentials.WB_ADMIN_USER);
        await password.fill(credentials.WB_ADMIN_PASSWORD);
        await page.locator('#sign-in-button').click();
        await pause(1000);
      } else if (await consent.isVisible()) {
        step = 'consent'; await consent.click();
      } else if (await password.isVisible()) {
        await password.fill(credentials.WB_ADMIN_PASSWORD);
        await page.getByRole('button', { name: /submit/i }).click();
      } else {
        const backend = page.getByRole('textbox', { name: 'Backend URL', exact: true });
        const connect = page.getByRole('button', { name: 'Connect', exact: true });
        const provider = page.getByRole('button', { name: /authelia|sign in|continue with/i }).first();
        const providerText = page.getByText(/^authelia$/i).first();
        if (await backend.isVisible()) {
          step = 'backend'; await backend.fill(base);
          await connect.click();
        } else if (await provider.isVisible()) {
          step = 'provider'; await provider.click();
        } else if (await providerText.isVisible()) {
          await providerText.click();
        }
      }
      await pause(400);
    }
    throw new Error(`Sign-in timed out after step ${step}`);
  } catch (error) {
    await browser.close();
    // Name the step and error class only. Messages can hold auth URLs.
    throw new Error(`Sign-in failed at step ${step} (${error?.name ?? 'Error'}), no authentication evidence was saved`);
  }
}

export async function openThread(page, base, alias, room, threadId) {
  const route = `/#/room/${encodeURIComponent(alias)}/${encodeURIComponent(room)}${threadId ? `/thread/${encodeURIComponent(threadId)}` : ''}`;
  await page.goto(`${base}${route}`, { waitUntil: 'domcontentloaded' });
  await waitForComposer(page);
}

export async function waitForComposer(page) {
  const deadline = Date.now() + 45000;
  while (Date.now() < deadline) {
    await semantics(page);
    if (await composer(page).isVisible()) return;
    await pause(250);
  }
  throw new Error('Room composer is unavailable');
}

export async function freshThread(page, base, alias, room, recordThread) {
  await openThread(page, base, alias, room);
  const created = page.waitForResponse(response => response.request().method() === 'POST'
    && new URL(response.url()).pathname.endsWith(`/rooms/${room}/agui`));
  created.catch(() => {});
  await page.getByRole('button', { name: 'New', exact: true }).click();
  const response = await created;
  if (!response.ok()) throw new Error(`Thread creation HTTP ${response.status()}`);
  const { thread_id: threadId } = await response.json();
  if (!/^[0-9a-f-]{36}$/.test(threadId)) throw new Error('Thread creation returned no valid thread id');
  recordThread?.(room, threadId);
  await page.waitForURL(url => url.hash.endsWith(`/thread/${threadId}`));
  await waitForComposer(page);
  return threadId;
}

export async function sendPrompt(page, room, prompt, timeoutMs, threadId) {
  // Observe the actual request made by Flutter. No synthetic agent API call.
  const responsePromise = page.waitForResponse(response => {
    const path = new URL(response.url()).pathname;
    return response.request().method() === 'POST' && path.includes(`/rooms/${room}/agui/${threadId}/`) && path.split('/').length >= 8;
  }, { timeout: timeoutMs });
  // Install rejection handling before any UI action can fail.
  responsePromise.catch(() => {});
  await composer(page).fill(prompt);
  await composer(page).press('Enter');
  const response = await responsePromise;
  if (!response.ok()) throw new Error(`Agent HTTP ${response.status()}`);
  const body = await bounded(response.text(), timeoutMs, 'Agent stream timed out');
  const events = parseSSE(body);
  const summary = summarizeEvents(events);
  const parts = new URL(response.url()).pathname.split('/');
  summary.threadId = parts.at(-2);
  if (!summary.completed && summary.runErrors.length === 0) throw new Error('Agent stream ended without RUN_FINISHED');
  await waitForComposer(page);
  await pause(500);
  return summary;
}

async function bounded(promise, timeoutMs, message) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(message)), timeoutMs);
    })]);
  } finally {
    clearTimeout(timer);
  }
}


export async function assertCanvas(page, assertions, timeoutMs = 12000) {
  const results = [];
  for (const a of assertions) {
    const deadline = Date.now() + timeoutMs;
    let matches = [];
    let pass = false;
    let painted = 0;
    do {
      matches = await workspaceMatches(page, a);
      pass = a.absent ? matches.length === 0 : a.count ? matches.length === a.count : matches.length > 0;
      painted = 0;
      if (pass && !a.absent) {
        for (const { box } of matches) {
          // A populated accessibility tree can survive a blank paint. Check
          // the pixels behind each semantic bound as well as names and roles.
          const png = await page.screenshot({ clip: box, animations: 'disabled' });
          if (hasVisibleInk(png)) painted++;
        }
        pass = painted === matches.length;
      }
      // Absence gets a settling interval, avoiding a pass during hydration.
      if (a.absent) {
        await pause(600);
        matches = await workspaceMatches(page, a);
        pass = matches.length === 0;
      }
      if (pass) break;
      await pause(250);
    } while (Date.now() < deadline);
    const bounds = matches.map(m => `x=${Math.round(m.box.x)}, y=${Math.round(m.box.y)}, width=${Math.round(m.box.width)}, height=${Math.round(m.box.height)}`).join(' | ');
    results.push({
      label: assertionLabel(a),
      pass,
      detail: `${matches.length} visible canvas matches, ${painted} nonblank pixel regions${bounds ? `, ${bounds}` : ''}`,
    });
  }
  return results;
}

export async function performActions(page, actions = []) {
  for (const action of actions) {
    const assertion = { kind: 'role', region: 'workspace', ...action };
    const deadline = Date.now() + 15000;
    let matches = [];
    while (Date.now() < deadline) {
      matches = await workspaceMatches(page, assertion);
      if (matches.length) break;
      await pause(250);
    }
    if (matches.length !== 1) throw new Error(`Action needs one visible workspace ${action.role}: ${action.name}`);
    await matches[0].target.click();
    await pause(600);
  }
}

export async function visibleErrors(page) {
  const pattern = /Workbench is unavailable|Run failed|Run error|Failed to (?:load|send)|Server error|VALIDATION_FAILED|Traceback|\b(?:TypeError|ValueError|RuntimeError):/i;
  const matches = page.getByText(pattern);
  const errors = [];
  for (let i = 0; i < await matches.count(); i++) {
    if (await matches.nth(i).isVisible()) errors.push((await matches.nth(i).innerText()).slice(0, 2000));
  }
  const banner = page.getByRole('button', { name: 'Copy error', exact: true });
  for (let i = 0; i < await banner.count(); i++) {
    if (await banner.nth(i).isVisible()) errors.push('Visible error banner with Copy error control');
  }
  return [...new Set(errors)];
}

export async function timelineTools(page, names) {
  const headers = page.getByText(/^\d+ events?$/);
  for (let i = 0; i < await headers.count(); i++) {
    const header = headers.nth(i);
    if (await header.isVisible()) await header.click();
  }
  const visible = [];
  const chat = page.locator(regionSelector('chat'));
  for (const name of new Set(names)) {
    const labels = chat.getByText(exact(name));
    for (let i = 0; i < await labels.count(); i++) {
      const label = labels.nth(i);
      const box = await label.boundingBox();
      if (await label.isVisible() && box) {
        visible.push(name);
        break;
      }
    }
  }
  return visible;
}

export async function screenshot(page, path, credentials, expected = {}) {
  // Never capture a sign-in/callback page. Flutter paints text on a canvas,
  // so Playwright masks the semantic bounds over the actual screenshot.
  if (!new URL(page.url()).hash.startsWith('#/room/')) throw new Error('Screenshot requires an authenticated room');
  const route = new URL(page.url()).hash;
  if ((expected.threadId && !route.endsWith(`/thread/${expected.threadId}`))
    || (expected.room && !route.includes(`/${expected.room}/thread/`))) throw new Error('Screenshot route does not match this case');
  const mask = Object.values(credentials).flatMap(value => [page.getByText(value, { exact: false }), page.getByRole('textbox', { name: value, exact: false })]);
  mask.push(page.getByText(/\bBearer\s+\S+|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|(?:password|token|secret|api[_-]?key)\s*[:=]/i));
  await page.screenshot({ path, fullPage: false, mask, maskColor: '#111111', animations: 'disabled' });
}

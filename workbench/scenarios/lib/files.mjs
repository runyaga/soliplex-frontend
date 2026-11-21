import { assertionLabel } from './core.mjs';

// Only a live request's in-memory authorization is used. Never put it in evidence.
export async function assertSavedFile(page, base, room, threadId, assertion, authorization) {
  const label = assertionLabel(assertion);
  if (!authorization) return { label, pass: false, detail: 'No authenticated request observed' };
  const url = new URL(`/api/v1/rooms/${encodeURIComponent(room)}/threads/${encodeURIComponent(threadId)}/workbench/files/read`, base);
  const response = await page.request.post(url.href, {
    headers: { authorization }, data: { filename: assertion.filename }, timeout: 15000,
  });
  if (!response.ok()) return { label, pass: false, detail: 'Saved file could not be read' };
  const { text } = await response.json();
  return { label, pass: typeof text === 'string' && text.includes(assertion.includes), detail: `Read ${assertion.filename} from authenticated thread workdir` };
}

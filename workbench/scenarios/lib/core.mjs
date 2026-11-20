import { readFile, writeFile } from 'node:fs/promises';

export function parseCredentials(text) {
  const values = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*(?:export\s+)?(WB_ADMIN_(?:USER|PASSWORD|EMAIL))=(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    if (value.startsWith("'")) {
      if (!value.endsWith("'")) throw new Error('Invalid credential quoting');
      value = value.slice(1, -1);
    } else if (value.startsWith('"')) {
      if (!value.endsWith('"') || /[$`]/.test(value)) throw new Error('Use literal credentials');
      value = value.slice(1, -1).replace(/\\([\\"$`])/g, '$1');
    } else {
      value = value.replace(/\s+#.*$/, '').trim();
      if (/[$`\s\\]/.test(value)) throw new Error('Quote literal credentials');
    }
    if (!value || /[\r\n\0]/.test(value)) throw new Error('Missing credential');
    values[match[1]] = value;
  }
  if (!values.WB_ADMIN_USER || !values.WB_ADMIN_PASSWORD || !values.WB_ADMIN_EMAIL) {
    throw new Error('Missing workbench credentials');
  }
  return values;
}

export function redactor(values = []) {
  const literals = values.filter(Boolean).flatMap(value => [value, encodeURIComponent(value)])
    .sort((a, b) => b.length - a.length);
  return value => {
    let text = String(value ?? '');
    for (const literal of literals) text = text.split(literal).join('[redacted]');
    return text
      .replace(/\bBearer\s+[^\s"<>]+/gi, 'Bearer [redacted]')
      .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[redacted]')
      .replace(/((?:password|token|secret|authorization|cookie|api[_-]?key)\s*["']?\s*[:=]\s*)[^\s,<>]+/gi, '$1[redacted]');
  };
}

export function cleanEvidence(value, redact) {
  if (typeof value === 'string') return redact(value);
  if (Array.isArray(value)) return value.map(item => cleanEvidence(item, redact));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, cleanEvidence(item, redact)]));
  return value;
}

const regions = new Set(['workspace', 'left', 'canvas', 'right', 'tray']);
export function validateCases(data, { prompts = false } = {}) {
  if (!Array.isArray(data) || data.length === 0) throw new Error('Expected nonempty case list');
  const ids = new Set();
  for (const item of data) {
    if (!item || typeof item.id !== 'string' || !/^[a-z][a-z0-9_]*$/.test(item.id) || ids.has(item.id)) throw new Error('Invalid or duplicate case id');
    ids.add(item.id);
    if (prompts && (typeof item.prompt !== 'string' || !item.prompt.trim())) throw new Error('Missing prompt');
    if (item.setup && (!Array.isArray(item.setup) || item.setup.some(p => typeof p !== 'string' || !p.trim()))) throw new Error('Invalid setup');
    if (!Array.isArray(item.assertions) || item.assertions.length === 0) throw new Error('Missing canvas assertions');
    if (item.assertions.every(a => a?.absent)) throw new Error('A case must require visible content');
    if (item.reload !== undefined && typeof item.reload !== 'boolean') throw new Error('Invalid reload flag');
    for (const a of item.assertions) {
      if (!a || !['text', 'role', 'source'].includes(a.kind) || typeof a.name !== 'string' || !a.name.trim() || !regions.has(a.region ?? 'workspace')) throw new Error('Invalid assertion');
      if (a.kind === 'role' && !['button', 'textbox', 'tab', 'checkbox', 'img'].includes(a.role)) throw new Error('Invalid accessible role');
      if (a.kind === 'source' && (typeof a.includes !== 'string' || !a.includes)) throw new Error('Missing source expectation');
      if (a.absent !== undefined && typeof a.absent !== 'boolean') throw new Error('Invalid absence assertion');
      if (a.count !== undefined && (!Number.isInteger(a.count) || a.count < 1 || a.absent)) throw new Error('Invalid count');
    }
    for (const action of item.actions ?? []) {
      if (!['button', 'tab'].includes(action.role) || typeof action.name !== 'string' || !action.name) throw new Error('Invalid action');
    }
    if (item.setup_assertions) validateCases([{ id: 'setup', assertions: item.setup_assertions }]);
  }
  return data;
}

export async function loadCases(path, options) {
  // JSON is a YAML 1.2 subset. No package download or unsafe YAML constructors.
  return validateCases(JSON.parse(await readFile(path, 'utf8')), options);
}

export function parseSSE(body) {
  const events = [];
  for (const block of body.replace(/\r\n/g, '\n').split(/\n\n+/)) {
    const data = block.split('\n').filter(line => line.startsWith('data:'))
      .map(line => line.slice(5).trimStart()).join('\n');
    if (data && data !== '[DONE]') events.push(JSON.parse(data));
  }
  return events;
}

export function summarizeEvents(events) {
  const messages = new Map();
  const tools = [];
  const errors = [];
  for (const event of events) {
    if (event.type === 'TEXT_MESSAGE_START') messages.set(event.messageId, { role: event.role, text: '' });
    if (event.type === 'TEXT_MESSAGE_CONTENT') {
      const message = messages.get(event.messageId);
      if (message) message.text += event.delta ?? '';
    }
    if (event.type === 'TOOL_CALL_START') tools.push(event.toolCallName);
    if (event.type === 'RUN_ERROR') errors.push(event.message || 'Run error');
  }
  return {
    completed: events.some(event => event.type === 'RUN_FINISHED'),
    finalMessage: [...messages.values()].filter(m => m.role === 'assistant').at(-1)?.text ?? '',
    toolCalls: tools,
    runErrors: errors,
  };
}

export function inRegion(box, chat, viewport, region = 'workspace') {
  if (!box || box.width < 2 || box.height < 2 || box.y < 0 || box.y + box.height > viewport.height + 2 || box.x < 0 || box.x + box.width > viewport.width + 2) return false;
  const middle = box.x + box.width / 2;
  const left = middle < chat.x - 12;
  const right = middle > chat.x + chat.width + 70;
  const tray = box.y > chat.y + chat.height + 25;
  if (region === 'left') return left;
  if (region === 'right') return right && middle > chat.x + chat.width + (viewport.width - chat.x - chat.width) * 0.72;
  if (region === 'canvas') return right && !tray;
  if (region === 'tray') return tray;
  return left || right || tray;
}

export function assertionLabel(a) {
  return `${a.absent ? 'Absent ' : ''}${a.kind === 'role' ? a.role : a.kind} ${a.name} in ${a.region ?? 'workspace'}${a.includes ? ` containing ${a.includes}` : ''}${a.count ? ` count ${a.count}` : ''}`;
}

export function failedAssertions(assertions, reason) {
  return assertions.map(a => ({ label: assertionLabel(a), pass: false, detail: reason }));
}

const cell = value => String(value ?? '').replace(/—/g, ' - ').replace(/;/g, ',').replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
const paragraph = value => cell(String(value ?? '').replace(/`/g, "'").replace(/</g, '‹').replace(/>/g, '›'))
  .replace(/\bhttps?:\/\/[^\s<>|]+/g, url => `<${url}>`);
export function renderReport(results, timestamp, redact = redactor()) {
  results = cleanEvidence(results, redact);
  const lines = [
    '# Workbench scenario evidence', '',
    '| Run | Value |', '| --- | --- |',
    `| UTC | ${cell(timestamp)} |`,
    '| Scope | I recorded outcomes for the selected suites and their canvas assertions |',
    '', '| Scenario or prompt | Model | Result | Evidence |', '| --- | --- | --- | --- |',
    ...results.map((r, i) => `| ${cell(r.id)} | ${cell(r.model)} | ${r.pass ? 'PASS' : 'FAIL'} | [Details](#case-${i + 1})${r.screenshot ? `, [Screenshot](${r.screenshot})` : ''} |`),
  ];
  results.forEach((r, i) => {
    lines.push('', `## Case ${i + 1}`, '', '| Field | Value |', '| --- | --- |',
      `| Id | ${cell(r.id)} |`, `| Model | ${cell(r.model)} |`, `| Thread | ${cell(r.threadId || 'Not created')} |`,
      `| Run errors | ${paragraph((r.runErrors ?? []).join('\n') || 'None recorded')} |`,
      `| Harness error | ${paragraph(r.error || 'None')} |`,
      `| Final assistant message | ${paragraph(r.finalMessage || 'None recorded')} |`,
      `| Timeline tool calls | ${paragraph((r.timelineTools ?? []).join(', ') || 'None visible')} |`,
      `| Run tool calls | ${paragraph((r.toolCalls ?? []).join(', ') || 'None recorded')} |`,
      `| Screenshot | ${r.screenshot ? `[Open](${r.screenshot})` : 'Not captured'} |`,
      '', '| Assertion | Result | Evidence |', '| --- | --- | --- |',
      ...(r.assertions?.length ? r.assertions.map(a => `| ${paragraph(a.label)} | ${a.pass ? 'PASS' : 'FAIL'} | ${paragraph(a.detail || '')} |`) : ['| Suite reached the canvas | FAIL | Setup failed |']),
    );
  });
  return redact(`${lines.join('\n')}\n`);
}

export async function writeReport(directory, results, timestamp, redact) {
  await writeFile(`${directory}/report.md`, renderReport(results, timestamp, redact), { mode: 0o600 });
  // Persist only the bounded, explicitly selected evidence. No headers or storage state.
  await writeFile(`${directory}/results.json`, JSON.stringify(cleanEvidence(results, redact), null, 2) + '\n', { mode: 0o600 });
}

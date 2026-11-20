import { csvCell } from './csv.mjs';
import { readFile, writeFile } from 'node:fs/promises';
import { isDeepStrictEqual } from 'node:util';

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
const validWindow = value => value === undefined || (typeof value === 'string' && value.trim().length > 0 && value.length <= 80);
export function replyExpectation(includes) {
  if (typeof includes === 'string' && includes.trim()) return includes;
  const args = includes?.pow;
  if (!includes || Object.keys(includes).length !== 1 || !Array.isArray(args) || args.length !== 3 || args.some(n => !Number.isSafeInteger(n) || n < 0) || args[2] === 0) throw new Error('Invalid reply expectation');
  let [base, exponent, modulus] = args.map(BigInt);
  let value = 1n % modulus;
  base %= modulus;
  while (exponent) {
    if (exponent & 1n) value = value * base % modulus;
    base = base * base % modulus;
    exponent >>= 1n;
  }
  return String(value);
}

export function validateCases(data, { prompts = false } = {}) {
  if (!Array.isArray(data) || data.length === 0) throw new Error('Expected nonempty case list');
  const ids = new Set();
  for (const item of data) {
    if (!item || typeof item.id !== 'string' || !/^[a-z][a-z0-9_]*$/.test(item.id) || ids.has(item.id)) throw new Error('Invalid or duplicate case id');
    ids.add(item.id);
    if (prompts && (typeof item.prompt !== 'string' || !item.prompt.trim())) throw new Error('Missing prompt');
    if (item.setup && (!Array.isArray(item.setup) || item.setup.some(p => typeof p !== 'string' || !p.trim()))) throw new Error('Invalid setup');
    if (item.followup !== undefined && (!prompts || !Array.isArray(item.followup) || !item.followup.length || item.followup.some(p => typeof p !== 'string' || !p.trim()))) throw new Error('Invalid followup');
    if (item.expectFail !== undefined && (!prompts || typeof item.expectFail !== 'string' || !item.expectFail.trim())) throw new Error('Invalid expected failure reason');
    if (!Array.isArray(item.assertions) || item.assertions.length === 0) throw new Error('Missing canvas assertions');
    if (item.assertions.every(a => a?.absent)) throw new Error('A case must require visible content');
    if (item.walkthrough !== undefined && (!prompts || typeof item.walkthrough !== 'boolean')) throw new Error('Invalid walkthrough flag');
    if (item.reload !== undefined && typeof item.reload !== 'boolean') throw new Error('Invalid reload flag');
    for (const a of item.assertions) {
      if (a?.kind === 'reply') {
        if (!prompts || ['region', 'name', 'absent', 'count', 'role'].some(key => key in a)) throw new Error('Invalid reply assertion');
        replyExpectation(a.includes);
        continue;
      }
      if (a?.kind === 'csv') {
        if (!prompts || typeof a.filename !== 'string' || !/^[a-z0-9-]+\.csv$/.test(a.filename) || !a.values || typeof a.values !== 'object' || Array.isArray(a.values) || !Object.keys(a.values).length) throw new Error('Invalid CSV assertion');
        continue;
      }
      if (a?.kind === 'submission') {
        const intake = a.name === 'workbench_intake' && typeof a.context?.question === 'string' && Array.isArray(a.context.districts) && a.context.districts.every(d => ['north', 'south'].includes(d)) && a.context.acknowledged === true;
        const custom = a.name === 'workbench_form' && typeof a.context?.title === 'string' && a.context.title.trim() && a.context.values && typeof a.context.values === 'object' && !Array.isArray(a.context.values);
        if (!prompts || !(intake || custom)) throw new Error('Invalid submission assertion');
        continue;
      }
      if (!a || !['text', 'role', 'source'].includes(a.kind) || typeof a.name !== 'string' || !a.name.trim() || !regions.has(a.region ?? 'workspace')) throw new Error('Invalid assertion');
      if (a.initialViewport !== undefined && typeof a.initialViewport !== 'boolean') throw new Error('Invalid initial viewport assertion');
      if (!validWindow(a.window)) throw new Error('Invalid assertion window');
      if (a.kind === 'role' && !['button', 'textbox', 'tab', 'checkbox', 'radio', 'img', 'group'].includes(a.role)) throw new Error('Invalid accessible role');
      if (a.kind === 'source' && (typeof a.includes !== 'string' || !a.includes)) throw new Error('Missing source expectation');
      if (a.absent !== undefined && typeof a.absent !== 'boolean') throw new Error('Invalid absence assertion');
      if (a.count !== undefined && (!Number.isInteger(a.count) || a.count < 1 || a.absent)) throw new Error('Invalid count');
    }
    if (item.actions !== undefined && !Array.isArray(item.actions)) throw new Error('Invalid actions');
    for (const action of item.actions ?? []) {
      const kind = action?.kind ?? 'click';
      const role = action?.role ?? ({ run_program: 'button', fill: 'textbox', check: 'checkbox', select: 'button', choose: 'button' })[kind];
      if (!['click', 'fill', 'select', 'choose', 'check', 'run_program'].includes(kind) || typeof action.name !== 'string' || !action.name.trim() || !regions.has(action.region ?? 'workspace')) throw new Error('Invalid action');
      if (!validWindow(action.window)) throw new Error('Invalid action window');
      if ((kind === 'run_program' && role !== 'button') || (kind === 'click' && !['button', 'tab'].includes(role)) || (kind === 'fill' && role !== 'textbox') || (kind === 'check' && role !== 'checkbox') || (['select', 'choose'].includes(kind) && !['button', 'checkbox', 'radio', 'option'].includes(role))) throw new Error('Invalid action role');
      if (kind === 'run_program' && (!prompts || typeof action.expectRepair !== 'boolean')) throw new Error('Invalid program repair expectation');
      if (kind === 'fill' && typeof action.value !== 'string') throw new Error('Missing fill value');
      if (action.awaitTurn !== undefined && (typeof action.awaitTurn !== 'boolean' || kind !== 'click')) throw new Error('Invalid awaitTurn flag');
      if (action.assertions !== undefined) validateCases([{ id: 'action', assertions: action.assertions }]);
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

export function regionSelector(region = 'workspace') {
  const roles = region === 'workspace' ? ['left', 'right', 'canvas', 'tray'] : [region];
  if (roles.some(role => !['chat', 'left', 'right', 'canvas', 'tray'].includes(role))) throw new Error('Unknown workbench region');
  return roles.map(role => `[aria-label="Workbench region ${role}"]`).join(', ');
}

export function assertionLabel(a) {
  if (a.kind === 'reply') return `Latest assistant reply containing ${replyExpectation(a.includes)}`;
  if (a.kind === 'csv') return `Public workdir CSV ${a.filename} contains submitted values`;
  if (a.kind === 'submission') return `Run input contains ${a.name} submission`;
  return `${a.absent ? 'Absent ' : ''}${a.kind === 'role' ? a.role : a.kind} ${a.name} in ${a.region ?? 'workspace'}${a.window ? ` window ${a.window}` : ''}${a.includes ? ` containing ${a.includes}` : ''}${a.count ? ` count ${a.count}` : ''}`;
}

export function assertTurn(a, turn) {
  if (a.kind === 'csv') {
    const csv = turn?.savedCsv;
    const matches = csv?.filename === a.filename && csv.rowCount > 0 &&
      csv.submissionId && csv.lastRow.submission_id === csvCell(csv.submissionId) &&
      !Number.isNaN(Date.parse(csv.lastRow.submitted_at)) &&
      // The model names the fields, so column case varies between runs.
      Object.entries(a.values).every(([key, value]) => {
        const column = Object.keys(csv.lastRow).find(name => name.toLowerCase() === key.toLowerCase());
        return column !== undefined && csv.lastRow[column] === csvCell(value);
      });
    return { label: assertionLabel(a), pass: Boolean(turn?.completed && !turn.runErrors?.length && matches), detail: csv ? `${csv.filename}: ${csv.rowCount} rows` : 'No downloaded CSV' };
  }
  if (a.kind === 'reply') return {
    label: assertionLabel(a),
    pass: Boolean(turn?.completed && !turn.runErrors?.length && turn.finalMessage?.toLowerCase().includes(replyExpectation(a.includes).toLowerCase())),
    detail: turn?.finalMessage || 'No captured assistant reply',
  };
  if (a.kind === 'submission') {
    // The model names custom form fields, so compare their keys case-insensitively.
    const lowerKeys = values => Object.fromEntries(Object.entries(values ?? {}).map(([key, value]) => [key.toLowerCase(), value]));
    const matches = (turn?.submissions ?? []).filter(s => s.name === a.name && (a.name === 'workbench_form'
      ? isDeepStrictEqual({ title: s.context.title, values: lowerKeys(s.context.values) }, { title: a.context.title, values: lowerKeys(a.context.values) })
      : isDeepStrictEqual(s.context, a.context)));
    return { label: assertionLabel(a), pass: Boolean(turn?.completed && turn.actionName === (a.name === 'workbench_form' ? 'submit_form' : 'submit_intake') && !turn.runErrors?.length && matches.length === 1), detail: `${matches.length} matching submissions in persisted run input, RUN_FINISHED=${Boolean(turn?.completed)}` };
  }
  throw new Error('Unknown turn assertion');
}

// Persist only assertion data from paired synthetic results, never the full input.
export function intakeSubmissions(input) {
  const messages = input?.messages ?? [];
  const calls = new Map(messages.flatMap(m => (m.toolCalls ?? []).filter(c => ['workbench_intake', 'workbench_form'].includes(c.function?.name)).map(c => [c.id, c.function.name])));
  return messages.filter(m => m.role === 'tool' && calls.has(m.toolCallId)).flatMap(m => {
    let result;
    try { result = JSON.parse(m.content); } catch { return []; }
    if (result.kind !== 'untrusted_user_submitted_data' || !result.context) return [];
    const name = calls.get(m.toolCallId);
    if (name === 'workbench_form') {
      const { surfaceId, title, values } = result.context;
      if (result.actionSchemaVersion !== 'form.submit@1' || typeof surfaceId !== 'string' || typeof title !== 'string' || !values || typeof values !== 'object' || Array.isArray(values)) return [];
      return [{ name, context: { surfaceId, title, values } }];
    }
    if (result.actionSchemaVersion !== 'intake.submit@1') return [];
    const { question, districts, acknowledged } = result.context;
    return [{ name, context: { question, districts, acknowledged } }];
  });
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
      `| Expected failure reason | ${paragraph(r.expectFail || 'None')} |`,
      `| Unexpected pass | ${r.unexpectedPass ? 'Yes' : 'No'} |`,
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

export async function cleanupCreatedThreads(threads, remove, keep = process.env.WB_KEEP_THREADS === '1') {
  if (!keep && threads.length) await remove(threads);
}

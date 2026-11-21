import test from 'node:test';
import assert from 'node:assert/strict';
import { validateCases } from '../lib/core.mjs';
import { assertSavedFile } from '../lib/files.mjs';

const assertion = { kind: 'file', filename: 'notes.md', includes: 'Keep these notes' };
test('saved file assertions validate names and require real authenticated content', async () => {
  assert.doesNotThrow(() => validateCases([{ id: 'notes', prompt: 'Notes', assertions: [assertion] }], { prompts: true }));
  for (const filename of ['../notes.md', '/notes.md', '.notes.md', 'notes.py']) {
    assert.throws(() => validateCases([{ id: 'notes', prompt: 'Notes', assertions: [{ ...assertion, filename }] }], { prompts: true }));
  }
  let observed;
  const page = { request: { post: async (url, options) => {
    observed = { url, options };
    return { ok: () => true, json: async () => ({ text: 'Keep these notes' }) };
  } } };
  assert.equal((await assertSavedFile(page, 'https://example.test', 'room', 'thread', assertion, 'Bearer memory-only')).pass, true);
  assert.equal(observed.options.headers.authorization, 'Bearer memory-only');
  assert.match(observed.url, /rooms\/room\/threads\/thread\/workbench\/files\/read$/);
  assert.equal((await assertSavedFile(page, 'https://example.test', 'room', 'thread', { ...assertion, includes: 'missing' }, 'Bearer memory-only')).pass, false);
  assert.equal((await assertSavedFile(page, 'https://example.test', 'room', 'thread', assertion)).pass, false);
});

test('reply exclusions distinguish completed and unfinished tasks', async () => {
  const { assertTurn } = await import('../lib/core.mjs');
  const expected = { kind: 'reply', includes: 'Call Sam', excludes: 'Buy tea' };
  assert.equal(assertTurn(expected, { completed: true, runErrors: [], finalMessage: 'Call Sam' }).pass, true);
  assert.equal(assertTurn(expected, { completed: true, runErrors: [], finalMessage: 'Buy tea and Call Sam' }).pass, false);
});

test('every new suggestion has a real Run, edits and a saved file or model answer', async () => {
  const { readFile } = await import('node:fs/promises');
  const cases = JSON.parse(await readFile(new URL('../model/prompts.yaml', import.meta.url), 'utf8'));
  for (const id of ['team_survey_live_results', 'notes_that_save', 'todo_current_state', 'pipeline_saved_csv']) {
    const item = cases.find(item => item.id === id);
    assert.ok(item.actions.some(action => action.name === 'Run' && action.awaitTurn));
    assert.ok(item.actions.some(action => action.kind === 'fill'));
    assert.ok(item.assertions.some(assertion => ['file', 'reply'].includes(assertion.kind)));
  }
  const survey = cases.find(item => item.id === 'team_survey_live_results');
  assert.ok(survey.actions.some(action => action.name === 'Refresh' && action.assertions.some(a => a.name === 'Bar Blue: 1')));
  const todo = cases.find(item => item.id === 'todo_current_state');
  assert.ok(todo.actions.some(action => action.name === 'Done Buy tea'));
  assert.ok(todo.actions.some(action => action.name === 'Remove Discard me'));
});

test('survey and pipeline selectors match the rendered catalog', async () => {
  const { readFile } = await import('node:fs/promises');
  const cases = JSON.parse(await readFile(new URL('../model/prompts.yaml', import.meta.url), 'utf8'));
  const survey = cases.find(item => item.id === 'team_survey_live_results');
  assert.equal(survey.actions.find(a => a.kind === 'fill').name, 'Name *');
  const healing = cases.find(item => item.id === 'two_stage_healing_pipeline');
  const repairedRun = healing.actions.find(a => a.kind === 'run_program');
  assert.equal(repairedRun.expectRepair, true);
  assert.equal(repairedRun.expectRepairs, 2);
  assert.ok(repairedRun.assertions.some(a => a.kind === 'text' && a.name === 'Clean monthly sales'));
  const pipeline = cases.find(item => item.id === 'pipeline_saved_csv');
  assert.ok(pipeline.assertions.some(a => a.kind === 'text' && a.name === 'Monthly sales'));
});

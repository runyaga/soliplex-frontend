import test from 'node:test';
import assert from 'node:assert/strict';
import { parseScenarioArgs } from '../lib/options.mjs';
import { driveProbePlan, probePlan, reportMarkdown } from '../probes/run_probes.mjs';

test('probes are opt-in and cannot enter a normal or combined suite', () => {
  assert.equal(parseScenarioArgs(['--probes']).probes, true);
  assert.deepEqual(parseScenarioArgs(['--all']), { deterministic: true, models: true, probes: false });
  assert.equal(parseScenarioArgs(['--help']), null);
  for (const args of [[], ['--probe'], ['--probes', '--all'], ['--models', '--probes'], ['--probes', '--probes']]) assert.throws(() => parseScenarioArgs(args));
});

test('driver stops at measured limits, continues after rejection, and sends 300 distinct session clicks', async () => {
  const calls = [], finished = [];
  const groups = await driveProbePlan({
    sample: async input => {
      calls.push(input);
      return { index: input.index, wall_ms: input.index + 0.25,
        error: ['compute', 'windows', 'cycles'].includes(input.probe) && input.index === 2 ? 'actual boundary error' : undefined };
    },
    afterGroup: async group => finished.push(group.probe),
  });
  assert.deepEqual(finished, probePlan.map(([probe]) => probe));
  assert.equal(calls.filter(c => c.probe === 'long').length, 300);
  assert.deepEqual(calls.filter(c => c.probe === 'compute').map(c => c.index), [0, 1, 2]);
  assert.equal(groups.find(g => g.probe === 'files').samples.length, 4);
  assert.equal(groups.find(g => g.probe === 'redraw').samples.length, 5);
  assert.equal(groups.find(g => g.probe === 'compute').censored, false);
});

test('unreached boundaries are censored and reports keep measured errors', async () => {
  const groups = await driveProbePlan({ sample: async ({ index }) => ({ index, wall_ms: 1.25, status: 'completed' }) });
  assert.equal(groups.find(g => g.probe === 'compute').censored, true);
  const text = reportMarkdown({ started: 'fixture', groups: [{ probe: 'redraw', samples: [{ size: 401, wall_ms: 12.5, status: 'rejected', error: 'real | error\nmessage' }] }, groups[0]] });
  assert.match(text, /401 \| 12\.50 \| rejected \| real \\\| error message/);
  assert.match(text, /ceiling unknown/);
});

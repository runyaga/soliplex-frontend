import test from 'node:test';
import assert from 'node:assert/strict';
import { runInNewContext } from 'node:vm';
import { parseScenarioArgs } from '../lib/options.mjs';
import { driveProbePlan, matchProbeResult, matchesProbeStatus, probePlan, reportMarkdown, revealAppTarget } from '../probes/run_probes.mjs';

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
        status: ['compute', 'windows', 'cycles'].includes(input.probe) && input.index === 2 ? 'rejected' : 'completed',
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

test('thrown samples and cleanup failures are recorded and remaining samples and groups run', async () => {
  const recorded = [];
  const groups = await driveProbePlan({
    sample: async ({ probe, index }) => {
      if ((probe === 'charts' && index === 1) || (probe === 'compute' && index === 0) || (probe === 'long' && index === 100)) {
        const error = new Error('scroll timed out');
        error.observation = { id: 8, program_status: 'completed', size: 32 };
        throw error;
      }
      return { index, status: 'completed' };
    },
    onSample: async (probe, result) => recorded.push({ probe, ...result }),
    afterGroup: async group => { if (group.probe === 'windows') throw new Error('close refused'); },
  });
  assert.deepEqual(groups.map(g => g.probe), probePlan.map(([probe]) => probe));
  assert.equal(recorded.length, probePlan.reduce((sum, [, , limit]) => sum + limit, 0));
  const failed = groups.find(g => g.probe === 'charts').samples[1];
  assert.deepEqual(failed, { id: 8, index: 1, size: 32, program_status: 'completed', status: 'harness_error', error: 'scroll timed out' });
  assert.equal(groups.find(g => g.probe === 'charts').samples[4].status, 'completed');
  assert.equal(groups.find(g => g.probe === 'long').samples.length, 300);
  assert.equal(groups.find(g => g.probe === 'windows').error, 'close refused');
  assert.equal(groups.at(-1).samples.length, 40);
  assert.match(reportMarkdown({ started: 'fixture', groups }), /cleanup \| \| harness_error \| close refused/);
});

test('result matching requires the recorded probe, id, terminal outcome and exact long-session count', () => {
  const completed = { id: 1, probe: 'compute', status: 'completed', checksum: 994853,
    observation: { status: 'rejected', error: 'old visibility failure' } };
  const failed = { id: 2, probe: 'redraw', status: 'error', error: 'Too many components in one run.' };
  const requested = { id: 3, probe: 'windows', status: 'requested' };
  const long = { id: 4, probe: 'long', status: 'completed', count: 10 };
  const book = { results: [completed, failed, requested, long, { id: 5, probe: 'charts', status: 'started' }] };
  assert.equal(matchProbeResult(book, { id: 1, probe: 'compute' }), completed);
  assert.equal(matchProbeResult(book, { id: 1, probe: 'charts' }), undefined);
  assert.equal(matchProbeResult(book, { id: 10, probe: 'compute' }), undefined);
  assert.equal(matchProbeResult(book, { id: 2, probe: 'redraw' }), failed);
  assert.equal(matchProbeResult(book, { id: 3, probe: 'windows' }), requested);
  assert.equal(matchProbeResult(book, { id: 4, probe: 'long', count: 1 }), undefined);
  assert.equal(matchProbeResult(book, { id: 4, probe: 'long', count: 10 }), long);
  assert.equal(matchProbeResult(book, { id: 5, probe: 'charts' }), undefined);
});

test('status matches text or merged semantics lines without accepting stale ids, counts or stdout', () => {
  const message = 'PROBE 1 compute done';
  assert.equal(matchesProbeStatus(message, message), true);
  assert.equal(matchesProbeStatus(`Platform probe\n  ${message}\r\nCompute`, message), true);
  assert.equal(matchesProbeStatus('PROBE 10 compute done', message), false);
  assert.equal(matchesProbeStatus('PROBE 1 compute completed', message), false);
  assert.equal(matchesProbeStatus('PROBE 1 long count 10 done', 'PROBE 1 long count 1 done'), false);
  assert.equal(matchesProbeStatus('PROBE 1 compute done extra', message), false);
  assert.equal(matchesProbeStatus(null, message), false);
  assert.equal(matchesProbeStatus('', undefined), false);
});

test('visibility scrolls the app scrollable and reacquires semantics after a redraw', async () => {
  const wheels = [], moves = [];
  let position = 500, located = 0;
  const bounds = { left: 0, right: 400, top: 0, bottom: 300, width: 400, height: 300 };
  const root = { getBoundingClientRect: () => bounds, parentElement: null, style: {} };
  const overflow = { tagName: 'FLT-SEMANTICS-SCROLL-OVERFLOW' };
  const scroll = { children: [overflow], scrollHeight: 2000, clientHeight: 260, style: { overflowY: 'hidden' },
    getBoundingClientRect: () => ({ ...bounds, top: 40 }), parentElement: root };
  root.querySelectorAll = () => [scroll];
  const element = { closest: () => root, parentElement: scroll,
    getBoundingClientRect: () => ({ left: 20, right: 200, top: 50 - position, bottom: 70 - position, width: 180, height: 20 }) };
  const evaluate = (fn, target) => runInNewContext(`(${fn.toString()})(target)`, {
    target, innerWidth: 1000, innerHeight: 800, getComputedStyle: node => node.style,
  });
  const scope = {
    scrollIntoViewIfNeeded: async () => {},
    evaluate: async fn => evaluate(fn, root),
    page: () => ({ mouse: {
      move: async (x, y) => moves.push([x, y]),
      wheel: async (x, y) => { wheels.push([x, y]); position = Math.max(0, position + y); },
    } }),
  };
  const result = await revealAppTarget(scope, async () => {
    located++;
    return { generation: located, count: async () => 1, isVisible: async () => true, evaluate: async fn => evaluate(fn, element) };
  }, { top: true, wait: async () => {} });
  assert.deepEqual(wheels, [[0, -2000]]);
  assert.deepEqual(moves, [[200, 170]]);
  assert.equal(result.generation, 2);
});

test('unreached boundaries are censored and reports keep measured errors', async () => {
  const groups = await driveProbePlan({ sample: async ({ index }) => ({ index, wall_ms: 1.25, status: 'completed' }) });
  assert.equal(groups.find(g => g.probe === 'compute').censored, true);
  const text = reportMarkdown({ started: 'fixture', groups: [{ probe: 'redraw', samples: [{ size: 401, wall_ms: 12.5, status: 'rejected', error: 'real | error\nmessage' }] }, groups[0]] });
  assert.match(text, /401 \| 12\.50 \| rejected \| real \\\| error message/);
  assert.match(text, /ceiling unknown/);
});

import { workspaceMatches } from './selectors.mjs';
import { captureProgramTurns, captureTurn } from './turns.mjs';

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

// Flutter updates aria-checked after the click returns, so setChecked's
// immediate state check fails. Click once, then poll for the checked state.
async function check(target, wait) {
  if ((await target.getAttribute('aria-checked')) === 'true') return;
  await target.click();
  for (let i = 0; i < 20; i++) {
    if ((await target.getAttribute('aria-checked')) === 'true') return;
    await wait(100);
  }
  throw new Error('Checkbox did not become checked');
}

// Whole-word matching lets "Run" also match "Show run history (2)". When
// exactly one match carries the exact name, act on that one.
export async function narrowToExact(matches, name) {
  if (matches.length < 2) return matches;
  const exact = [];
  for (const match of matches) {
    const label = ((await match.target.getAttribute('aria-label')) ?? (await match.target.innerText())).trim();
    if (label === name) exact.push(match);
  }
  return exact.length === 1 ? exact : matches;
}

export async function performActions(page, actions = [], turnOptions, onTurn = () => {}, wait = pause, onAssertions) {
  const observations = [];
  for (const action of actions) {
    const kind = action.kind ?? 'click';
    const role = action.role ?? ({ run_program: 'button', fill: 'textbox', check: 'checkbox', select: 'button', choose: 'button' })[kind];
    const assertion = { ...action, kind: 'role', role, region: action.region ?? 'workspace' };
    const deadline = Date.now() + 15000;
    let matches = [];
    while (Date.now() < deadline) {
      matches = await workspaceMatches(page, assertion);
      if (matches.length) break;
      await wait(250);
    }
    matches = await narrowToExact(matches, action.name);
    if (matches.length !== 1) throw new Error(`Action needs one visible workspace ${role}: ${action.name}`);
    const target = matches[0].target;
    const trigger = async () => {
      if (kind === 'fill') {
        // Flutter's editing state requires focus and key events, like chat.
        await target.click();
        await wait(300);
        await page.keyboard.press('ControlOrMeta+A');
        await page.keyboard.press('Backspace');
        await page.keyboard.type(action.value);
        await page.keyboard.press('Tab');
      } else if (kind === 'check') {
        await check(target, wait);
      } else if (kind === 'select' || kind === 'choose') {
        // Roles are explicit: multiple choices expose checkboxes; single
        // choices with displayStyle=checkbox expose radio buttons.
        if (role === 'checkbox' || role === 'radio') await check(target, wait);
        else if ((await target.getAttribute('aria-pressed')) !== 'true' && (await target.getAttribute('aria-selected')) !== 'true') await target.click();
      } else {
        await target.click();
      }
    };
    if (kind === 'run_program') {
      if (!turnOptions) throw new Error('run_program requires room and thread context');
      observations.push(await captureProgramTurns(page, { ...turnOptions, expectedOutput: action.expectedOutput, expectRepairs: action.expectRepairs }, trigger, action.expectRepair, onTurn, wait));
    } else if (action.awaitTurn) {
      if (!turnOptions) throw new Error('awaitTurn requires room and thread context');
      await onTurn(await captureTurn(page, turnOptions, trigger));
    } else await trigger();
    await wait(600);
    if (action.assertions) {
      if (!onAssertions) throw new Error('Action assertions require an inspector');
      const results = await onAssertions(action.assertions);
      if (!results.length || results.some(a => !a.pass)) throw new Error(`Action assertions failed after ${action.name}`);
    }
  }
  return observations;
}

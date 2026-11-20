import { workspaceMatches } from './selectors.mjs';
import { captureTurn } from './turns.mjs';

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

export async function performActions(page, actions = [], turnOptions, onTurn = () => {}, wait = pause) {
  for (const action of actions) {
    const kind = action.kind ?? 'click';
    const role = action.role ?? ({ fill: 'textbox', check: 'checkbox', select: 'button', choose: 'button' })[kind];
    const assertion = { ...action, kind: 'role', role, region: action.region ?? 'workspace' };
    const deadline = Date.now() + 15000;
    let matches = [];
    while (Date.now() < deadline) {
      matches = await workspaceMatches(page, assertion);
      if (matches.length) break;
      await wait(250);
    }
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
        // Intake Districts uses FilterChip, exposed as a labelled button.
        // Checkbox/radio variants are selected idempotently as well.
        if (role === 'checkbox' || role === 'radio') await check(target, wait);
        else if ((await target.getAttribute('aria-pressed')) !== 'true' && (await target.getAttribute('aria-selected')) !== 'true') await target.click();
      } else {
        await target.click();
      }
    };
    if (action.awaitTurn) {
      if (!turnOptions) throw new Error('awaitTurn requires room and thread context');
      await onTurn(await captureTurn(page, turnOptions, trigger));
    } else await trigger();
    await wait(600);
  }
}

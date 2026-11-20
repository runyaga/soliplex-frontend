import { regionSelector } from './core.mjs';

const escape = name => name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// Flutter merges neighbouring labels into one semantics node, for example a
// textbox named "Scenario intake Question Districts". The region container
// keeps a whole-word substring match specific.
const words = name => new RegExp(`(^|\\W)${escape(name)}(\\W|$)`, 'i');

function locatorFor(page, a) {
  if (a.kind === 'text') {
    // Window and panel titles exist only as group labels.
    return page.getByText(words(a.name)).or(page.getByRole('group', { name: words(a.name) }));
  }
  return page.getByRole(a.kind === 'source' ? 'textbox' : a.role, { name: words(a.name) });
}

export async function workspaceMatches(page, a) {
  const selector = regionSelector(a.region).split(', ').map(region =>
    a.window ? `${region} [aria-label=${JSON.stringify(`Workbench window ${a.window}`)}]` : region).join(', ');
  const container = page.locator(selector);
  const locator = locatorFor(container, a);
  const matches = [];
  for (let i = 0; i < await locator.count(); i++) {
    const target = locator.nth(i);
    // A user scrolls a window to reach its content. Absence checks never scroll.
    if (!a.absent) await target.scrollIntoViewIfNeeded?.({ timeout: 2000 }).catch(() => {});
    const box = await target.boundingBox();
    if (!await target.isVisible() || !box || box.width <= 0 || box.height <= 0) continue;
    if (a.kind === 'source') {
      // Flutter web writes a text field's value into the DOM only on focus.
      await target.focus();
      // The value arrives a frame or more after focus.
      await new Promise(resolve => setTimeout(resolve, 300));
      const value = await target.inputValue();
      await target.blur();
      if (!value.includes(a.includes)) continue;
    }
    // A title can match as text and as a group label: count each place once.
    if (matches.some(m => m.box.x === box.x && m.box.y === box.y && m.box.width === box.width && m.box.height === box.height)) continue;
    matches.push({ target, box });
  }
  return matches;
}


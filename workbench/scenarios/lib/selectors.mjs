import { regionSelector } from './core.mjs';

const exact = name => new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i');

function locatorFor(page, a) {
  return a.kind === 'text'
    ? page.getByText(exact(a.name))
    : page.getByRole(a.kind === 'source' ? 'textbox' : a.role, { name: exact(a.name) });
}

export async function workspaceMatches(page, a) {
  const container = page.locator(regionSelector(a.region));
  const locator = locatorFor(container, a);
  const matches = [];
  for (let i = 0; i < await locator.count(); i++) {
    const target = locator.nth(i);
    const box = await target.boundingBox();
    if (!await target.isVisible() || !box || box.width <= 0 || box.height <= 0) continue;
    if (a.kind === 'source') {
      const value = await target.inputValue();
      if (!value.includes(a.includes)) continue;
    }
    matches.push({ target, box });
  }
  return matches;
}


// Keep the documented directory command working on Node versions that resolve
// an explicit test directory as a module instead of discovering its files.
Promise.all([import('./core.test.mjs'), import('./turns.test.mjs')]).catch(error => {
  console.error(error);
  process.exitCode = 1;
});

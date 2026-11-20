# Workbench research notes and lessons

Newest first. Each entry: what happened, the evidence, what changed.

## 2026-11-19

| Lesson | Evidence | What changed |
| --- | --- | --- |
| Flutter web merges labels and hides field values | A textbox was named "Scenario intake Question Districts". Chart text sat in one node. A window title was only a group label. A text area's value was empty until focused | Harness matches whole words inside a labelled region and focuses a field before reading it. The merged textbox name is an accessibility bug to fix in the form |
| Locate regions by label, not by geometry | The first live harness run reported 0 matches for widgets visible in the screenshot. It placed regions relative to the composer, which is centred on the page while the chat column sits to its left | Each workbench region carries a semantics label and the harness scopes its lookups to it |
| Click Flutter's semantics placeholder from JavaScript | A pointer click on `flt-semantics-placeholder` throws because Flutter keeps it off-screen. The harness sign-in failed on its first step and hid the error | The harness dispatches `element.click()`. Sign-in failures name the step and error class |
| A pixel check catches what the accessibility tree hides | The form's Submit button was in the semantics tree at y=333 but clipped by its card, and the pixel check found it blank | Keep pixel checks on every canvas assertion |
| The owner should not be the test harness | The owner found `ui.Label`, "content parent must be empty" and a blank program window before any check did | Deterministic scenario script and a two-model prompt suite run after every deploy (`workbench/scenarios/`) |
| Separate platform bugs from model mistakes | A failed run looked the same whether Glimmer guessed an API or the workbench was broken | No-model scenarios test the platform. The model suite tests skills and prompts |
| Unit tests and review rounds missed every seam bug | Ten bugs surfaced only in the deployed app: circular import, missing `/v1` prefix, root-owned volume, null default layout, snapshot envelope mismatch, tool signature against Soliplex `RunContext`, digit-first run ids, blank panels, the guard rejecting normal actions, the empty-parent rule blocking fixes | Each fix adds a test across the seam where it hid. Drive the deployed app early, not after the plan's last unit |
| Ride the existing pipeline before building a parallel one | An architecture review found the SQLite store, REST snapshot and reservation guard duplicated Soliplex's activity pipeline and thread history. Blank panels came from the canvas reading one store and rendering from another | Canvas reads layout and content from the existing thread surface store. Tools return A2UI activity events. Parallel machinery is being removed step by step |
| Eight review rounds on one group is too many | G1's rounds kept finding defects in the parallel machinery the review later recommended deleting | Formal review loops paused for the preview. Review the architecture before polishing an implementation |
| Freeze every wire shape both sides read | The GET snapshot envelope was never a shared fixture. Server and client each passed their own tests and disagreed | Shared byte-identical fixtures with digest tests on both sides for every cross-language payload |
| Test with production-shaped values | Tests used run id `run-1`. Real Soliplex run ids are UUIDs that can start with a digit, which broke the letter-first id rule | Contract tests use real-shaped ids (UUIDs) |
| dart2js conflates 1.0 and 1 | An int-only check passed on the VM and failed on Chrome | Run such tests under dart2wasm, skip only dart2js with `testOn: '!js'` |
| A model needs the API taught, not guessed | Without the `ui` skill, Glimmer wrote `ui.Label`, which does not exist | Workbench rooms get the real `ui` and tool teaching, generated from the registered catalogs |
| Route cross-cutting work to the reasoning model | Luna rounds returned incomplete work at seams. Sol traced the blank-panel path end to end | Sol for multi-package traces, Luna for bounded units, Astra for architecture questions |

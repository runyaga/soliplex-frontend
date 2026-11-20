# Workbench research notes and lessons

Newest first. Each entry: what happened, the evidence, what changed.

## 2026-11-20

| Lesson | Evidence | What changed |
| --- | --- | --- |
| A deploy-time patch hides the bug class | The stack script rewrote one `nextInt(1 << 32)` while staging. Two more stayed in source. Under dart2js the shift wraps to 0 and `nextInt(0)` throws, so every canvas Run and Submit died before its request. VM widget tests passed | Fixed in source. The deploy now refuses any shift by 32 in the staged tree. A Chrome test fails without the fix |
| A widget can work and send nothing | Run showed "Run 1 · ok" and the form ticked its boxes, while the page made zero API requests. Only a network log after the click showed the break | Harness cases assert the action turn's stream and the stored run input, not the widget state |
| Probe the deployed app before writing the fix brief | A 60-line Playwright probe found both the checkbox roles and the silent Run in one pass. The brief then named the exact evidence | Keep probes in the scratchpad and hand their output to the fixing round |
| Playwright's request context lacks the app's bearer header | The stored-run read returned 401. The app authenticates by header, not cookie | The harness reuses the header from the intercepted request, in memory only, and a test checks it stays out of the record |

## 2026-11-19

| Lesson | Evidence | What changed |
| --- | --- | --- |
| One run per prompt cannot score a small model | E4B flipped two prompts from pass to fail between runs with no relevant change. Three runs gave 19 of 30 with two prompts at 0 of 3 | E4B is reported as passes out of 3 per prompt. Glimmer still runs once |
| Make the tool forgiving before teaching the model | E4B put programs in regions and moved content ids. Teaching alone did not fix it. Tools that create the window and resolve a content id to its panel took tally_counter and move_chart_right to passing | When a weak model misuses a tool the same way twice, change the tool first |
| A green tick must mean success | A tool raised a validation error, the timeline showed success and the model told the user it worked | Tool validation failures are retryable errors with corrective text and render as failed |
| Chrome drops streamed response bodies | `response.text()` on the AG-UI SSE stream failed in 16 of 20 model cases with "No resource with given identifier" | The harness routes the run request, fetches it itself and fulfils the page with the full body |
| A fixed-height window hides what a program draws | Glimmer wrote a correct tally program. The window clipped at about 450 px, so Run and the buttons were in the semantics tree with blank pixels | Windows and the source editor must scroll or size to content. The pixel check caught it |
| Type into Flutter web with key events | The first model-suite run failed all 20 prompts: `fill` hit a read-only text area, and `insertText` left Flutter's editing state empty | The harness clicks the composer, waits, and sends key events. Twenty failures in one shape point at the harness first |
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

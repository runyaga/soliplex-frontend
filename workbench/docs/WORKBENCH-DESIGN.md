# Soliplex workbench design

## Amendment (2026-11-19)

| Changed | Where |
| --- | --- |
| F01: Minimize remains user-only through panel chrome, agent demo requests only a move | Section 1, Minimize and tray, section 9, live demo step 4 |
| F02: Persist minimized, hidden and pinned overrides by stable node ID with geometry, clear on sign-out and discard removed IDs | Section 7, device-local state |
| F03: Minimum tools use intake only and no selection_group, later form/chart variants and ShowTable moved out of minimum scope | Section 3, After the minimum, section 5 export schema reference |
| Binding nested stable-ID tree replaces flat placement, protocol (c) retained | Sections 1, 2, 3, 7, 8 and 9, including all three mockups |
| Separate client and server Python tools, server declared but disabled in minimum, real runner deferred | Sections 3 and 5, section 9 and work order U14 |
| Explicit run traces and file-backed interpreter-state pointer | Sections 5 and 7, Claude owns Logfire wiring |
| B01 and B04 resolved by this amendment, B07 remains Claude's setup-stack.sh work | Work order blocker table and U12, earlier owner answers below preserved |
| Decision lookup | Three amendment queries, `Soliplex workbench nested layouts`, `Soliplex Python client server interpreter handoff`, `Soliplex workbench Logfire`, failed with `Too many open files`. Indexed decisions remain **UNVERIFIED**. I use the binding 2026-11-19 amendment and `P/workbench/PROMPT.md:155`, `P/workbench/PROMPT.md:164`, plus local ADR path@commit evidence below |

Phase 1, 2026-11-19. I recommend **option (c), a separate A2UI layout surface whose data model describes the workspace**. Small typed tools update that surface and publish ordinary content surfaces. The room shell renders the arrangement. Monty remains in `soliplex_monty`.

## Scope, authority and evidence

| Reading rule | Application |
| --- | --- |
| Design versus implementation | Behavior, identifiers, schemas, limits, estimates and tests are specifications, not claims of implemented code. The 2026-11-19 owner amendment is binding, earlier owner answers remain below, and existing-code claims are labelled **Evidence** or carry path:line citations. Acceptance tests are specifications, not passing results. |
| Authoritative brief | `P/workbench/PROMPT.md:19` supplies isolation, models, package boundaries and safety. Its decisions at `P/workbench/PROMPT.md:51` override earlier alternatives. I reread the full brief after it changed during inspection. |
| Phase boundary | The original deliverable is this design with three inline ASCII mockups. This amendment also updates WORK-ORDER-P3.md. Stack installation and implementation are future work. No stack, repository, worktree, dependency or container change is part of this phase. |
| Knowledge lookup | Queries were `Soliplex workbench layout module composition`, `Soliplex action-only A2UI surface replay`, and `Monty session retry owner decisions`. All failed with `Too many open files`. **UNVERIFIED:** indexed decisions. This is an unavailable search, not a successful search returning “no prior decision found”. |
| Verified prior decisions | ADR-004 is Accepted and prescribes module composition and lifecycle. ADR-005 is Accepted and prescribes downward imports and shared stores. I used `E/docs/adr/ADR-004-module-composition-contract.md@dccc4901` and `E/docs/adr/ADR-005-module-layering.md@dccc4901`. Their decision passages are `E/docs/adr/ADR-004-module-composition-contract.md:44` and `E/docs/adr/ADR-005-module-layering.md:64`. |
| Changing source | `D` is an uncommitted worktree over `482879f8`. Other agents changed it during inspection. Citations describe the opened text, not an immutable release. The implementation must inventory the final source before porting. |

Citation aliases expand to these absolute paths. `alias/relative/path:line` always refers to a file I opened. Backend citations marked `origin/main` refer to numbered `git show` output, not the working file.

| Alias | Absolute root | Inspected identity |
| --- | --- | --- |
| `P` | `~/dev/plans/soliplex-a2ui` | Local plans, no enclosing Git repository |
| `D` | `~/dev/soliplex-frontend-wt/exp-dojo-a2ui` | HEAD `482879f8510e46faaa15a22dea93996803cbbea6`, plus working changes |
| `E` | `~/dev/soliplex-frontend-a2ui-embed` | HEAD `dccc4901a421e093a38a1183dc2a4ce6de04767f`, plus working changes |
| `M` | `~/dev/soliplex-a2ui-monty` | HEAD `1161004dd6d0d72244153808277c7cc25dae5e78`, inspected working files |
| `Q` | `~/dev/soliplex-embed-probe/lib/lab` | Inspected working files |
| `L` | `~/dev/soliplex-a2ui-lab/src/soliplex_a2ui_lab` | Inspected working files |
| `S` | temporary `soliplex-a2ui` source checkout | Local `ggozad/soliplex-a2ui` checkout, HEAD `56bf87c8b78cce74fad849d36dbc4656fbba882e`. The three cited package files have no diff against HEAD |
| `B` | `~/dev/soliplex` | `origin/main` = `fef0c00f96c21a3213796ae3223e9391f60d10aa` |
| `T` | `~/dev/soliplex-template` | Read-only skill inspection |
| `C` | `~/.pub-cache/hosted/pub.dev` | Installed package source, versions included in paths |
| `R` | `~/dev/dart_monty2/packages/dart_monty` | Read-only resource-limit source |

| Read-first input | What I carry forward |
| --- | --- |
| `P/track-a-action-contract.md:33`, `P/track-a-client-gaps.md:70` | Immutable submissions, request-stage validation, accepted surface identity, drafts and passive replay. The gap report is historical evidence, not a statement of current `D`. |
| `P/track-b-binding-contract.md:127`, `P/widget-interaction-findings.md:24` | Stage and validate before publication. Preserve stable widget identity. Test real interactions, not just generated JSON. Persistent sessions override Track B's original fresh-session clause. |
| `P/rooms/ROOMS-DESIGN.md:135` | Separate emitter, action, atomic candidate, workspace and replay work. The seven-room ladder is context, not additional workbench scope. |
| `P/hhg-a2ui-r2.md:261`, `P/hhg-a2ui-r3.md:9` | R3 supersedes the R2 feed-budget prerequisite and broad component scope. Use the finite raised session budget, model-authored programs, bar/line Chart, and immutable handles. |
| `P/catalog-survey.md:106`, `P/inspiration-survey.md:147` | Prefer a narrow native chart interface. Do not import legacy catalog packages merely because they contain a table or chart. |
| `P/monty-handoff.md:230` | Prefer answer-only round trips. Section 5 defines the required file-backed pointer now. Interpreter transfer and resume remain deferred. **UNVERIFIED:** independent reproduction of the note's version and timing results. |
| `P/a2ui-lab-stack.md:128`, `P/dojo-integration-plan.md:184` | Installation gotchas and historical port omissions are inputs to future work. They do not authorize touching either stack. |
| `T/skills/soliplex-template/SKILL.md:28` | The template distinguishes generation, identity, room and source-package tasks. I read the skill as required source material and did not run its deployment workflows. |
| Optional input availability | R3 and `monty-handoff.md` appeared during inspection and were read in full. `monty-codegen-skill.md` remains absent. Its contents are **UNVERIFIED**. |

| Owner decision in force | Design consequence |
| --- | --- |
| `soliplex-a2ui` at `56bf87c`, `P/workbench/PROMPT.md:53` | Reuse its emitter and extend its action reader. Do not ship a competing dojo-local protocol or `get_ui_action` reader. |
| Dart A2UI versions, `P/workbench/PROMPT.md:54` | Target core `^0.8.0`, Flutter `^0.4.0`, agent `^0.4.0`. A2UI wire version remains `1.0`. Python package version numbers are a separate compatibility check. |
| Session, authorship and budget, `P/workbench/PROMPT.md:55` | One session per program surface, persistent globals, fresh invocation arenas, short handlers, model-written code and raised `maxSuspensions`. No runtime budget redesign is required. |
| Maps, `P/workbench/PROMPT.md:58` | Any later map uses `[lng, lat]`, `urn:soliplex:catalog:geo:1`, public tiles and no client API keys. Map implementation is outside the first workbench slice. |
| Retry and startup, `P/workbench/PROMPT.md:59` | Default two automatic repairs following Run, then “Do you want to try again?”. First startup says “Loading Monty”. |

## 1. Layout model

| Tree rule | Binding contract for the minimum |
| --- | --- |
| Workspace and identity | One private tree per authenticated actor, server, room and thread. Server allocates stable node IDs. Address every node by ID, never by an ancestry path. Node records use `id`, tools use `node_id` and `parent_id`, and no separate panel identity is needed. Moving a parent preserves every descendant ID and content reference |
| Reserved nodes | Server creates `wb_root` of kind `workspace`, with `r_chat`, `r_left`, `r_right`, `r_canvas` and `r_tray` of kind `region`. Region payload names its role. Root and regions cannot be created, moved or closed by the agent. Chat retains the existing timeline/composer and cannot be covered or replaced |
| Agent-created nodes | `create_container(parent_id, kind, title)` creates one empty `split`, `tabs`, `panel` or `window`. Content tools create a panel plus surface leaf under a region/split/tabs, or fill an empty panel/window. `run_python_client` fills an empty window or panel within a window. All IDs and activity/surface registrations come from the server |
| Agent movement | `move_panel(node_id, parent_id, order, size)` moves any split, tabs, panel, window or surface subtree within this workspace, subject to grammar, depth, capacity and single-mount validation. A surface may move only into an empty panel/window. Program surfaces must keep a window ancestor. No whole-subtree argument or path addressing |
| Grammar | Workspace contains only the reserved regions. Chat and tray have no authored children. Left/right/canvas regions, split and tabs contain split, tabs, panel or window nodes. Panel/window contains zero or one split, tabs or surface. Surface is a leaf referencing one registered activity/surface pair. Windows require canvas ancestry and cannot have another window ancestor. Empty containers are legal for incremental authoring |
| Edges and payloads | Each node has `id`, nullable `parentId`, ordered `children`, `kind`, `title`, `size`, `visibility` and closed kind-specific `payload`. Root alone has no parent. Every non-root edge agrees in both directions. Region payload has `role`, split has `axis: horizontal or vertical`, surface has `activityMessageId` and `surfaceId`, other payloads are empty |
| Limits | Root counts as depth 1. Maximum depth 8, 64 total nodes including closed nodes, 64 KiB serialized control-surface data, 12 effectively open content mounts, 3 live client program sessions and 2 expanded windows. Nested wrappers do not count twice as content panels. Split has at most 3 children, tabs at most 12. Reject a mutation atomically with a typed depth/capacity error |
| Close parent | Visibility is `open`, `minimized` or `closed`. Set the selected node's visibility to `closed`. All descendants become effectively closed through ancestry, retain their own stored visibility, IDs, source and accepted results, and are never deleted or implicitly reparented. Cancel/dispose every descendant program session and revoke repair permission, including pinned descendants. A deliberate user Restore sends the no-model `workbench.layout.restore@1` action with `{nodeId}` to clear that accepted ancestor close atomically and restore descendants' prior visibility, with Python idle |
| User precedence | User may move, resize, minimize, restore, hide and pin containers or leaves. Same-device overrides win until Reset/Restore. A pinned descendant of an agent-closed parent stays visible with retained ancestor chrome and a “Kept open by pin” badge, showing saved output only. Local hide suppresses the entire subtree and cancels/disposes its programs. Pins never preserve execution permission |
| Minimize and tray | Only the user may minimize a container through panel chrome in the minimum, without reparenting it. Descendants become offstage and idle, with one tray reference to that subtree. Restore uses the same IDs. Tray entries are derived views, not second content mounts |
| Persistence and replay | Server stores the complete validated tree, child order, size, visibility, registered content and revision atomically. Device storage holds ID-keyed overrides. Hydrate accepted tree before overlays, revalidate overlay edges and clamp geometry. Replay restores the same IDs and closed ancestry without Python, handlers, tools or models |
| Thread change | Flush local drafts and geometry, cancel execution and dispose old-thread sessions. A new thread starts with only reserved nodes. Returning restores source and saved output, with Run required to recreate client Python state |

| Host rendering | Rule |
| --- | --- |
| Chat | Permanent composer, minimum desktop width 320 logical pixels. Reserved navigation stays outside the authored tree |
| Sidebars | Left/right regions hold nested panels, tabs and splits. Initial width 260, adjustable 220 to 420. Empty sidebar collapses, right collapses before chat falls below its minimum |
| Canvas | Render the authored split/tab/container hierarchy. Split defaults horizontal with equal shares, at most three children. Nested panels use small/medium/large size requests, not model-written pixel geometry |
| Windows | Window nodes hold their own split/tab/panel hierarchy and surface leaves. Initial rectangle 640 by 480, clamped to workspace bounds. No browser popups and no overlap over chat |
| Narrow screen | Below 900 logical pixels, show Chat/Workspace tabs, sidebars as drawers and windows as full-width cards. When a split cannot provide 240 logical pixels per child, stack it vertically. This presentation transform does not change accepted tree IDs, edges or order |
| Overflow | Give split axes finite constraints before applying weights. Each visible surface gets measured width and bounded height with host-owned vertical scrolling. Constrain chart width when horizontal space is unbounded. Keep Run/Submit reachable, use flexible labels and test nonzero readable leaf bounds as well as Flutter errors |
| View state | Keep shell tab selection and scroll position by stable node ID through movement and ordinary content updates. Component-level tab/focus persistence requires separate binding tests. Minimize never makes a second renderer |

| Nested-layout evidence | Required treatment |
| --- | --- |
| Probe reports silent leaf collapse, ignored weights on unbounded axes and chart/Run-row overflow, `P/nested-layouts.md:37`, `P/nested-layouts.md:39`, `P/nested-layouts.md:40` | Use bounded axes, readable-width assertions and flexible controls in U07/U08. **UNVERIFIED:** those probe fixes in the implementation target |
| Probe measures per-surface width through CLIENT and `/client/viewport`, with no Python on resize, `P/nested-layouts.md:48`, `P/nested-layouts.md:56` | U08 supplies measured content width, excluding chrome, at the next deliberate Run/handler. Resize may update bound viewport data but cannot run Python or rebuild its component tree. Shell stacking needs no Python |
| Probe reports lost focus, tab and scroll state on re-render, `P/nested-layouts.md:63`, `P/nested-layouts.md:70`, `P/nested-layouts.md:74` | Preserve mount identity on shell moves. Teach bound inputs and `data=DATA` on deliberate redraw, do not infer component state preservation from shell nesting |
| Hints improved turn-1 validity in one small experiment, `P/nested-layouts.md:105`, `P/nested-layouts.md:112` | Teach plain top-level handle_event, immutable handles, list-first children, dictionary Event context and at most 3 side-by-side items. **UNVERIFIED:** repeatability in target. Helpers remain proposals, `P/nested-layouts.md:185` |

Mockup A, wide nested workspace. Brackets contain stable node IDs, arrows show edges only:

```text
[wb_root workspace]
+-------------------+--------------------------+--------------------------------+
| [r_chat region]   | [r_left region]          | [r_canvas region]              |
| timeline          | [p_intake panel]         | [sp_data split vertical]       |
|                   |   [t_intake tabs]        |   +--------------------------+ |
| Agent: ready      |     [p_form panel]       |   | [p_chart panel]          | |
|                   |       [s_form surface]   |   |   [s_chart surface]      | |
|                   |     [p_notes panel]      |   +--------------------------+ |
|                   |       [s_notes surface]  |   | [p_table panel]          | |
| [message][Send]   | [Intake] [Notes]         |   |   [s_table surface]      | |
+-------------------+--------------------------+--------------------------------+
[r_right region: empty]  [r_tray region: derived minimized subtree references]
```

Mockup B, a window inside the canvas region holds its own layout:

```text
[r_canvas region]
  [w_calc window]  Estimate.py [pin] [min] [close]
  +------------------------------------------------------------+
  | [sp_calc split]                                            |
  | +--------------------------------+-----------------------+ |
  | | [p_code panel]                 | [p_help panel]        | |
  | |   [s_calc surface: client]     |   [s_help surface]    | |
  | | source / [Run] [Stop]          | instructions          | |
  | | Loading Monty                 |                       | |
  | | units [4] rate [25]            |                       | |
  | | [Recalculate] result: 100      |                       | |
  | | [Open chart from result]       |                       | |
  | +--------------------------------+-----------------------+ |
  +------------------------------------------------------------+
```

Mockup C, narrow reload of those same IDs. Only host presentation changes:

```text
+--------------------------------------+
| [Chat] [Workspace] [Left drawer]      |
| drawer: p_intake > t_intake           |
|         [Intake] [Notes]              |
+--------------------------------------+
| sp_data stacked                      |
| p_chart > s_chart: north 80, south 60 |
| p_table > s_table: north selected     |
+--------------------------------------+
| w_calc card > sp_calc stacked        |
| p_code > s_calc: saved result 100     |
| Python session is not running [Run]  |
| p_help > s_help: instructions         |
+--------------------------------------+
| r_tray: minimized subtree references |
+--------------------------------------+
```

## 2. Protocol comparison and choice

| Option | Strength | Cost and failure mode | Choice |
| --- | --- | --- | --- |
| (a) `layout` catalog with Panel, Sidebar, Window and Grid | Makes layout explicit in catalog vocabulary. Can describe nesting through layout components | Cross-surface references need a host mount registry, lifecycle ownership and cycle checks. A component cannot be allowed to construct room routing or a Monty runtime. This makes shell composition part of every generated component tree | Defer. It is more surface-composition machinery than this prototype needs |
| (b) Placement beside `a2ui_operations` on each activity | Small per-panel extension. Easy first placement and text fallback | Rearranging several panels spreads one layout across several activities. Ordering, collisions, sidebar visibility and local overrides need an additional aggregate contract. The current generated-message projection only copies operations/status and run attribution into tile data, `D/packages/soliplex_client/lib/src/application/a2ui_activity.dart:88` | Viable, but not selected |
| (c) Separate layout surface with a typed data model | One aggregate arrangement, independent content surfaces, ordinary A2UI data updates, one layout revision and one replayable source of placement intent | Requires a layout decoder and coordination when a new content surface and its layout reference arrive together. It is application-specific behavior, not an upstream A2UI feature | **Selected** |

| Architectural reason | Evidence and consequence |
| --- | --- |
| Modules own routes and teardown | ADR-004 describes `AppModule.build`, overrides and disposal at `E/docs/adr/ADR-004-module-composition-contract.md:46`. It requires lowering through `ShellConfig.fromModules` at `E/docs/adr/ADR-004-module-composition-contract.md:63`. Design: layout data cannot invent routes, public paths or module lifetimes |
| Composition stays in the flavor | ADR-004 uses constructor injection and one root scope at `E/docs/adr/ADR-004-module-composition-contract.md:146`. Design: a workbench flavor configures the existing room module and catalogs through explicit constructor seams |
| Features never import siblings | ADR-005's layer order is at `E/docs/adr/ADR-005-module-layering.md:66`, with shared state in `stores/` at `E/docs/adr/ADR-005-module-layering.md:90`. Design: keep the workbench presentation inside the room feature, not a new feature that imports room internals |
| RoomScreen already owns the outer layout | Wide mode assembles room rail, thread sidebar and content in a Row at `D/lib/src/modules/room/ui/room_screen.dart:1781`. Narrow mode uses a drawer at `D/lib/src/modules/room/ui/room_screen.dart:1820`. `_buildContent` assembles banners, files, thread body and composer at `D/lib/src/modules/room/ui/room_screen.dart:2003`. Design: replace the presentation slot around these existing pieces, not the shell/router |
| Catalog injection already has a seam | `standardFlavor(surfaceCatalogs:)` forwards catalogs into the kit at `D/lib/src/flavors/standard.dart:30`. RoomAppModule passes them to RoomScreen at `D/lib/src/modules/room/room_module.dart:137`. Design: preserve this path for content catalogs |

### Layout surface and wire shape

| Element | Proposed contract |
| --- | --- |
| Reserved control surface | Server registration marks exactly one surface as `workbench-layout@1`. This role is trusted registration metadata. A producer cannot acquire it by naming a component or inserting a data key |
| A2UI components | A fixed basic `Text` root bound to `/summary` provides an accessible fallback. The workbench host reads `/workbench` from the same surface's data model. The nested tree is this layout surface's data model. Content surfaces stay independent, with no recursive cross-surface component definitions |
| Addressing | Tools address stable `node_id` and `parent_id`. The server resolves registered leaf activity/surface pairs. The layout contains ordered tree edges and references, never copied content component definitions or ancestry paths |
| Update unit | Complete replacement activity snapshots under stable IDs. Materialize the complete layout candidate even if the producer internally uses `updateDataModel` patches |
| Revision | `layoutRevision` advances only for arrangement changes. `surfaceRevision` tracks every accepted control-surface publication, including shared selection updates. A selection change need not invalidate an unrelated move's layout precondition |
| Shape validation | Closed discriminated node objects and the section 1 grammar. Exactly one root, reserved regions, unique IDs, one parent, reachability, matching ordered edges, no cycles or duplicate mounts, scoped references, depth 8, 64 nodes, 12 open content mounts and 64 KiB control-surface content |
| Missing content | Retain the previous committed workspace and fetch the missing committed record. Never run Python to satisfy a reference |

Example control-surface data, not a second transport format:

```json
{
  "summary": "Workspace: Readiness",
  "workbench": {
    "schemaVersion": 1,
    "layoutRevision": 7,
    "rootId": "wb_root",
    "nodes": [
      {"id":"wb_root","parentId":null,"children":["r_chat","r_left","r_right","r_canvas","r_tray"],"kind":"workspace","title":"wb_root","size":"medium","visibility":"open","payload":{}},
      {"id":"r_chat","parentId":"wb_root","children":[],"kind":"region","title":"r_chat","size":"medium","visibility":"open","payload":{"role":"chat"}},
      {"id":"r_left","parentId":"wb_root","children":[],"kind":"region","title":"r_left","size":"medium","visibility":"open","payload":{"role":"left"}},
      {"id":"r_right","parentId":"wb_root","children":[],"kind":"region","title":"r_right","size":"medium","visibility":"open","payload":{"role":"right"}},
      {"id":"r_canvas","parentId":"wb_root","children":["sp_data"],"kind":"region","title":"r_canvas","size":"medium","visibility":"open","payload":{"role":"canvas"}},
      {"id":"r_tray","parentId":"wb_root","children":[],"kind":"region","title":"r_tray","size":"medium","visibility":"open","payload":{"role":"tray"}},
      {"id":"sp_data","parentId":"r_canvas","children":["p_readiness"],"kind":"split","title":"sp_data","size":"medium","visibility":"open","payload":{"axis":"horizontal"}},
      {"id":"p_readiness","parentId":"sp_data","children":["s_readiness"],"kind":"panel","title":"p_readiness","size":"medium","visibility":"open","payload":{}},
      {"id":"s_readiness","parentId":"p_readiness","children":[],"kind":"surface","title":"s_readiness","size":"medium","visibility":"open","payload":{"activityMessageId":"a2ui-surface-wb_chart_1","surfaceId":"s_chart_1"}}
    ],
    "shared": {"selections": {"districts": ["north"]}}
  }
}
```

| Delivery step | Proposed behavior |
| --- | --- |
| Prepare | Build content and layout candidates against the current registered catalogs and revisions. Validate all candidates before committing anything |
| Commit | One database transaction stores snapshots, registrations, layout revision and an ordered thread-journal record. A record can contain multiple activity snapshots |
| Emit | Use `surface_event(stable_key, operations)` for each snapshot, then copy the returned event with trusted surface metadata and `workbenchCommit: {recordId, sequence, index, count}` in content. These commit fields are proposed. They carry ordering, not placement |
| Client fold | Parts have zero-based `index` values from 0 through `count - 1`, with content before control surface and at most 13 parts. Buffer all parts, validate them, then publish one workspace change. Duplicates fold once by record ID. A sequence gap blocks later publication and requests journal hydration |
| Recovery | If persistence succeeds and delivery fails, hydration returns the same committed record. If preparation or commit fails, the old workspace stays visible |
| Standard presentation | It can render the basic summary and ordinary content surfaces. It does not interpret layout or lose content because workbench support is absent |

**Evidence:** `surface_event` currently returns a replacement `a2ui-surface` activity and derives its ID from its string argument, `S/src/soliplex_a2ui/__init__.py:28`. Design: persist a stable server key and pass it in that argument across updates, rather than passing each new `ctx.tool_call_id`. Add metadata through the returned event model. The current client preserves activity content separately from generated tile data, `D/packages/soliplex_client/lib/src/application/a2ui_activity.dart:46`. The proposed commit-aware reducer is new work.

## 3. Agent tools and catalog teaching

### Minimum typed inputs

These are proposed Pydantic v2 models for the minimum tool set. Later variants under After the minimum are excluded from minimum room tools, skills and U01 fixtures. Each callable receives the corresponding fields as top-level arguments, plus an injected `RunContext`. `RunContext`, actor, room, thread, revision preconditions and catalog manifests never appear as model-supplied arguments. `model_json_schema()` defines each JSON Schema. Expand the small shared definitions when sending schemas if a provider does not support references.

```python
from typing import Annotated, Literal
from pydantic import BaseModel, ConfigDict, Field

Id = Annotated[str, Field(min_length=1, max_length=64,
                         pattern=r"^[A-Za-z][A-Za-z0-9_-]*$")]
Title = Annotated[str, Field(min_length=1, max_length=80)]
NodeKind = Literal["split", "tabs", "panel", "window"]
Size = Literal["small", "medium", "large"]
Source = Annotated[str, Field(min_length=1, max_length=12000)]

class Closed(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True,
                              allow_inf_nan=False)

class Point(Closed):
    id: Id
    label: Annotated[str, Field(min_length=1, max_length=80)]
    value: Annotated[float, Field(ge=-1000000000, le=1000000000)]

Points = Annotated[list[Point], Field(min_length=1, max_length=32)]

class GetWorkbench(Closed):
    pass

class OpenPanel(Closed):
    title: Title
    text: Annotated[str, Field(min_length=1, max_length=2000)]
    parent_id: Id

class PlaceForm(Closed):
    template: Literal["intake"]
    title: Title
    parent_id: Id

class ShowChart(Closed):
    title: Title
    kind: Literal["bar", "line"]
    points: Points
    parent_id: Id

class RunPythonClient(Closed):
    title: Title
    source: Source
    parent_id: Id

class RunPythonServer(Closed):
    surface_id: Id
    source: Source

class CreateContainer(Closed):
    parent_id: Id
    kind: NodeKind
    title: Title

class MovePanel(Closed):
    node_id: Id
    parent_id: Id
    order: Annotated[int, Field(ge=0, le=63)]
    size: Size

class ClosePanel(Closed):
    node_id: Id

class RepairProgram(Closed):
    node_id: Id
    source: Source
```

| Tool and model | Behavior and `soliplex-a2ui` calls |
| --- | --- |
| `get_workbench`, `GetWorkbench` | Return up to 64 node IDs/kinds/parent IDs/ordered child IDs/titles, protected-node flags, layout revision, available catalogs/templates and a bounded advisory local-view summary. Read accepted state. No emitter or action-reader call |
| `open_panel`, `OpenPanel` | Compile basic Card/Column/Text. Call `capability.surface_operations` for content and control surface, then `surface_event` for both in one journal record |
| `place_form`, `PlaceForm` | Select only the registered intake template with fixed bindings, action manifest and context schema. Call `surface_operations`, strict template/catalog validation, then `surface_event` for form plus layout |
| `show_chart`, `ShowChart` | Compile graphics:2 Chart, with one identified series for `line` and a server-selected default selection group. The model supplies no selection_group. Use `surface_operations` with explicit component `@catalogId`, extended catalog validation, then `surface_event` plus layout |
| `create_container`, `CreateContainer` | Create one empty allowed container under `parent_id`. Split defaults to horizontal equal shares. Validate section 1 grammar, then emit only the complete control surface. Reorder/fill it through subsequent small tool calls |
| `run_python_client`, `RunPythonClient` | Fill an empty window or panel with a window ancestor, addressed by `parent_id`, with a lab PythonRepl surface and inert source. Use `surface_operations`, extended lab validation and `surface_event` plus tree. Return `side:client, execution:awaiting_user`. Only a later user Run executes browser Monty |
| `run_python_server`, `RunPythonServer` | Declared and documented in both minimum rooms. Validate source and registered program `surface_id` in authenticated scope, then return the typed disabled result in section 5. No emitter, runner, file read or model call |
| `move_panel`, `MovePanel` | Resolve the stable node, reparent its entire subtree, normalize ordered child IDs on both parents, validate grammar/cycles/depth, call `surface_operations` to serialize the complete control surface and `surface_event` under its stable key |
| `close_panel`, `ClosePanel` | Set selected node visibility to `closed`, inheriting closure through descendants and cancelling their sessions, preserving all accepted content and edges. Rebuild and emit only the control surface through the same two calls. A local pin may keep the view displayed |
| `repair_program`, `RepairProgram` | Exposed only in a validated repair turn. Resolve an existing failed program and replace its source under the same surface identity using `surface_operations` and `surface_event`. Chain ID and attempt come from accepted context. No new window and no independent execution permission |

| Schema policy | Rule |
| --- | --- |
| Model load | Ordinary tool shapes have at most five fields, one enum per choice and at most one nested list. Repair turns expose only inspection and repair. No free-form A2UI, JSON Patch, general JSON Schema or pixel coordinates reach E4B |
| Additional checks | Reject duplicate point IDs, unknown node/group references and catalog mismatch. Validate UTF-8 byte lengths as well as character lengths. Source is at most 12,000 UTF-8 bytes. Whole action envelopes still obey Track A's 16 KiB ceiling |
| Preconditions | Capture layout revision at turn start. Serialize successful tools and refresh that revision after each commit. Reject a competing update with `stale_layout`, return the current compact view and require a fresh tool request |
| Tool identity | Journal accepted publications by logical turn and tool-call identity. Redelivery returns the same receipt. A model calling the tool again under a new identity is a new intent and remains subject to capacity limits |
| Compact return | Mutation tools return `{status, node_id, layout_revision, receipt_id}`. `run_python_client` also returns `side:client, execution:awaiting_user`. Disabled server execution returns section 5's closed result without a receipt or revision change. Errors return `{status:"rejected", code, field}` with bounded strings. `get_workbench` returns the bounded view instead. Source and full component graphs do not echo into tool results |

### After the minimum

| Deferred tool variant | Later scope, excluded from minimum room tools, skills and U01 fixtures |
| --- | --- |
| `place_form`, `PlaceFormAfterMinimum` | Add the filters template alongside intake only when its state-only action contract is implemented |
| `show_chart`, `ShowChartAfterMinimum` | Add required selection_group only with the later linked-selection profile |
| `show_table`, `ShowTable` | Compile data:1 DataTable from the bounded keyed rows. Same operations/emission path as Chart. The model cannot send arbitrary columns, renderer names or HTML |

```python
class PlaceFormAfterMinimum(PlaceForm):
    template: Literal["intake", "filters"]

class ShowChartAfterMinimum(ShowChart):
    selection_group: Id

class ShowTable(Closed):
    title: Title
    rows: Points
    selection_group: Id
    parent_id: Id
```

### What is reusable and what needs package work

| Evidence from `56bf87c` | Design treatment |
| --- | --- |
| `surface_operations(surface_id, components, data)` emits create, component and root-data operations using the basic surface catalog, `S/src/soliplex_a2ui/capability.py:76` | Reuse it for deterministic templates. Custom components carry canonical `@catalogId` overrides |
| `validation_errors` constructs a processor with only `_CATALOG`, the basic catalog, `S/src/soliplex_a2ui/capability.py:96` | Extend package validation to accept the pinned lab, graphics and data catalog manifest. Its present basic-only validator cannot certify those payloads |
| `A2UICapability.get_toolset` exposes a broad generating tool and invokes a nested agent, `S/src/soliplex_a2ui/capability.py:118`, `S/src/soliplex_a2ui/capability.py:158` | Do not expose that broad tool for ordinary workspace placement. Compile the small typed inputs deterministically. No additional model is needed to lay out a form or chart |
| The package constrains Python core to `>=0.6,<0.7`, AG-UI to `>=1.0.0,<1.1` and pydantic-ai to `>=2.53,<3`, `S/pyproject.toml:9` | Resolve and test the actual isolated backend combination later. Do not equate Python core versions with Dart core versions or claim this dependency set already resolves |
| The lab tool constructs a replacement activity in `_event` and returns it in ToolReturn metadata, `L/src/soliplex_a2ui_lab/a2ui_lab.py:48`, `L/src/soliplex_a2ui_lab/a2ui_lab.py:112` | Copy its PythonRepl template idea. Use the chosen package emitter rather than copying `_event` as another authority. Its fixed `dojo-python` ID is replaced by allocated IDs |

### Room skill and runtime context

| Material | Content and installation plan |
| --- | --- |
| Workbench room skill | One short instruction page plus generated API reference. Teach reserved region IDs, incremental parent-ID plus node-kind calls, returned stable node IDs, depth/grammar rules, Python sides and disabled server result, pin precedence, allowed templates, the Run boundary, errors and repair examples |
| Monty API section | Advertise only implemented signatures. Start with `import ui`, immutable constructor handles, list-first construction, `ui.bind`, `ui.Event`, `ui.show` and short `handle_event`. Include `True`, `False`, `None`, no `tkinter`, no `io`, no third-party modules and no star imports |
| Capability upgrade | Add the five staged operations and `ui.graphics.Chart` only after the R3 binding fixtures pass. Generated signatures must match the mounted catalog digest. Do not teach R3's proposed functions as current implementation |
| Dynamic view | Inject a server-owned bounded layout summary and allowed catalogs before each turn. `get_workbench` refreshes it after conflicts. Never concatenate form fields, program stdout or labels into system instructions |
| Catalog manifest | Basic, lab:1, graphics:2 and data:1 only when implemented and validated. Retain graphics:1 for old surfaces. Geo is absent until its renderer is installed |
| Room wiring | Put the tool package in the new stack's own source package. A configured factory installs the tool subset, model profile and skill. This is a proposed factory contract, not a new native room-config field |

**Evidence:** filesystem skills are instruction capabilities loaded from `SKILL.md`, `B/docs/config/skills.md:3` (`origin/main`). Room tools use dotted callable names, `B/docs/config/rooms.md:122` (`origin/main`). Factory agents accept `factory_name`, `with_agent_config` and arbitrary `extra_config`, `B/docs/config/agents.md:218` (`origin/main`). The current Python module exposes constructors, bind, Event and show, `M/packages/soliplex_monty/lib/src/python_ui.dart:103`. R3's generated operation and graphics API is design at `P/hhg-a2ui-r3.md:83`, not proof of implementation.

## 4. Forms and capture

| Template | Fixed controls | Accepted typed context |
| --- | --- | --- |
| `intake@1` | Question TextField, multiple ChoicePicker for north/south, acknowledgement CheckBox, Submit Button | `IntakeSubmit` below, model-turn action `workbench.intake.submit@1` |
| `filters@1` | District ChoicePicker, include-archived CheckBox, Apply Button | `FilterSubmit` below, state-only action `workbench.filters.set@1` |

```python
class IntakeSubmit(Closed):
    question: Annotated[str, Field(min_length=1, max_length=240)]
    districts: Annotated[list[Literal["north", "south"]],
                         Field(min_length=1, max_length=2)]
    acknowledged: Literal[True]

class FilterSubmit(Closed):
    districts: Annotated[list[Literal["north", "south"]],
                         Field(min_length=1, max_length=2)]
    include_archived: bool
```

Reject duplicate district values with semantic validation. Initial acknowledgement is false, so the form is renderable but cannot submit validly until checked. Templates own action names, sources and schemas. The model supplies title and template choice, not an action handler or validation policy.

| Step | Proposed action path |
| --- | --- |
| Resolve | At click time resolve the current bound fields. Use only the full-payload callback. Freeze exactly one immutable envelope |
| Wrap | `{v:1, submissionId, activityMessageId, surfaceRevision, actionSchemaVersion, userAction}`. Generate a canonical UUIDv4 per deliberate submission. A retry reuses the envelope |
| Outbox | Persist the envelope independently of editable drafts before sending. Disable duplicate Submit while pending. Preserve later edits by edit generation |
| Validate before inference | Bound the request and action subtree, reject duplicate JSON keys and unknown fields, authenticate, authorize actor/room/thread, consult the submission ledger, check registry/source/revision/schema, validate context and reserve acceptance |
| Model-turn | Existing thread, empty prompt, no new client user message, envelope in `forwardedProps.a2uiAction`. Reconstruct history from accepted server records. Persist one typed-context adapter record before the first model invocation |
| No-turn | Filters and selection updates use Track A's proposed authenticated action POST and receipt path. They start zero model calls. They are not routed through the model to discover what handler to use |
| Commit | Atomically store effects and receipt. Duplicate identical envelopes return the original receipt before testing a newer revision. Changed content under the same submission ID conflicts |
| Feedback | Invalid context produces safe field errors with zero model calls. A failed commit preserves prior accepted surfaces. Raw `userMessage` is an optional display summary and grants no routing authority |

| Existing evidence | Gap or reuse |
| --- | --- |
| Action closures resolve context when invoked and writable properties require paths, `C/a2ui_flutter-0.4.0/lib/src/component_props.dart:76` | Reuse binding and click-time capture |
| The TextField writer receives text, `C/a2ui_flutter-0.4.0/lib/src/catalog/basic/text_field.dart:204` | Do not assume a numeric-looking text input supplies a JSON number. The two initial forms avoid numeric text coercion |
| RoomScreen now wires timeline actions to `threadView.sendAction`, `D/lib/src/modules/room/ui/room_screen.dart:2735`. Timeline forwards its activity ID, `D/lib/src/modules/room/ui/message_timeline.dart:641` | The old “room clicks go nowhere” gap is stale. Preserve the ID instead of discarding it in the room callback |
| `ThreadViewState.sendAction` wraps only `userAction` and keeps the latest queued action, `D/lib/src/modules/room/thread_view_state.dart:417` | Add Track A wrapper/outbox semantics. Latest-only replacement is unsuitable for distinct form submissions |
| The current orchestrator accepts `a2uiAction` and marks an action-only turn, `D/packages/soliplex_agent/lib/src/orchestration/run_orchestrator.dart:157` | Reuse this current API. Do not blindly port the older embedded controller's `actionOnly` parameter |
| The orchestrator adds `afterMessageId`, `D/packages/soliplex_agent/lib/src/orchestration/run_orchestrator.dart:1387` | Treat this as legacy placement metadata outside the closed v1 action wrapper. Do not add an undeclared field to the frozen envelope. Accepted server history determines placement |
| The older embedded controller also sends only a userAction wrapper, `E/lib/src/modules/room/embedded_conversation_controller.dart:128` | It is a reference for transport, not the complete acceptance contract |
| `apply_user_action` checks dictionary shapes, hashes run ID and appends full JSON as a user message, `S/src/soliplex_a2ui/__init__.py:41`, `S/src/soliplex_a2ui/__init__.py:61`, `S/src/soliplex_a2ui/__init__.py:71` | Extend this package's reader with request-stage accepted-action input, submission identity and typed-context projection. Keep legacy behavior available for other callers. Do not also invoke the legacy JSON-message projection |
| Backend main checks room access and URL/body IDs, then persists run input, `B/src/soliplex/views/agui.py:1127`, `B/src/soliplex/views/agui.py:1141`, `B/src/soliplex/views/agui.py:1157` (`origin/main`) | Insert package acceptance after scoped checks and before action-bearing input persistence or stream startup. Load authoritative room action policy early |

Track A's 16 KiB envelope, context bounds, thread-lifetime ledger, continuation consumption and indeterminate-dispatch behavior apply. References: `P/track-a-action-contract.md:71`, `P/track-a-action-contract.md:81`, `P/track-a-action-contract.md:97`. These are required implementation work. Neither the current emitter nor a disabled Submit button supplies them.

## 5. Mini programs and the execution boundary

| Concern | Proposed behavior |
| --- | --- |
| Client tool | `run_python_client` publishes inert source in a lab PythonRepl surface under an empty window or panel within a window. It does not execute source. The user sees browser/client Python and Run |
| Runtime owner | Plugin session registry keyed by actor/server/room/thread/surface lifetime. The renderer attaches to that registry. Moving or minimizing the window must not create a second runtime |
| Client Run | Freeze source and invocation generation. Show “Loading Monty” until startup completes. Initialize the one session and run source. Subsequent local widget gestures call a short `handle_event(name, context)` in that session |
| Globals and handles | Globals and functions survive successful events. Each invocation gets fresh handles and staging. Keep ordinary data across events, rebuild descriptors or patch data. Never retain an old widget handle for reuse |
| Client limits | Forward `maxSuspensions=10,000,000` per session, 32 MiB memory, one-second feed time and five-second elapsed deadline. Source is at most 12,000 UTF-8 bytes for this room. Output is bounded to 4,000 characters. One handler runs per surface |
| Busy input | Bounded FIFO of 32 discrete local activations. Reserve queue space before publishing their input writes. Reject overflow visibly. Hover, resize and binding repaint enqueue nothing |
| Publication | Stage, validate the complete candidate, compare revisions/generation and publish once. A caught structural host error invalidates the candidate. UI rollback does not promise rollback of Python globals already mutated |
| Timeout, crash, forced Stop | Cancel and invalidate generation, discard staging, close the interpreter, retain the last accepted result read-only and show that Python state was lost. Restart requires an explicit gesture |
| Finite-budget exhaustion | Report exhaustion and require Restart. Do not silently rotate or re-execute prior events. The raised budget is finite, not a claim of indefinite session operation |
| Close versus minimize | Minimize retains idle descendant sessions. Closing any ancestor cancels/disposes all descendant sessions and repair chains. A pinned saved view remains read-only. Reopen restores source and accepted results, with Run required |
| Reload and replay | Never restore an active runtime, queue or execution authorization. Restore declarative results and source. This applies even when a historical record says retrying |

| Program communication | Allowed route |
| --- | --- |
| Build controls in its own window | Yes. Use its authorized `ui` surface only |
| Open a chart | The program can place bounded provisional points under `/export/points` in its own staged data. A host-owned “Open chart from result” button previews and sends `workbench.program.export_chart@1`. A deterministic handler validates points, compiles Chart and adds a panel/surface subtree under `r_canvas` through the same publication service. The export button does not execute Python |
| Share with another program | Explicit export of accepted JSON, followed by the user loading that snapshot into the other program's inputs. That program receives it on its next Run or deliberate local action. No Python-to-Python calls or shared interpreter globals |
| Move windows or close panels | No direct Python layout capability. The agent tools and host controls own layout changes |
| Read server data | Client answer-only host endpoint remains optional later work. Distinct `run_python_server` uses server-side allowlisted data only after deferred U14. No client token, arbitrary URL helper or implicit dump resume |
| Client files | `run_python_client` uses read-only mounted thread workspace snapshots through the plugin. Scope derives from authenticated room/thread registration, with listed-size and streamed-download limits. Mounting or loading files never executes source |

`program.export_chart` context is the minimum `ShowChart` without `parent_id`, plus the current invocation ID. The server selects `r_canvas` and a server-owned selection group, checks provenance against the registered program surface and accepts values as untrusted client data. An accepted export records provenance, not proof that Python computed the values honestly. The user sees a preview before export.

### Python sides, run results and interpreter-state pointer

| Contract | Required behavior |
| --- | --- |
| Server input | `RunPythonServer` has `surface_id` and `source`. Resolve the existing registered program surface through authenticated actor/room/thread context. Enforce the same 12,000 UTF-8 byte source bound. The minimum has no enable flag or fallback to client execution |
| Minimum disabled result | Closed `ServerPythonNotEnabled` with literal fields `{status:"not_enabled", code:"server_runner_deferred", tool:"run_python_server", side:"server", execution:"disabled"}`. Valid requests return this result with no state mutation, receipt, runtime start, data read or background job. Invalid requests return the ordinary typed rejection. Both models see the tool and its disabled description |
| Deferred real server execution | U14 follows the minimum. A future enabled call runs in a pinned server sandbox or server Monty, accepts untrusted source, uses scoped allowlisted server data, and can run unattended only under an approved bounded policy. It has no browser `ui`, browser filesystem, ambient credentials or unrestricted network access. Cancellation, result storage and errors must be explicit. Engine/version, limits, data policy and unattended authorization are U14 BLOCKERs, not choices hidden in this minimum |
| Trace tags for every actual run | `python.side=client` or `python.side=server`, `python.engine` as engine name plus exact version, `room`, `thread`, `surface`, `chain_id` and `invocation_id`. Allocate a chain ID for an ordinary Run as well as repairs. Future server runs use the same keys. A disabled request records a tool diagnostic, never a fabricated server-run trace |
| Client run-result action | After each client initialization, local handler or repair attempt, post a bounded `workbench.program.run_result@1` action with `{side:"client", engine, invocationId, chainId, outcome, output}`. Outcome is `success`, `error`, `timeout`, `cancelled` or `crashed`. Resolve room/thread/surface from authenticated registration, deduplicate invocation IDs, and have the server record the Logfire event with zero model calls. Engine is client-reported metadata, not attestation. Failure to deliver telemetry cannot authorize a rerun |
| Logfire ownership | Claude wires the stack's own service name and secret file according to `P/workbench/PROMPT.md:162`. This amendment references that work only. No Logfire token or direct Logfire exporter goes in the browser |
| AG-UI state pointer | Reserve `/python/handoff/<surfaceId>` for a closed `{side, engine, dump: <file id>, sha256, owner, hop}` object. `side` is `client` or `server`, engine includes exact version, dump is an opaque thread workspace file ID, sha256 is 64 lowercase hexadecimal characters, owner is the authenticated scoped owner, and hop is an integer 0 through 4. It is a reference, never execution permission |
| Dump storage and validation | Dump bytes live only in a thread workspace file, never in AG-UI state, A2UI data, tool returns, run-result actions or traces. On any future transfer, authorize owner/thread/file, enforce byte limits before download, verify SHA-256 and exact engine/dump-format compatibility, and increment hop. Treat dumps as untrusted code. Reject foreign owner, missing file, digest/version mismatch or hop exhaustion. File identity and checksum are insufficient authorization |
| Minimum pointer scope | Define pointer schemas and accepted/rejected fixtures now. Normal minimum runs do not create or resume dumps. An absent pointer is normal. If a pointer is retained with accepted AG-UI state, replay preserves it as opaque metadata and never loads its file or starts an interpreter. Transfer, deserialization and resume belong to a separate handoff unit after U14 policy review |

```python
class ServerPythonNotEnabled(Closed):
    status: Literal["not_enabled"] = "not_enabled"
    code: Literal["server_runner_deferred"] = "server_runner_deferred"
    tool: Literal["run_python_server"] = "run_python_server"
    side: Literal["server"] = "server"
    execution: Literal["disabled"] = "disabled"

class InterpreterStatePointer(Closed):
    side: Literal["client", "server"]
    engine: Annotated[str, Field(min_length=1, max_length=128)]
    dump: Annotated[str, Field(min_length=1, max_length=128)]
    sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
    owner: Annotated[str, Field(min_length=1, max_length=128)]
    hop: Annotated[int, Field(ge=0, le=4)]

class RunResult(Closed):
    side: Literal["client"]
    engine: Annotated[str, Field(min_length=1, max_length=128)]
    invocationId: Id
    chainId: Id
    outcome: Literal["success", "error", "timeout", "cancelled", "crashed"]
    output: Annotated[str, Field(max_length=4000)]
```

| Non-tool schema checks | Rule |
| --- | --- |
| Engine and file identity | Require engine name plus exact version using the pinned engine manifest, beyond the string bounds above. The dump field is an opaque workspace file ID of 1 to 128 characters, not a path or URL. Validate it with the workspace service's identifier grammar, not the node-ID grammar. Owner and file access derive from authenticated scope. No lookup or dump read happens on passive replay |
| Byte budgets | Output is also bounded by the complete 16 KiB action envelope. These result/state models are not model-visible tool inputs, so their field count does not enlarge E4B tool schemas |

### Bounded repair after Run

| State | Rule |
| --- | --- |
| Initial failure | A current Run may authorize up to two repairs. Host state records actor/thread/surface, chain ID, source digest, session generation, pending attempt and expiry. Payload data cannot create this authorization |
| Model repair | Submit a validated `workbench.program.failed@1` action containing bounded source/error plus chain/attempt references. The package reader supplies these as untrusted typed context. Expose only `repair_program` and inspection tools |
| Execute repair | Accept a replacement for that existing program. Automatically run it only when it matches the live local pending chain, exact attempt, generation and accepted source digest. Consume that attempt once |
| Success | End the chain and save its declarative result |
| Exhaustion | After two failed repairs, ask exactly “Do you want to try again?”. Yes grants one additional attempt. No or Stop ends the chain |
| Invalidation | Reload, sign-out, thread switch, close, expiry, user source edit or cancellation revokes the chain. A historical, duplicated or unsolicited repair payload starts zero execution |
| Stateful handler exception | Do not automatically replay a failed or ambiguously completed handler. Its globals may have changed. Offer an explicit restart/repair of initialization |

| Evidence | Reuse or missing work |
| --- | --- |
| Monorepo ReplLimits already declares 10,000,000 suspensions and forwards it into ResourceLimits, `M/packages/soliplex_monty/lib/src/lab_catalog.dart:25`, `M/packages/soliplex_monty/lib/src/lab_catalog.dart:269` | Reuse this implementation. It supersedes R2's proposed budget redesign |
| ResourceLimits describes a session cap and a default of 1000, `R/lib/src/core/resource_limits.dart:83`, `R/lib/src/core/resource_limits.dart:155` | Keep the finite-budget limitation explicit |
| Current `D` lab catalog exposes `onFailure` and retry fields, `D/packages/soliplex_monty/lib/src/lab_catalog.dart:143`. It claims a live pending repair on arrival, `D/packages/soliplex_monty/lib/src/lab_catalog.dart:340` | Repair integration exists in the inspected working source. Add thread/surface scope and remount tests before reusing it in a persistent workbench |
| Current `didUpdateWidget` updates delivered source and editor text, `D/packages/soliplex_monty/lib/src/lab_catalog.dart:363` | Stable-ID repairs cannot rely on initial widget mount. Move pending-attempt claiming into the session controller's accepted-source-revision path, so a valid replacement executes once without requiring remount |
| Current repair failure handling clamps budget and asks after failure, `D/packages/soliplex_monty/lib/src/lab_catalog.dart:326`, `D/packages/soliplex_monty/lib/src/lab_catalog.dart:461` | Preserve default two and the explicit extra-attempt interaction. Do not infer full lifecycle safety from these functions alone |
| The current nested UI commit validates in a fresh basic-only processor, `D/packages/soliplex_monty/lib/src/lab_catalog.dart:536` | Add negotiated custom catalogs and stable-instance publication. Processor replacement alone does not establish focus/session preservation |
| Probe chart taps write a label and call an action, `Q/lab_chart.dart:21`. Its schema has bounded label/value bars, `Q/lab_chart_api.dart:14` | Useful interaction/data examples, not the new typed Chart implementation |
| Probe workspace load downloads before constructing its bounded workspace, `Q/lab_workspace.dart:93`. Monorepo mounting checks listed sizes before download and actual sizes after, `M/packages/soliplex_monty_workspace/lib/src/workspace_mount.dart:186` | Prefer the monorepo mount and add streamed download limits. Do not claim the probe's final byte check bounds network allocation |

The handoff note reports mismatched dump versions and recommends moving answers at `P/monty-handoff.md:5` and `P/monty-handoff.md:234`. I prefer answer-only data exchange and define the owner-required file pointer above for future interpreter transfer. **UNVERIFIED:** I did not rerun its handoff demos. Browser reload in this design never uses interpreter replay as a fallback.

## 6. Charts, tables and linked selection

| Component | First workbench contract |
| --- | --- |
| Chart | Implement R3 graphics:2 `Chart` with `spec`, string-list `selection`, `description`, optional `event`, `onTap` and bounded height. Support bar and categorical line. Use `fl_chart ^1.2.0` and record the actual resolution. The small tool input compiles to the richer component schema |
| Legacy charts | Retain graphics:1 and the four legacy graphics entries when assembling graphics:2, as R3 specifies. Do not change their encoded-values/numeric-selection contract |
| DataTable | Add `urn:soliplex:catalog:data:1`, component `DataTable`. Fixed columns ID, Label and Value for this slice. Rows use `Point` records, bound through `rows`. Add string-list `selection`, description and optional event/onTap. Use Flutter DataTable with bounded pagination, keyboard selection and an accessible row summary |
| General tables | Arbitrary editable columns and spreadsheet formulas are later scope. A basic Row/List/Text fallback may display the same data when data:1 is unavailable, but it does not satisfy interactive-table acceptance |
| Limits | Agent tools allow 32 rows/points and one line series. Component-side R3 bounds still apply to non-tool producers. Reject non-finite values, duplicate IDs and missing numeric cells rather than inventing zero |
| Identity | Set `selectionKey` to the row's stable domain ID, such as `north`. Selection follows IDs across sorting and replacement, not renderer indices |

| Evidence | Consequence |
| --- | --- |
| BasicComponents.all contains no table, `C/a2ui_flutter-0.4.0/lib/src/catalog/basic/basic_catalog.dart:148` | A native selectable table needs a new component. Do not claim basic already supplies DataTable |
| Existing graphics:1 BarChart takes a JSON string and numeric selected index, `M/packages/soliplex_catalogs/lib/src/surface_catalog.dart:20` | Preserve it. The proposed Chart uses a new catalog revision |
| Probe BarChart draws rows with containers, `Q/lab_chart.dart:53` | It is not an existing fl_chart implementation to relabel |
| fl_chart supplies a BarChart widget over BarChartData, `C/fl_chart-1.3.0/lib/src/chart/bar_chart/bar_chart.dart:11`, and typed touch responses, `C/fl_chart-1.3.0/lib/src/chart/bar_chart/bar_chart_data.dart:673` | Implement a renderer adapter translating tap-end indices through a current immutable ID table |
| R3 defines bar/line and `onTap`, `P/hhg-a2ui-r3.md:327`, `P/hhg-a2ui-r3.md:420` | Follow R3 rather than R2's five-family/onSelect proposal. Chart is still build work |

### Shared bound paths across independent surfaces

| Layer | Proposed rule |
| --- | --- |
| Canonical selection | The control surface owns `/workbench/shared/selections/<group>`. Each content surface gets a host-maintained local mirror at `/shared/selections/<group>` |
| Registration | Each Chart/Table binding is registered with its group and allowed source. The model cannot bind a surface into another thread or arbitrary state path |
| Write | A user activation proposes a unique string list plus a frozen event. Validate them together, update the thread's client SelectionStore and all registered mirrors in one local-input transaction, then persist through a state-only Track A action |
| Acknowledge | The accepted journal record updates canonical control data and shared-state revision. Fold it once. A rejected/stale update restores the accepted selection and reports a conflict |
| Avoid loops | Mirror writes and programmatic accepted updates invoke zero actions, Python handlers or model runs. Only the originating deliberate activation can dispatch |
| Explicit model interaction | “Explain selection” is a separate model-turn button. Ordinary highlighting never calls a model |
| Isolation | Equal pointer strings in separate A2UI processors do not create shared state. The registered mirror adapter is required. Basic renderer write access is surface-local, `C/a2ui_flutter-0.4.0/lib/src/component_props.dart:76` |

## 7. Persistence, replay and conflicts

| State | Owner and storage | Reload/replay behavior |
| --- | --- | --- |
| Logical tree | Server, complete scoped control-surface tree plus thread journal | Restore root, stable IDs, ordered edges, payloads and visibility in sequence. Validate the entire tree before exposing any node |
| Accepted content | Server, latest full activity snapshots, catalog digests, revision and action manifests | Restore passively with original activity and surface IDs |
| Accepted form values and exported results | Server, transactional state and receipts | Show accepted values and provenance without calling handlers |
| Shared selections | Server accepted control data, with bounded pending device overlay | Restore accepted selection, then reconcile an already frozen submission by status |
| Window rectangles, split widths, z-order and user visibility overrides (minimized, hidden, pinned) | Device-local actor/server/room/thread/stable-node-ID key | Persist on gesture completion and restore after the accepted server tree. Clamp geometry and apply visibility overrides without execution. Geometry and visibility use the same reconciliation and sign-out clearing rules. If an ID is absent from the authoritative server tree, discard its geometry and visibility overrides, never recreate the node. Another device uses semantic defaults |
| Parent/order overrides and shell tab selection | Device-local, stable node ID keys | Apply after accepted tree. Revalidate depth/cycles and parent existence. For a node still present, keep invalid overlays in a recoverable conflict, never silently orphan a child. For an absent node ID, discard its overrides under the same rule as geometry and visibility. Ancestor close still revokes descendant execution |
| Unsent form/source draft | Device-local, activity/surface/revision/operation-hash/edit-generation key, maximum 64 KiB per surface | Restore only on matching accepted base. Preserve a changed-base draft as a recoverable conflict |
| Submission outbox | Device-local frozen envelopes, separate from drafts | Query receipt/status. Explicitly resend identical input if needed. Never allocate a new submission merely because a page reloaded |
| Active interpreter globals, host objects and queues | Memory only, client plugin or future server runner | Never restore implicitly. Show “Python session is not running” beside the saved result |
| Interpreter handoff | AG-UI state has only section 5's pointer, dump bytes in an authorized thread workspace file | Preserve pointer passively. No file fetch, deserialization or resume during reload/replay. Minimum has schemas/fixtures only, no transfer executor |
| Retry permission | Memory only, scoped live chain | Never restore or infer from a saved `retry` field |

| Conflict case | Proposed handling |
| --- | --- |
| Same record twice | Ignore duplicate record ID. One layout change, one receipt, zero callbacks |
| Stale or out-of-order record | Hold until missing sequence records arrive. Reject regressing surface revisions |
| Identical operations | Preserve controller and local draft. Update trusted metadata |
| Appended accepted operations | Validate the full materialized candidate, apply the new effect once and preserve untouched dirty paths |
| Replacement operations | Validate before replacing. Reset affected accepted bindings and retain prior dirty values in a conflict drawer. Reconcile unchanged renderer nodes |
| Local edit after Submit | Receipt clears only the submitted edit generation. Later edits survive |
| Dispatch crash | Persist indeterminate status and block automatic redispatch. Display an explicit unresolved outcome |
| Sign-out or actor change | Cancel work, dispose sessions and clear that actor's local drafts, outbox and layout overrides. Server accepted records remain subject to normal thread retention |
| Server/thread removal | Remove associated local cache through the existing ownership/cleanup path. Tombstones prevent late execution/publication into a recreated surface |

**Evidence:** the current store keeps identical operations, applies suffixes and disposes a changed prefix before rebuilding, `D/lib/src/modules/room/a2ui/surface_scope.dart:29`. The controller processes operations individually, `D/lib/src/modules/room/a2ui/surface_controller.dart:55`. Its snapshot includes current bindings, `D/lib/src/modules/room/a2ui/surface_controller.dart:67`. These are useful seams, not atomic batches or durable draft storage. The projection computes run attribution from current conversation state, `D/packages/soliplex_client/lib/src/application/a2ui_activity.dart:76`. New journal metadata must carry trusted attribution instead.

Replay invariant: restoring any accepted workspace with interpreter, handler, model and tool hooks set to fail must still succeed. A2UI activities already bypass the client model transcript, `D/packages/soliplex_client/lib/src/application/transcript_events.dart:53`. Apply that exclusion to server history reconstruction too. Persist one accepted typed-context record per submission, not raw surface graphs or repeat action messages.

## 8. Fit with the existing frontend and plugin

| Location | Proposed change | Boundary |
| --- | --- | --- |
| `lib/src/flavors/workbench.dart` | Add a workbench flavor using the standard composition kit. Inject one room-presentation configuration and the negotiated catalogs | No handwritten router or duplicate room routes |
| RoomAppModule and RoomScreen | Add optional presentation selection, default `chat`. In workbench mode assemble existing thread navigation, timeline, composer, file controls and workspace host | Workbench presentation remains inside the room feature, avoiding sibling feature imports |
| `lib/src/modules/room/workbench/` | Typed tree decoder/reducer with whole-tree grammar/cycle/depth checks, recursive split/tab/panel/window host, panel chrome, stable surface mount registry, ID-keyed local geometry store and shared selection coordinator | No `dart_monty` imports. Room-only state stays here |
| `interfaces/` and `shared/` | Small presentation/mount and execution-status contracts only where needed for injection | These types expose data and callbacks, not concrete room controllers or Monty types |
| `stores/` | Add a store only if a second feature actually consumes it. Otherwise integrate room-owned cleanup into RoomAppModule | Follow ADR-005 rather than creating global state preemptively |
| `soliplex_client` | Preserve trusted surface/journal metadata, commit-aware folding and hydration/action APIs | Protocol/data only, no Flutter layout and no interpreter dependency |
| `soliplex_agent` | Preserve action-only semantics, accepted-context continuation identity and no synthetic user turns | No renderer or interpreter dependency |
| `soliplex_catalogs` | Chart/DataTable schemas, semantic validators and Flutter renderers | Catalogs receive interaction callbacks and never import Monty |
| `soliplex_monty` | Client session registry, measured surface viewport, runtime lifecycle, generated `ui` bridge, staging, repair chain, run-result action and result export adapters | The only Soliplex plugin package depending on `dart_monty` |
| Plugin-enabled app entry | Compose workbench flavor plus catalog/session callbacks | The app can depend on `soliplex_monty` but never directly on `dart_monty` |
| New stack tool package | Tree tools, templates, declared disabled server Python tool, server-recorded client run traces and configuration. Use shared `soliplex-a2ui` emitter/reader services. Real server runner is deferred U14 | Package extensions belong upstream in the chosen emitter package, not copied private implementations |

| Existing seam | Design requirement |
| --- | --- |
| Room module builds routes and passes RoomScreen dependencies, `D/lib/src/modules/room/room_module.dart:94`, `D/lib/src/modules/room/room_module.dart:137` | Preserve route ownership and authentication |
| RoomScreen deliberately keeps one stable ChatInput, `D/lib/src/modules/room/ui/room_screen.dart:2834` | Do not key or recreate the composer when subtrees move or the first thread is created |
| Type-to-focus has an EditableText guard, `D/lib/src/modules/room/ui/room_screen.dart:1361`, `D/lib/src/modules/room/ui/room_screen.dart:1392` | Preserve it for form editors and program source, including paste and keyboard shortcuts |
| Timeline prefers an ancestor ChatSurfaceScope, `D/lib/src/modules/room/ui/message_timeline.dart:623` | Hoist one thread-owned scope above timeline and workspace, so virtualized reference cards do not own content lifetimes |
| Standard flavor already accepts extra catalogs, `D/lib/src/flavors/standard.dart:24` | Standard chat remains the default presentation and retains its existing catalog injection behavior |
| Current frontend root still pins core 0.7.0 and Flutter 0.3.0, `D/pubspec.yaml:25`. Monorepo plugin uses `^0.8.0`/`^0.4.0`, `M/packages/soliplex_monty/pubspec.yaml:13` | Port the target version line into the isolated implementation. Do not assume the source worktree has already migrated |
| Migration report records changed envelope keys and a pre-existing failing test, `M/docs/A2UI-0.8-MIGRATION.md:25`, `M/docs/A2UI-0.8-MIGRATION.md:87` | Emit canonical `@` component keys and diagnose the inherited failure before claiming a green baseline. The report is not a new test run |

Mount invariant: moving a subtree changes parent edges, resizing/minimizing changes geometry or visibility, and each preserves descendant IDs, surface identity, drafts and selected shell tabs. Maintain a stable widget identity and plugin session registry across reparenting. A failed candidate cannot dispose the prior accepted editor. Deletion, thread departure and sign-out have explicit awaited teardown. ADR-004's disposal contract remains in force, `E/docs/adr/ADR-004-module-composition-contract.md:79`.

## 9. Phased build plan and demonstrations

All phases below are future implementation after owner review. Sizes include meaningful deterministic tests. S means roughly 1 to 2 developer days, M means 3 to 5, L means 6 to 10. These are engineering estimates, not measured schedules. Dependencies run in order. Optional maps, full CSV tooling and interpreter transfer/resume are excluded. Pointer schemas and the disabled server tool are included. Real server execution follows the minimum as deferred U14.

| Phase | Size | Deliverable | Model-free acceptance and completion evidence |
| --- | --- | --- | --- |
| W0, freeze source and protocol | S | Inventory the evolving source, lock target versions/catalog digests, define the nested control-surface schema, grammar, stable IDs, Python-side results and file-pointer fixtures. Confirm backend dependency resolution in the later isolated environment | Load fixed basic/lab/graphics/data candidates under target validators. Reject unknown catalogs, duplicate envelope keys and invalid references. Record the inherited failing test diagnosis. No live inference |
| W1, accepted publication and replay | L | Extend the chosen emitter validator and action reader, stable publication service, journal, ledger and hydration. Implement proposed no-turn routes | Commit content+layout together. Kill delivery after commit, hydrate and recover both. Inject validation/DB failure and preserve both prior states. Duplicate, reorder and omit records. Test request rejection before model persistence, duplicate submission across restart and indeterminate dispatch |
| W2, room presentation | M | Workbench flavor and recursive room-owned tree host, protected chat/regions, split/tab/panel/window/surface nodes, subtree moves/close, resize/minimize/pin and ID-keyed local storage | Fixed sidebar panel/tabs, canvas split and window-owned split fixtures at 360, 900 and 1440 logical pixels. Assert readable leaf widths, reachable controls and zero execution on responsive stacking. Reject depth 9, cycles and protected-region edits. Move a focused form and program without losing draft/session identity. Pin then inject an agent move/close. Reload and clamp geometry. Count zero interpreter starts. Verify standard chat layout and normal send/cancel still work |
| W3, forms and capture | M | Intake/filters templates, full wrapper/outbox, action-only bridge and field feedback | Edit at click time, verify exactly one complete envelope and no invented user message. Duplicate with a new backend run ID and obtain the same receipt. Reject wrong types, source, actor, room, revision, oversized bodies and unknown fields before the model stub is invoked. Preserve late edits after acknowledgement |
| W4, charts, table and shared selection | L | R3 bar/line adapter over fl_chart, bounded DataTable and cross-surface mirrors | Render north=80, south=60 and negative bars. Tap/sort/reorder and retain domain IDs. Select in either panel and highlight the other with zero model/Python calls. Programmatic updates emit no action. Inject failure in the second local write and require no partial selection/event. Reject nulls, duplicate IDs and invalid live specs |
| W5, program windows and repair | L | Client session registry, measured viewport, raised budget, stable staged publication, reset UI, scoped retry, server-recorded run-result traces and explicit chart export. Declare disabled run_python_server now. Real server runner follows minimum in U14 | Real Monty runs a fixed counter for 120 clicks with persistent globals. A budget of 50 is enforced. Mount/move/minimize/replay starts zero new code. Timeout/crash/late callback cannot publish. Scripted model replies fail twice then succeed, and fail three times to reach the exact retry question. Replay a forged chain and require zero execution. Export points and create one chart without inference |
| W6, end-to-end release checks | M | Regression, browser fixtures, retention/recovery and both live demos | Restart server and browser, fold records twice and compare accepted layout/data. Sign out and verify local cleanup. Test pending submission, active Run, missing journal part and capacity limit. Browser release build preserves focused input, worker asset paths and passive reload. Capture per-phase gate results |

Estimated total is 28 to 47 developer days for the complete contract. Existing implementations reduce that only after their fixtures pass. W1 is substantial durable-state work. Rendering a few panels does not complete persistence, validation or safe retry acceptance.

### Required code gates in the implementation phase

| Check | Proposed execution scope |
| --- | --- |
| Analyzer configuration | Apply `very_good_analysis` and the package-level DCM options to every new/touched Dart package and the app, as required by `P/workbench/PROMPT.md:27`. The reference includes both at `D/packages/soliplex_agent/analysis_options.yaml:1` |
| Analyze and metrics | Run `flutter analyze`, `dcm analyze` and `dcm calculate-metrics` for all touched Dart implementation and test paths. Resolve new violations or record an owner-reviewed existing baseline without silently weakening gates |
| Metric thresholds | Reference DCM thresholds are CC 10, LOC 40, parameters 5 and nesting 3, `D/packages/soliplex_agent/dcm_options.yaml:1`. These are inherited requirements, not proposed changes to gates |
| Runtime tests | Native and Chrome tests for pure-Dart bindings, real-worker tests for execution, Flutter widget tests for layout/focus and browser release smoke tests. Check dart2js nonce behavior and cache-busted worker URLs |
| Backend tests | Strict schemas, metadata forwarding, request-stage rejection, ledger, database rollback, restart and hydration with a capturing model stub that fails unexpected calls |
| Architecture | Existing import-boundary checks, no app/client/agent direct `dart_monty` dependency, catalogs independent of Monty, awaited teardown and standard-flavor regression |
| Design-phase validation | Checked all ten numbered sections, three ASCII mockups, citation-file existence and line bounds, JSON syntax and prohibited prose. The earlier nine-model schema check is historical. Amendment validation covers the revised small tool schemas and tree/pointer examples. These checks do not prove implementation behavior. Flutter/DCM code checks are not applicable to this Markdown file. No package resolution or build was run because those write repository state |

### Model profiles

| Profile | Exact requested configuration | Capability requirement |
| --- | --- | --- |
| Glimmer | `http://MODEL_HOST:11450/v1`, `Inferact/Muse-Glimmer-30B-NVFP4-W4A4`, `chat_template_kwargs.reasoning_strength=medium`, at least 4096 output tokens | All tools and generated programs. Reasoning remains enabled |
| E4B | Ollama `http://OLLAMA_HOST:11434`, `gemma4:e4b`, thinking off. Use a 4096 output-token ceiling for complete program authoring, short tool returns and serialized calls | Same features and acceptance. No feature requires Glimmer or a frontier model |
| Shared policy | Title/auxiliary agents use the selected local profile too. Pin served model revision, runtime and catalogs in demo evidence | **UNVERIFIED:** endpoint reachability, provider-specific thinking-off mapping and current served revisions. Probe in the later live phase |

### Live demo script, run once on each profile

Use fresh threads, synthetic fixture data and the same prompts. Record exact prompts, tool arguments, receipts, source, model profile, catalog/runtime revisions, attempts and screenshots. Live checks supplement deterministic acceptance.

| Step | Prompt or user gesture | Expected observation |
| --- | --- | --- |
| 1 | Sign in to the isolated workbench and choose the model profile. Ask “Open an intake form on the left and an evidence panel on the right” | Two panel/surface subtrees under reserved regions, existing chat remains usable, zero interpreter starts |
| 2 | Enter “Compare north and south”, select both and check acknowledgement. Submit once | One validated action-only turn and receipt. No synthetic chat question. The explanation reflects accepted values |
| 3 | Ask “Show north 80 and south 60 as a bar chart and table, linked by district” | Chart on canvas and keyed table. Select south in the table, then north in the chart. Both highlights agree without model or Python calls |
| 4 | Pin the chart, drag the table and minimize the evidence panel through its panel chrome. Ask “Move the chart to the right” | Pin keeps the chart placement. The user-minimized evidence panel enters the tray. The local table move survives |
| 5 | Ask “Write a mini program with units and rate controls, a Recalculate button and a persistent click counter. Start at 4 and 25. Use the supplied ui API” | create_container creates a window and run_python_client fills it with complete model-written source. It stays idle until Run. Both models are allowed to author it |
| 6 | Press Run, set 4 and 25, press Recalculate, then change units to 5 and repeat | First startup shows “Loading Monty”. Results are 100 then 125. Counter persists across local events. Server records python.side=client run-result traces with engine, room, thread, surface and chain ID. No model calls for these clicks |
| 7 | Use “Open chart from result” on a program that exports keyed points | Explicit preview and one deterministic chart publication. The program does not gain direct layout authority |
| 8 | Request a deliberately failing one-off program, press Run and observe repairs | Log initial attempt and at most two automatic repair attempts separately. If all fail, show “Do you want to try again?”. No or Stop ends the chain |
| 9 | Edit an intake field without Submit, minimize the program and reload | Accepted layout/chart/table plus matching draft return. Saved program result is visible. Python starts zero times and repair does not resume |
| 10 | Replay a stored receipt, then retry the identical frozen action | Same receipt, no duplicate effects. Final screenshot includes nested sidebar tabs, canvas split and a window-owned layout. Invoke run_python_server with fixed valid input and verify its typed not_enabled result with zero runtime starts |

| Failure during live demo | Required response |
| --- | --- |
| Model writes unsupported API or mutates a handle | Show the actual error and bounded repair outcome. Do not substitute another model or fabricate a successful screenshot |
| Wrong arithmetic/data/selection | Compare to the deterministic oracle and mark the run failed |
| Cannot finish within two repairs | Keep the explicit retry question and record failure for that model. A reviewed fixed fixture may diagnose infrastructure separately but cannot replace the live authorship result |
| Reload executes Python | Release-blocking failure |

### Isolated deployment handoff

| Item | Future target, not a verified installation |
| --- | --- |
| Stack | `~/dev/soliplex-a2ui-workbench`, distinct Compose project `soliplex-a2ui-workbench` |
| Address | `https://soliplex-a2ui-workbench.localhost:9743`, HTTP 9700 |
| Sign-in | Local Authelia user `$WB_ADMIN_USER` with a password the operator chooses, admin. **UNVERIFIED:** account and stack availability |
| Existing stacks | Dojo 9200/9543, A2UI lab 9600/9643 and AFSOC 9443 remain outside this task |
| Later operator checklist | Carry forward secret rotation, Docker `/tmp` fix, remapped nginx/Authelia ports, in-place bind-mount writes, unlimited static-asset rate on both server blocks, wasm gzip, nginx restart and hard reload from `P/workbench/PROMPT.md:75` |
| Isolation evidence required later | Record Compose project, container labels, published ports and target URL before deployment. Do not infer isolation from a directory name |

## 10. DECISION items for the owner

These choices concern the new workbench. They do not reopen the emitter, model, version, map, session, authorship, retry or safety decisions already in force.

| Item | Recommendation | Effect |
| --- | --- | --- |
| DECISION: Protocol | Choose (c), one registered A2UI layout surface | Approve the aggregate layout/control contract and commit-aware reducer |
| DECISION: Workspace and user overrides | Private per-thread workspace, same-device pins/moves/hides override agent placement until explicit reset | Predictable control without shared-room collaboration or cross-device geometry synchronization |
| DECISION: First component scope and capacity | Bar/line Chart, fixed keyed numeric DataTable, 12 open panels and 3 live program sessions | Keep the typed tool set small. Defer maps, arbitrary tables, broader chart kinds and full CSV ingestion |
| DECISION: Program communication | Explicit typed export and user-controlled snapshot import, with no direct Python layout or cross-program calls | A program can offer a chart without acquiring shell authority. Client/server data exchange prefers answer-only results. The separate server tool is disabled in minimum. Interpreter-state metadata uses section 5's file pointer |
| DECISION: Local retention | Keep drafts and overrides across same-device reload, clear them on sign-out, retain accepted server records for the thread lifetime | Suitable for shared demo devices. No automatic restoration of globals. Optional handoff dumps belong only in thread workspace files behind section 5's pointer |
| DECISION: Completion bar | Require W0 through W6 and Track A durability/validation before calling the prototype complete | Accept the 28 to 47 day estimate and avoid presenting a panel-only shell as the finished workbench |

### Verification limits at handoff

| Status | What remains unverified |
| --- | --- |
| UNVERIFIED, knowledge index | All three searches failed. Local accepted ADRs and owner plans are the available decision evidence |
| UNVERIFIED, missing input | `monty-codegen-skill.md` was absent. The design specifies a later room skill from opened APIs and owner constraints |
| UNVERIFIED, dependency compatibility | The selected Python emitter constraints against the eventual backend, the complete target Flutter composition and final resolved Chart dependencies were not installed or executed |
| UNVERIFIED, integration | Atomic multi-surface commits, control-surface decoding, Track A acceptance/outbox/ledger, stable reparenting, shared selection mirrors, DataTable and scoped program export/retry need the proposed tests |
| UNVERIFIED, live behavior | Neither model endpoint nor a stack/account was contacted. Model reliability, authoring latency, browser performance and live demos were not measured |
| UNVERIFIED, inherited test failure | The migration report records one pre-existing Monty failure at `M/docs/A2UI-0.8-MIGRATION.md:87`. I did not rerun or diagnose it |
| UNVERIFIED, handoff research | I read `P/monty-handoff.md` but did not independently reproduce its engine/dump compatibility experiments. This minimum defines the file pointer but requires no dump transfer or resume |
| Verified document boundary | Original phase wrote this design with three inline mockups. This amendment changes only this design and WORK-ORDER-P3.md. No implementation, stack setup, Git writes or containers are part of the amendment |

## Owner answers (2026-11-19)

| DECISION | Answer |
| --- | --- |
| Protocol | (c) layout surface, as recommended |
| Workspace and user overrides | Private per-thread workspace, user pins, moves and hides win until reset |
| First component scope | Bar and line Chart, keyed numeric DataTable, 12 panels, 3 live program sessions |
| Program communication | Explicit export and user-chosen import only |
| Local retention | Drafts and overrides survive reload, cleared on sign-out |
| Completion bar | **Changed.** The PROMPT.md phase 3 minimum ships first: chat, side bar, canvas, window, tools for a form, a chart and a mini program, tests, gates, a live demo on both models. W5 and W6 hardening follows |
| Build lanes | Codex: Luna implements, Sol writes work orders and tests, fresh Codex plus agy review each phase. Claude runs gates and demos |
| Source drift | Snapshot `exp-dojo-a2ui` and `soliplex-a2ui-lab` now. Port later changes deliberately |

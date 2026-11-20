# Soliplex workbench prototype

This directory holds a prototype of an agent-arranged workbench layout for Soliplex. It includes the design, build instructions, backend tools and stack setup script for team review. The Flutter code lives in `lib/` and `packages/` of this repo on branch `exp/workbench`.

| Path | Contents |
| --- | --- |
| `docs/PROMPT.md` | Original brief and owner directions |
| `docs/WORKBENCH-DESIGN.md` | Layout, protocol, persistence and implementation design |
| `docs/WORK-ORDER-P3.md` | Prototype work order and acceptance checks |
| `docs/STACK.md` | Stack handoff, adaptations and verification evidence |
| `docs/evidence/` | Screenshots added later by Claude, referenced by the docs |
| `backend/soliplex_a2ui_workbench/` | Backend package and unit tests |
| `stack/setup-stack.sh` | Guarded host setup, build and verification steps |
| `stack/workbench.env.example` | Configuration template |

To bring up the stack, first review [the stack handoff](docs/STACK.md), including its prerequisites, blockers and required source checkouts. The script expects those checkouts beneath `DEV_ROOT`, including the template, lab snapshot, frontend worktree and local Monty dependency. It requires `git`, `uv`, Python 3, `rsync`, Docker, Flutter and DCM on the host.

From the repository root, copy the configuration template:

```bash
cp workbench/stack/workbench.env.example workbench/stack/workbench.env
chmod 600 workbench/stack/workbench.env
```

Fill in the copied file locally. It is an ignored shell env file, sourced by the script. Quote values as shell literals. Set `DEV_ROOT` to an absolute path without a trailing slash or symlink aliases. Set `MODEL_HOST` and `OLLAMA_HOST` to reachable hosts without a scheme or port. Choose `WB_ADMIN_USER` and `WB_ADMIN_PASSWORD`. The login also supplies the display name and email local part. `LOGFIRE_ENV_FILE` is optional and defaults to `$DEV_ROOT/.env`, which must contain `LOGFIRE_TOKEN`. Keep passwords and tokens out of review material.

`SOLIPLEX_WORKBENCH_ROOMS` is an optional comma-separated allow-list of room IDs whose AG-UI run endpoint accepts workbench actions. It defaults to empty; add workbench room IDs explicitly and leave legacy `a2ui-lab` rooms out. The backend workbench database uses `SOLIPLEX_WORKBENCH_DB`, defaulting to `/data/workbench/workbench.sqlite3`; step3 mounts a named Compose volume at `/data/workbench`.

Review the script, then run the steps in order:

```bash
bash workbench/stack/setup-stack.sh step1
bash workbench/stack/setup-stack.sh step2
bash workbench/stack/setup-stack.sh step3
bash workbench/stack/setup-stack.sh step4
bash workbench/stack/setup-stack.sh step5
bash workbench/stack/setup-stack.sh step6
bash workbench/stack/setup-stack.sh step7
```

The steps generate the separate stack, rotate initial secrets, configure models and authentication, initialize services, configure the admin, build and deploy the frontend, and probe the installation. Follow the retry rules in `docs/STACK.md`. The project is `soliplex-a2ui-workbench`, with HTTP port 9700 and HTTPS port 9743. Open `https://soliplex-a2ui-workbench.localhost:9743` and sign in with the configured login and chosen password. Complete the manual browser acceptance checks and retain the screenshot references under `docs/evidence/`.

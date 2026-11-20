#!/usr/bin/env bash
set -euo pipefail
SCENARIO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -e "$SCENARIO_DIR/node_modules" ]]; then
  ln -s "${WB_NODE_MODULES:-$HOME/dev/soliplex-embed-probe/node_modules}" "$SCENARIO_DIR/node_modules"
fi
exec node "$SCENARIO_DIR/run.mjs" "$@"

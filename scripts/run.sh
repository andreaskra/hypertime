#!/usr/bin/env bash
# Kills any running instance, rebuilds and launches. Extra arguments go to the app.
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -x Hypertime 2>/dev/null || true
scripts/build-app.sh
if [ "$#" -gt 0 ]; then
  open dist/Hypertime.app --args "$@"
else
  open dist/Hypertime.app
fi

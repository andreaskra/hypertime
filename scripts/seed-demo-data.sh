#!/usr/bin/env bash
# Launches with a separate, seeded database for screenshots and design QA.
set -euo pipefail
exec "$(dirname "$0")/run.sh" --seed-demo

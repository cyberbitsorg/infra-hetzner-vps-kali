#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v bats >/dev/null 2>&1; then
  exec bats tests/
fi
echo "bats not installed; install with 'brew install bats-core'." >&2
exit 1

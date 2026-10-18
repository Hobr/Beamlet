#!/usr/bin/env bash
# Format2 end-to-end verification over fresh test files and two OS processes.
#
#   scripts/deployment/durable-e2e.sh            # isolated temp directory
#   DURABLE_E2E_DIR=/abs/dir scripts/deployment/durable-e2e.sh
#
# Phase one installs the datasets with the explicit operator action, boots the
# host wiring, commits one durable Agent turn through the Runtime with a
# deterministic model and Tool, then exits (the host process is gone). Phase two
# is a new OS process that reopens the same files, proves durable admission,
# restores paused, continues explicitly, exports and verifies the trace, and forks
# a safe committed position via immutable references (not a copied checkpoint).
# Nothing here is a physical power-loss or cross-host claim.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
dir="${DURABLE_E2E_DIR:-$(mktemp -d -t beamlet-durable-e2e-XXXXXX)}"
test_file="apps/beamlet_app_server/test/beamlet/durable_e2e_test.exs"

mkdir -p "$dir"
export DURABLE_E2E_DIR="$dir"
export MIX_ENV=test

cd "$root"

echo "== phase 1 (process $$): initialize fresh datasets and commit one durable turn"
mix test "$test_file" --only durable_e2e_phase1 --max-failures 1

echo "== phase 2 (new process): restart, restore paused, continue, export, fork"
mix test "$test_file" --only durable_e2e_phase2 --max-failures 1

echo "== durable end-to-end verification passed; evidence directory: $dir"
ls -1 "$dir"

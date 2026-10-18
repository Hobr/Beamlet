#!/usr/bin/env bash
set -euo pipefail
export ERL_FLAGS='+S 2:2'
logs=$(mktemp -d /tmp/beamlet-acceptance.XXXXXX)
printf 'Evidence directory: %s\n' "$logs"
mix format --check-formatted >"$logs/format.log" 2>&1
mix compile --warnings-as-errors >"$logs/compile.log" 2>&1
mix test --seed 631927 >"$logs/tests.log" 2>&1
python3 -B scripts/deployment/test-cli-pty.py >"$logs/pty-reader.log" 2>&1
# Isolated names/cookie, stdio peer control and finite peer lifecycle in tests.
cookie=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
test_name="beamlet_acceptance_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
elixir --sname "$test_name" --cookie "$cookie" -S mix test --only distributed --seed 631927 >"$logs/distributed.log" 2>&1
mix credo --strict --all >"$logs/credo.log" 2>&1
mix dialyzer >"$logs/dialyzer.log" 2>&1
mix sobelow >"$logs/sobelow.log" 2>&1
mix xref graph --format cycles >"$logs/cycles.log" 2>&1
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite >"$logs/build.log" 2>&1
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_cli --overwrite >"$logs/build-cli.log" 2>&1
MIX_ENV=prod mix tailwind beamlet_web --minify >"$logs/tailwind.log" 2>&1
MIX_ENV=prod mix esbuild beamlet_web --minify >"$logs/esbuild.log" 2>&1
MIX_ENV=prod mix phx.digest >"$logs/digest.log" 2>&1
MIX_ENV=prod mix release beamlet_web --overwrite >"$logs/build-web.log" 2>&1
BEAMLET_CHECK_LOG_DIR="$logs/copied" bash scripts/deployment/check-release.sh >"$logs/release.log" 2>&1
if env -u SECRET_KEY_BASE MIX_ENV=prod mix run --no-start -e ':ok' >"$logs/web-secret.log" 2>&1; then
  echo 'Web missing-secret check unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'SECRET_KEY_BASE is missing' "$logs/web-secret.log"
git diff --check >"$logs/whitespace.log" 2>&1

PYTHONDONTWRITEBYTECODE=1 python3 -B scripts/deployment/test-check-named-release.py >"$logs/python-cleanup.log" 2>&1
printf "Integrated local checks complete. Evidence: %s\n" "$logs"

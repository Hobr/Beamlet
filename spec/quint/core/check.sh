#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../../.."
mode=${1:-all}
case "$mode" in quick | simulate | verify | all) ;; *)
  echo "usage: $0 [quick|simulate|verify|all]" >&2
  exit 2
  ;;
esac
log_dir=${CORE_LOG_DIR:-$(mktemp -d /tmp/beamlet-quint-core.XXXXXX)}
mkdir -p "$log_dir"
log_dir=$(realpath "$log_dir")
status=0
printf 'Quint core evidence: %s\n' "$log_dir"
sha256sum spec/quint/core/*.qnt spec/quint/core/check.sh spec/quint/core/verify.py spec/architecture/*.md >"$log_dir/source-hashes.txt"
printf 'composition: Runs0/1, one Effect per Run, Attempts0/1 per Effect, owner incarnations0/1, FIFO6\nmain=composition init=init step=step invariant=safety samples=10000 depth=60 seed=20261014 backend=rust\nrecovery: Run0, FIFO4, restricted recovery.step; init=init; rankDecreases and core safety; 14 transitions to finish under explicit premises
BMC main=composition init=init step=step safety random-transitions=false depth=10 timeout=%s backend=apalache\n' "${CORE_VERIFY_TIMEOUT:-240}" >"$log_dir/domain.txt"
run_check() {
  local label=$1
  shift
  printf '%q ' "$@" >>"$log_dir/commands.txt"
  printf '\n' >>"$log_dir/commands.txt"
  local began=$SECONDS
  "$@" >"$log_dir/$label.log" 2>&1
  local code=$?
  printf '%s\n' "$code" >"$log_dir/$label.exit"
  printf '%s: exit=%s seconds=%s\n' "$label" "$code" "$((SECONDS - began))" | tee -a "$log_dir/results.txt"
  if ((code != 0)); then status=1; fi
}
quint --version >"$log_dir/version.txt"
for source in model small composition core_test recovery recovery_test; do run_check "typecheck-$source" quint typecheck "spec/quint/core/$source.qnt"; done
run_check recovery-tests quint test spec/quint/core/recovery_test.qnt --main recovery_test --backend typescript --seed 20261014
run_check combined quint test spec/quint/core/core_test.qnt --main core_test --match combinedTest --backend typescript --seed 20261014 --out-itf "$log_dir/combined_{test}_{seq}.itf.json"
run_check tests quint test spec/quint/core/core_test.qnt --main core_test --match '.*Test' --backend typescript --seed 20261014
if [[ $mode == simulate || $mode == all ]]; then
  witnesses=(intentWitness entryWitness unknownWitness recoveryWitness consumedWitness recoveryConsumedWitness branchWorkWitness inconclusiveWitness failedUnknownWitness failedReplyWitness)
  run_check sampling quint run spec/quint/core/composition.qnt --main composition --invariant safety --witnesses "${witnesses[@]}" --max-samples 10000 --max-steps 60 --seed 20261014 --verbosity 1
  run_check witnesses python3 - "$log_dir/sampling.log" "${witnesses[@]}" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
for name in sys.argv[2:]:
    count = re.search(rf'{re.escape(name)} was witnessed in (\d+) trace', text)
    if count is None or int(count.group(1)) == 0:
        print(f'missing or zero witness: {name}', file=sys.stderr)
        sys.exit(1)
print(f'All {len(sys.argv) - 2} required witnesses reached.')
PY
fi
if [[ $mode == verify || $mode == all ]]; then
  # Start a dedicated owned server so timeout cleanup cannot affect other jobs.
  # The Python wrapper places Quint and its server in an owned process group.
  run_check depth10 python3 spec/quint/core/verify.py "${CORE_VERIFY_TIMEOUT:-240}" "${CORE_SERVER_PORT:-8842}"
fi
sha256sum --check "$log_dir/source-hashes.txt" >"$log_dir/hash-validation.txt" 2>&1 || status=1
exit "$status"

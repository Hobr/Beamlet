#!/usr/bin/env bash
# Reproducible checks; every result is retained, including timeouts and zero witnesses.
set -uo pipefail
cd "$(dirname "$0")/../.."
mode=${1:-all}
case "$mode" in quick | simulate | verify | all) ;; *)
  echo 'usage: spec/quint/check.sh [quick|simulate|verify|all]' >&2
  exit 2
  ;;
esac
log_dir=${QUINT_LOG_DIR:-$(mktemp -d /tmp/beamlet-quint-check.XXXXXX)}
mkdir -p "$log_dir"
failed=0
quint --version >"$log_dir/version.log"
sha256sum spec/quint/*.qnt >"$log_dir/source-hashes.txt"
run_check() {
  local name=$1
  shift
  echo "[check] $name: $*"
  local started=$SECONDS
  "$@" >"$log_dir/$name.log" 2>&1
  local code=$?
  echo "$code" >"$log_dir/$name.exit"
  echo "$name exit=$code seconds=$((SECONDS - started))" | tee -a "$log_dir/results.txt"
  if ((code != 0)); then
    failed=1
    tail -n 12 "$log_dir/$name.log"
  fi
}
backend_checkpoint() {
  python3 - "$log_dir/$1.backend.log" <<'PY'
import pathlib,sys
logs=list(pathlib.Path('_apalache-out/server').glob('*/detailed.log'))
if logs:
    source=max(logs,key=lambda p:p.stat().st_mtime)
    lines=source.read_text().splitlines()
    pathlib.Path(sys.argv[1]).write_text('Backend source: '+str(source)+'\n'+'\n'.join(lines[-80:])+'\n')
PY
}
if [[ "$mode" == quick || "$mode" == simulate || "$mode" == all ]]; then
  for source in spec/quint/*.qnt; do
    run_check "typecheck-$(basename "$source" .qnt)" quint typecheck "$source"
  done
  # Long traces exceed the Rust evaluator's JSON recursion limit; use the official TS evaluator.
  run_check scenarios quint test spec/quint/architecture_test.qnt --main architecture_test --match '.*Test' --backend typescript --seed 20261007
  run_check command-protocol quint test spec/quint/protocol_test.qnt --main protocol_test --match '.*Test' --backend typescript --seed 20261010
  run_check negative-controls quint test spec/quint/negative_controls_test.qnt --main negative_controls_test --match '.*Test' --backend typescript --seed 20261007
  run_check formal-contracts quint test spec/quint/formal_test.qnt --main formal_test --match '.*Test' --backend typescript --seed 20261012
  run_check envelope-progress quint test spec/quint/progress_test.qnt --main progress_test --match '.*Test' --backend typescript --seed 20261012
  run_check independent-review quint test spec/quint/review_test.qnt --main review_test --match '.*Test' --backend typescript --seed 20261011
fi
if [[ "$mode" == simulate || "$mode" == all ]]; then
  witnesses=(inputWitness commitWitness admissionWitness entryWitness unknownWitness observationWitness repeatWitness settlementWitness consumptionWitness recoveryConsumedWitness branchNewWorkWitness forkWitness finishedWitness failedWitness disposalWitness evaluateWitness precheckWitness completeWitness auditWitness suspendWitness resumeWitness takeoverWitness controllerWitness controllerReadyWitness ownerDeathWitness disconnectWitness reconnectWitness providerWitness providerFaultWitness retryWitness rejectWitness lostAckWitness staleWitness lostProposalWitness writesWitness uiWitness authWitness permissionWitness)
  run_check composed-simulation quint run spec/quint/architecture.qnt --main architectureAnalysis --invariant architectureSafety --witnesses "${witnesses[@]}" --max-samples 10000 --max-steps 100 --seed 20261007 --verbosity 1
  run_check recovery-simulation quint run spec/quint/architecture.qnt --main architectureRecoveryAnalysis --init recoveryInit --invariant architectureSafety --witnesses recoveryConsumedWitness branchNewWorkWitness --max-samples 10000 --max-steps 100 --seed 20261008 --verbosity 1
  run_check conditional-progress quint run spec/quint/architecture.qnt --main architectureProgressAnalysis --init progressInit --step progressStep --invariant conditionalSafety --witnesses recoveryConsumedWitness --max-samples 10000 --max-steps 40 --seed 20261009 --verbosity 1
  # A zero count is a coverage gap, even when invariants had no sampled counterexample.
  if rg 'witnessed in 0 trace\(s\)' "$log_dir"/*simulation.log; then failed=1; fi
fi
if [[ "$mode" == verify || "$mode" == all ]]; then
  limit=${QUINT_VERIFY_TIMEOUT:-600}
  run_check composed-depth10 timeout "$limit" quint verify spec/quint/architecture.qnt --main architectureBounded --invariant modelCheckSafety --max-steps 10 --backend apalache --verbosity 1
  backend_checkpoint composed-depth10
  # Supplementary conditional check; cannot clear an inconclusive composition check.
  run_check conditional-depth8 timeout "$limit" quint verify spec/quint/architecture.qnt --main architectureProgressAnalysis --init progressInit --step progressStep --invariant conditionalSafety --max-steps 8 --backend apalache --verbosity 1
  backend_checkpoint conditional-depth8
fi
echo "Evidence: $log_dir"
exit "$failed"

# Integrated verification

Integration owner, feat/agent-model-credentials, baseline18137b1. Synthetic credentials,
local TCP/TLS, independent same-host VMs and copied releases only. No live/paid
provider or physical-host execution. Fresh independent review has **not** occurred.

## Commands and logs

Commands run from root with `ERL_FLAGS='+S 2:2'` unless specified. Logs live in
`/tmp/beamlet-integration-631927/`; attempt logs are retained separately and not
overwritten. Ordinary suite seed631927 and distributed suite seed631927.

| Command | Actual result | Log |
| --- | --- | --- |
| `mix format --check-formatted` | pass before repairs and after static repairs | format-attempt1.log, format-final.log |
| `mix compile --warnings-as-errors` | pass before and after source repairs | compile-attempt1.log, compile-attempt2.log |
| `mix test --seed 631927` | 138 passed, 9 distributed excluded, both runs | tests-attempt1.log, tests-final.log |
| `elixir --sname integration_credentials_631927 --cookie integration_isolated_631927 -S mix test --only distributed --seed 631927` | Runtime6 + Node3 actually executed and passed; 138 ordinary excluded | distributed-attempt1.log |
| same named command with `--sname integration_final_631927` | all9 passed after repairs; 138 ordinary excluded | distributed-final.log |
| `mix credo --strict` | initial failure:43 alias suggestions,2 alias-order findings,4 complexity/nesting findings; attempts2/3 remaining static findings; final pass | credo-attempt1.log through credo-attempt3.log, credo-final.log |
| `mix dialyzer` | pass,0 errors/skips, before and after repairs | dialyzer-attempt1.log, dialyzer-final.log |
| `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node --overwrite` | isolated backend build passed before/after source repairs | build-attempt1.log, build-final.log |
| `bash scripts/deployment/check-release.sh` | first authority/executor closure + copied eval/named startup/RPC/stop pass; expanded all-role attempt exposed checker boolean error | release-attempt1.log, release-final.log (failed expanded attempt) |
| `bash scripts/deployment/check-release.sh` after role-predicate repair | all7 copied eval combinations and all7 named startup/RPC/stop combinations completed; relative config rejected | release-attempt3.log |
| `env -u SECRET_KEY_BASE -u BEAMLET_BACKEND_BUILD ERL_FLAGS='+S 2:2' MIX_ENV=prod mix run --no-start -e ':ok'` | expected exit1, exact missing-secret message observed | web-secret.log |
| `python3 /tmp/beamlet-integration-631927/fixture-check.py` | 4 local fixture checks passed: complete tool_calls/stop, malformed Content-Length400, incomplete-header deadline | python-fixture.log |
| `mix format --check-formatted scripts/deployment/node.example.exs` | pass | example-format.log |
| `bash -n scripts/deployment/check-{local,release}.sh`; Python `ast.parse` both deployment scripts | pass | tool output |

Final ordinary counts by app: Harness31, Actions9, Runtime30 (6 excluded), Agent4,
Node57 (3 excluded), Web7. Named run excludes Harness31/Actions9/Agent4/Web7 and
Runtime30/Node57; umbrella prints per-app 'no test executed' notices for apps
without distributed tests. Those notices do not replace actual Runtime6/Node3
execution. Web7 includes CSP fresh nonce/rendering/secure policy regressions.

Dialyzer used existing `_build/dev/dialyxir_erlang-29.1.2_elixir-1.20.4_deps-dev.plt`;
reported 'PLT is up to date', no forced rebuild/refresh was performed. No callable
LSP tool available to this worker; no repository diagnostic cleanliness claimed.

Full umbrella acceptance was intentionally new integration coverage. Second full
run was justified by neutral-validator helper extraction and alias edits spanning
Harness/Agent/Node source and lifecycle/distributed fixtures. Backend rebuild and
copied release checks followed source edits; no additional unchanged passing gate
was rerun gratuitously. `check-local.sh` was read and its required gates executed
individually to preserve independent failures; wrapper itself not invoked. Sobelow
and xref cycles (extra wrapper diagnostics) were not required/run in this lane.

## AC1–AC8 evidence matrix

| Criterion | Executed evidence | Limits |
| --- | --- | --- |
| AC1 | Node release_integration_test (named3 includes real HTTP three-role VM test): supplied creation binding, Authorization/body assertions, no executor RELEASE_FIXTURE_KEY, workspace model→Tool→model and later turn | local peers/fixture only |
| AC2 | Node model_binding_test two immutable bindings on same executor, six config/key-paired invocations; unknown provider/adapter/fields rejected; Harness concurrent actual TCP auth/model isolation | no real second network provider |
| AC3 | Harness model_test independent alternate protocol and Node AlternateModel neutral Tool/text flow with dialect + nested session/bearer and internal tuple; static provider-audit.log confirms Agent/Handler/Catalogue/Deterministic have no OpenAI wire parser | Model's default registry names built-in OpenAI module; neutral :tool_calls tag is not wire parsing |
| AC4 | Harness model_test/harness_test/http_test malformed/full-batch/history/bounds, Node concurrent_tools_test reversed completion/invalid sibling and review malformed neutral replies | supported text/function subset only |
| AC5 | Actions9 credential JSON/protocol boundaries, Runtime review public+gateway exact deployment cap, distributed remote cap/forwarding, all Runtime/Node lifecycle and guarded-admission tests | no hard RSS cap; trusted cluster |
| AC6 | Harness TCP/TLS exact wire/auth/body/no retry/redirect/overflow/global defaults; Runtime generated progress/status/result/report absence; Node model_binding snapshot/history/progress/Tool Context/settings/arguments absence + explicit child/independent peer assertions | normal generated projections only; malicious provider echo/admin inspection excluded |
| AC7 | migrated README/runbook/example, isolated build closure and copied named RPC/stop checks; all-role checker expansion; Web missing-secret/CSP; Python4 fixture checks | all seven role subsets verified; physical/live untested |
| AC8 | model_binding_test immutable private binding across model steps and later turn, independent Agents, models collection/extra creation fields rejected; Agent option allowlist | one binding per lifetime, no switching API |

## Preserved contracts and evidence limitations

Caller puts credentials only in model Operation.credentials; Tool Operations retain
empty map and Handler rejects nonempty Tool credentials. Handler validates installed
provider/common invocation/request and uses neutral Model; OpenAI wire codecs stay
in OpenAICompatible. Provider source has no environment lookup. Server derives
canonical assistant history from validated neutral replies, without wire envelopes.
The existing public guarded admission, actual DOWN before infrastructure resume,
resource accounting until observed DOWN, fresh capacity synchronization and no
retry/replay assertions all executed. No lifecycle/admission/placement algorithm
was changed by integration. Existing deliberate-kill and TLS bad-certificate output
is expected test fixture output.

Earlier Agent/Node initial failure raw logs were overwritten before preservation
steering; only transcript excerpts and component narrative survive. Their original
root cause cannot be independently proved from raw logs. Operation initial compile
log was also reused. Component handoffs explicitly disclose this; no reconstructed
raw evidence is claimed. This lane preserves new failed attempts separately.

Matching builds required. Plaintext transient credentials/config may remain until
ordinary process/message/operation cleanup; no persistence/secure-erasure guarantee.
Executable spec migration and fresh independent full-diff review remain main-session
work. No dependency/lock/flake/task-state/archive/staging/commit changes made.

Final `git diff --check` passed (diff-check.log); staged.log is empty.

# Refined commit plan — approved for execution

User requested further splitting of the previous two-commit proposal, then replied
“确认” to this nine-commit plan. Scoped staging/commits are authorized; unrelated
.gitignore and unknown external changes remain excluded. Actual hashes and
isolated intermediate validation are recorded in commit-execution.md.

## Ordered groups

| # | Suggested subject | Scope |
| --- | --- | --- |
| 1 | feat(agent): add bounded live discovery and lookup | Agent facade, AuthoritySupervisor, Discovery/Endpoint and owning discovery tests. Include final fresh-challenge admission/lease/deadline safeguards, not the rejected implementation. |
| 2 | refactor(node): expose explicit library composition and cluster APIs | Remove Node Application callback/module; Node configuration/common limits/non-authority endpoint, Cluster, Agents aggregation, node/cluster/discovery tests and fixtures. Depends on1. Keep the final bounded-list validator. |
| 3 | refactor(cli): migrate client adapter and reuse Owl presentation | Move old Node.CLI and client/HTTP integration tests to CLI; Client, Command, Renderer, test support/dependencies and distributed exclusions. Renderer depends on Command; Client depends on Renderer, so keep these together. Node library must not depend back on CLI. Depends on2. |
| 4 | feat(daemon): add opt-in authority and executor host | Daemon configuration/Application/Bootstrap, Node dependency and ordinary/named lifecycle tests. Depends on2. No release configuration yet. |
| 5 | feat(cli): add bounded interaction sessions and terminal runner | CLI configuration/Application, Session/Runner, owning CLI/session/loading tests. Include final Unicode raw transport/restoration, retained pagination and encoded-ID behavior; do not reconstruct the defective pre-review candidate. Depends on1–3. |
| 6 | build(release): replace node executable with daemon and cli | Root mix release declarations/backend app set/CLI foreground entrypoint, host runtime configs, remove backend_runtime, migrate node example to daemon and add CLI/creation examples. Depends on4–5. |
| 7 | test(deployment): verify copied hosts and real terminal workflows | check-release/check-named-release/check-cli-release/check-local, six nested-cleanup regression tests and real PTY checker. Keep cleanup assertions with the corresponding checker changes. Depends on6. |
| 8 | docs(backend): document library hosts and discovery contracts | Current backend specs and deployment runbook. Documents final APIs, bounds, trusted configuration, Owl/Ucwidth, uncertainty and physical/paid exclusions. Depends on1–7. |
| 9 | chore(trellis): record split planning and reviewed acceptance | Only the five relevant task directories: PRDs/designs/plans/context/task records/research/acceptance, including this proposal. No journal/archive script or auto-commit. |

## Hunk ownership and validation

- apps/beamlet_node/lib/beamlet/node.ex belongs wholly to2: library docs, common
  Runtime limit validation and non-authority Discovery.Endpoint compose one final
  Node contract. Avoid arbitrary historical child-stage staging.
- CLI mix.exs/test_helper/support/adapter migration belong to3; fixed interaction
  host and its cli_test/session/loading assertions belong to5.
- Command/Renderer and Client must arrive together in3 because of actual module
  calls. Session/Runner consume them in5. Keep malformed-token and pagination
  parser/display assertions with the earliest owning tests that can run; Session
  tests stay with5, so do not claim their earlier execution.
- Root mix.exs belongs wholly to6, avoiding repeated partial release edits. Checker
  files belong to7 and final runbook/specs to8. No product bytes need rewriting.
- Old Node release configuration remains a migration boundary until6. Commits1–5
  do not claim copied-release acceptance; final release gates apply from7 onward.
  If every intermediate commit must ship a runnable release, move6's old-entry
  removal earlier with the necessary host/release changes, or squash2–6; do not
  silently claim that property from final evidence.
- Before each actual commit, verify exact staged files/hunks and whitespace; run
  relevant compile/ordinary/actual named gates on that candidate. The recorded
  final196/23 gate proves the final tree, not unbuilt intermediate commit trees.
  Use isolated candidate validation if necessary without modifying final bytes.
- Do not split implementation and its owning regression tests merely to increase
  commit count. Do not manufacture separate fix commits containing known-bad
  Unicode transport, hidden identities or queued-query admission.

The nine-commit batch is approved. Each staged set is checked against the exact
allowlist, with an empty index required at entry. Source snapshots for1–7 pass
format and warning-fatal compile; ordinary tests run for1–5, excluding distributed
cases. No intermediate named or copied-release rerun is claimed; the final tree's
23 actual named/copy evidence remains as recorded. Push, branch changes, archive
and journal actions remain outside this request.

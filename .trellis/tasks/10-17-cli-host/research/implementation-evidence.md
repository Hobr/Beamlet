# CLI host implementation — frozen, independent review pending

Approved final child implemented on dev / HEAD0fed1b19fdc5945978bad40307aff8562875bbb8.
Independent CLI check and parent AC1..AC9 acceptance remain pending; no task
completion/archive/commit is claimed. No product/test/spec/config/script writes
followed the final165-path freeze. This evidence and implementation checklist are
outside that freeze.

## Delivered contracts and ownership

- CLI.configuration validates enabled/allowed_nodes only; ordinary Application
  starts an empty supervisor with no Node/stdin. Enabled starts fixed interaction.
- Command.parse validates UTF-8 and65536-byte commands, preserves input text and
  dispatches help/connect/nodes/agents/create/attach/input/status/watch/stop/close/
  detach/quit. Runner owns bounded byte reads and VM exit after application start;
  tests inject read/output/exit. Foreground release start invokes Runner without IEx.
- Session is the single dispatcher over Cluster/Agent/Node.Agents and keeps at
  most128 aliases to real Refs. Existing aliases reject replacement. Attach uses
  explicit authority+ID, reads a snapshot, submits no input. Old Ref commands never
  rebind. Only successful close clears aliases to the closed Ref; quit/EOF/detach
  clear only local state and do not close Agents. No business replay/retry added.
- Creation accepts an absolute trusted operator-owned executable Config file with
  `config :beamlet_cli, agent_options: [...]`. Reader/options errors are static;
  raw config, credentials, paths and exceptions are not rendered. Config code is
  trusted and can itself execute/print; it is not sandboxed. No eval command exists.
- Watch retains same-sink subscribe/receive/ack/unsubscribe and finally cleanup,
  max256 events/60s. It shares safe status rendering with injected output. Owl
  display truncation is followed by an explicit4096 Unicode-codepoint hard cap
  because display columns and codepoints differ for combining characters.
- Root backend selector includes both hosts, excludes Web. Independent daemon/CLI
  release closures exclude each other and Web. cli_runtime config explicitly
  enables CLI; ordinary Web secret behavior and rel named service/control ports
  remain unchanged. Both artifacts rebuilt after shared-core and Owl changes.

## User-directed Owl reuse

Installed deps/owl0.13.1 README/source inspected; no dependency/version/install
operation. Owl.Table.new owns help, nodes, identity/discovery/failure and status
layouts. Owl.IO.puts owns default terminal output; callbacks preserve test IO.
Owl.Data.truncate/to_chardata owns display handling. No custom table/border/width/
full-screen terminal engine. Explicit unlimited table width plus bounded wrapping
cells prevents Owl's terminal-width column omission from hiding authority/ID.
Discovery shows at most8 full identity rows with shown/total/completeness/failure
counts, max32 failure rows. ID strings are inspected to escape terminal controls.

Residual custom code is application grammar/dispatch/alias policy, safe domain
projection/error allowlist, resource bounds and byte transport. Owl.IO.input at
lib/owl/io.ex:427 uses IO.gets then normalizes String.trim and recursively retries
required input/EOF, so it cannot preserve executable text, bound allocation before
reading, or implement piped EOF. The narrow reader terminates the session on an
overlong line rather than executing a prefix/suffix; piped stdin is prompt-free.

PRD/design/implement and current backend specs/docs persist this user steering.

## Essential discovery integration fix

Initial ordinary190/named23 passed but cumulative Dialyzer emitted3 MapSet opacity
warnings in private Node.Agents.valid_nodes?/3. Forced full compilation produced
byte-identical Agents beam; `mix dialyzer --force-check` against the existing PLT
reproduced the warnings. A MapSet.t annotation also failed. Final validator uses
an at-most32-element seen-atom list, preserving duplicate/improper-list/target
validation and all public/protocol/budget/worker semantics. No warning suppression,
clock/liveness/admission change, dependency repair or forced PLT deletion/rebuild.
Existing-PLT analysis then passed with zero errors. All discovery tests reran in
final ordinary/named suites, including existing endpoint lifecycle/admission cases.

Old discovery15 manifest remains historical and untouched.11/15 paths still match;
authorized differences are Node.Agents private validator plus current index,
directory-structure and agent-orchestration specs. Exact old/new hashes are in
/tmp/cli-host-evidence/discovery-authorized-delta.json. All discovery Agent source,
Endpoint, source tests, discovery design/evidence and Node core are unchanged.

## Final executed validation

Authoritative full run: /tmp/beamlet-acceptance.ML6HV6/.
Launcher /tmp/cli-host-evidence/check-local-owl-corrected.log and .exit record
`ERL_FLAGS='+S 2:2' bash scripts/deployment/check-local.sh`, exit0. Named parent
uses random unique name and explicitly generated secure random --cookie; cookie
never logged, ERL_FLAGS scheduler-only. Existing peers inherit parent cookie.

- Format and warning-fatal compile pass; additional full forced compile and
  example-config format checks pass. Final strict Credo108 files/870 mods-funs,
  no issues. Existing-PLT Dialyzer0 errors/0 skips; final PLT up to date.
- Ordinary191 passed: Harness35, Actions28, Runtime30, Agent13, Node60, Daemon5,
  CLI13, Web7.23 distributed excluded in ordinary run. No doctest total inferred.
- Actual named23 passed: Runtime6, Node14, Daemon2, CLI1 (real migrated HTTP→
  workspace→model integration). Other umbrella apps report zero matching tests;
  this is not presented as additional execution. Deliberate partition warnings
  are expected. Same-host peers, not physical hosts.
- Sobelow scan complete; xref command succeeds and reports5 current cycles in
  Web/Harness/Agent/Runtime/discovery, no CLI-host cycle; not a zero-cycle claim.
- Both isolated prod releases build. Same daemon copy passes default/authority-
  only/executor-only named start/RPC/pid/stop at service9100, two only services
  with remote Gateway turn, failed-peer continuation and12 rejected configs.
- Copied CLI closure excludes daemon/Web. Three independent foreground stdin
  sessions outside checkout/deps: A connects/creates/quits; B discovers/attaches/
  status/input/watch/stop/detach/EOF; RPC compares identical full Ref (authority,
  PID, incarnation); C attaches/closes/quits and RPC requires not_found.
- Expected ordinary prod missing SECRET_KEY_BASE failure asserted; Web7 includes
  CSP regressions. Original HTTP/workspace/wrong environment/no fallback/fresh
  capacity/stop/loss/no replay named assertions remain and pass.
- Six Python cleanup regressions pass; Python3.14.7 (requires3.11+). Shell syntax,
  Python AST, examples format and staged/unstaged whitespace pass.
- Active cached direct-beam ElixirLS:18 opened Elixir paths clean in
  /tmp/cli-host-evidence/lsp-owl-final, plus the final changed Client path clean
  in lsp-client-corrected. Actual version1 publishDiagnostics received; not an
  empty-cache claim. Dependency fetch/Dialyzer disabled for LSP. Initial probe
  mistakenly selected .expert directory; retained failure, corrected file filter.

## Preserved failures / intermediate evidence

All separate logs retained under /tmp/cli-host-evidence and the printed aggregate
run directories. Initial syntax errors in release step quoting, stale generated
hello test and malformed new fixtures were corrected; original logs retained.
First check-local timed out at tool60s and was interrupted during named tests
(/tmp/beamlet-acceptance.Ir0mMf), not called passing. Initial aggregate
Lt4pTF:190 ordinary/23 named, then Dialyzer exit2. Force-check/typespec attempts
also exit2, recorded separately. Owl aggregate1p7xJu:191 ordinary/23 named, then
strict Credo required a Renderer alias in Client; corrected before finalML6HV6
exit0. Earlier copied-final logs/artifacts belong to pre-Owl candidate. Final
unchanged candidate was not broadly rerun after ML6HV6 passed.

## Frozen source and rebuilt artifacts

/tmp/cli-host-evidence/final-fingerprints.json records:

| Manifest | Paths | SHA256 |
| --- | ---: | --- |
| product-test-spec-config-script.frozen.sha256 |165|9fa5ee987bbfb38e3f0dce48032c43f99b97f44d8910690b39cab0cf7e2288c0|
| daemon-artifact.frozen.sha256 |1006|035572d3a3d489779310aa9eb6a7fa17b79fdda52795542305d33e250da481f8|
| cli-artifact.frozen.sha256 |1036|c593c6ebc89e417ee34869d056f60c9a5b7f9a4e4fbf46c1b3be678e3f1fb528|

All manifests verify. Artifact source trees exactly equal actual copied manifests
(daemon shell-sorted ./paths, CLI Python-sorted relative paths). These are manifest
fingerprints, not tarball hashes. Product freeze includes current product/test/
spec/config/script, lock/manifests, CLI PRD/design; evidence/checklist are separate.
No candidate writes after freeze. No cache-empty or clean-checkout claim.

## Index, safety and residual risks

Entry status84 changed entries /83 staged /1 untracked; entry raw index SHA256
8a56f40d9d152e072a0ba945c1f194012e41dc8af3055ce8c5706a27fce48539.
Final pre-evidence observation97 changed /96 staged /1 untracked; raw index
7a0c1ad928108bcfc1bd4aaae2a3cfb3472e13139e97f6cc50f7b739f4b823c7,
cached binary diff61f07daa07323e718043a6d6534f283641209f0a09f87e0acc689524f33180d5.
Worker ran no index mutation; unknown actor staged changes during work and parent
was notified. Snapshots preserved, no reconciliation/ownership attribution.
Evidence writes can add entries after those observations; noStagedFiles=false.
No commit/push/merge/reset/restore/clean/branch/archive/journal, install/version
repair, SSH/physical deployment or paid provider operation occurred.

Independent read-only CLI check and final parent AC review remain pending. Trusted
executable config/distribution, fixed one-Node-per-VM names, eventual discovery and
conservative timeout assumptions remain. Watch/stop are not upstream rollback or
billing-cancellation promises. Same-host deterministic fixtures do not attest
physical hosts or paid providers. No unresolved self-validation gate remains.

# Independent Agent Core review

Verdict: **request changes**. Three P2 blockers below; no P1 defect established. This is an independent, read-only product/source/spec review, not parent acceptance. Only this report was written in the repository. No fixes, worktrees, reset/checkout/clean/stage/commit/push, or subprocess agents.

## Scope and baseline

Checkout `/mnt/data/Project/Beamlet`; branch `refactor/agent-core-extraction`; HEAD/baseline `a18f3c7488e08c13a4fc324e602e0a75d67e20bf`, independently confirmed with `git rev-parse HEAD` and `git branch --show-current`. Reviewed complete tracked diff plus all new Core source, manifest, formatter, README, tests and Agent adapter tests. Read check.jsonl entries, prd/design/implement and research/recreation.md and implementation-report.md. The dispatch explicitly identifies the existing task; stale no_task breadcrumbs do not require creating another task.

## Blocking findings

### F1 — P2: bulk loading changes first error and reads past an already failed context

Location: `apps/beamlet_agent/lib/beamlet/agent/context_builder.ex:11`, `:21`, `:25`.

`build/3` and `materialize/2` load the entire selected timeline before running any message conversion/Context.append. Baseline loaded, converted, appended and stopped per occurrence. This violates R5 error compatibility and the design requirement to preserve error precedence, and expands retained data/read work for histories that already exceed native limits.

Concrete baseline differential probe compiles the exact baseline ContextBuilder under a different module name; all Storage/Codec/History and Harness code are real. A tiny Repo protocol double returns valid 65536-byte input events, recording read count, with one absent final event. Timeline is 127 explicit repetitions of a valid selected input followed by a missing input source, total 128 (within the existing selected-occurrence contract). Results:

```
baseline:  {:error, :context_limit}, reads: 16
extracted: {:error, :invalid_reference}, reads: 128
```

With all 128 occurrences valid, both return context_limit but baseline reads 16 and extracted reads 128. Thus the extra work exists even without corruption. These are counted Repo calls, not a claimed measured RSS figure; repeated fixture binaries can share storage. With distinct real input rows this collects up to 8 MiB of input text before the 1 MiB native message check, plus event/material overhead. Operations may retain much larger descriptions/results which never appeared in final messages. Earlier invalid model replies/unresolved outputs are likewise evaluated only after all later reads; the first-error regression is directly proven above, not conjectured from a failing suite.

Smallest architectural remedy: retain source I/O in the adapter, but feed each verified source-bound material into a pure incremental Core context accumulator (convert + append + exact selected occurrence validation) before reading the next source. Validate completion/current catalogue only after the last source. No reader callbacks or I/O in Core, no second DB traversal, and no request validation on incomplete tool-pair prefixes. Keep a batch facade for standalone Core callers if desired. Add adapter regressions for overflow-before-missing/corrupt suffix and invalid-reply-before-missing suffix, asserting both error and absence of later reads. Enforce material validation incrementally too, so future prevalidation of the whole set does not recreate first-error changes.

### F2 — P2: generic plain-data validation shrinks the accepted persisted nesting budget

Location: `apps/beamlet_agent_core/lib/beamlet/agent/core/reducer.ex:59`, `:44`; related `apps/beamlet_agent_core/lib/beamlet/agent/core/data.ex:23`.

Storage.Codec checks payload nesting from payload root, limit 32. The new decoder also applies Data.plain? to the complete event; its payload wrapper consumes another level. A valid reference-only `context.selected` payload constructed as `Enum.reduce(1..32, 0, fn _, x -> %{"x" => x} end)` is accepted by baseline Agent.Reducer.decode/reduce/replay but all three current facade calls return invalid_history. Event identity/sequence/schema and payload are otherwise unchanged. Existing supported history can therefore fail reconstruction after a nominally equivalent extraction.

Core.replay adds an additional list wrapper: with depth 31, Core.decode returns :ok while Core.replay of created + selected returns invalid_history. This proves inconsistency even within the new pure API.

Remedy: validate event-envelope fields separately from the payload's existing depth budget, and validate replay list properness without recursively recounting every event under the list root. Apply the same principle to material/control wrappers; adding a container must not silently lower an already validated domain object's budget. Preserve safe rejection of improper lists/live values. Add boundary vectors at payload depth 32 and over the limit, plus reduce-vs-replay equivalence. Do not globally relax Storage's limit or just increase an arbitrary global Core limit without accounting for wrappers.

### F3 — P2: malformed normalized inheritance still succeeds in pure replay

Location: `apps/beamlet_agent_core/lib/beamlet/agent/core/reducer.ex:164`, `:176`, `:178`.

`inherited_source?` accepts `%{"type" => "inherited_input"}` with no artifact/event/source owner/digest/sequence and inherited_result with an empty reference. Created + valid fork + context.inherited with sources=closure=[that input] returns {:ok, state}, placing the malformed source in both inheritance and timeline. This is a carried-forward baseline validation gap, **not a newly introduced accepted-history regression**. It remains an explicit task acceptance/spec gap: design Event contract requires malformed normalized input rejection and durable-references §3 says malformed inherited entries are rejected by the pure decoder before traversal. The existing pure fork test uses only empty sources/closure, so it cannot exercise this requirement.

Remedy: pure shape checks for inherited entries (exact keys; canonical UUID/digest and positive sequence fields; result reference/resolution structure), retaining source-in-closure membership and existing count limits. Keep actual artifact existence, ownership, digest verification, operation prepared/accepted linkage and closure coverage reads in the loader. Add nonempty valid inheritance and missing/malformed field vectors, including inherited results and risk acceptance without inheriting pending/consumed work. This hardens malformed input, not valid historical formats. Loader verification currently protects the persisted execution path; this finding does not establish arbitrary persisted execution bypass.

## Bookkeeping finding (non-product, P2 review gate)

`implement.md:20` marks “independently review the full diff, fix findings” complete while implementation-report and implement.md's final paragraph say independent review is pending. Step 9 at `:21` also bundles spec-sync/review/wrap-up as completed before parent acceptance/commit/archive. There is **no explicit completed commit checkbox**; the actual report correctly says no commit/archive occurred. Correct the compound checklist to distinguish implemented/static-gated work from independent review, fixes and parent finish steps. Do not infer commit completion from step 9. Dispatch checklist line 6 is also still unchecked. Parent owns those edits; this pass did not modify the plan.

## Positive review evidence and limits

- Core declares only Harness/Jason, has no Application callback; lib inspection and forbidden-call search found no Agent/Storage/Runtime/Ecto dependency or external-effect calls. The sole Ecto search hit is a comment explaining UUID spelling. Req remains a documented Harness transitive dependency, not a Core transport invocation.
- Adapter preserves Storage.Codec/Events validation, canonical input digest, and transient input_digest normalization. Canonical storage formats, reducer version, checkpoint state keys and unchanged tests remain intact. UUID vectors compare against existing Ecto-backed Codec, including casing and raw-byte forms; no contrary UUID vector was found.
- Loader/History/Inheritance/OperationRecords are unchanged. Owned operation checks still bind owner, preparation event/turn/step/ordinal, immutable description and acceptance digest, consumed linkage and selected sources. Inherited manifest verification retains original owner/description/acceptance/closure checks. F3 identifies pure shape-validation incompleteness, not removal of those I/O checks.
- Historical model result conversion still calls Model.validate_reply with the stored request catalogue; final build validates with current catalogue. complete_boundary deliberately avoids revalidating old arguments. The new test named historical catalogue only uses empty catalogue/text and is weak evidence for differing tool schemas; optionally add a real old-schema/new-schema tool batch test.
- Durable preflight only returns :ok/error and uses temporary projections. Durable.committed/2 still replays transaction-returned events; prepare/accept/consume transactions, request recovery, uncertainty, owner retirement, resources and memory execution code are unchanged by the diff. Decision classifications are called at actual Server durable model result/resume and Durable safe-fork sites and match baseline cases, including blocked resumable precheck vs unsupported resumed position.
- Core tests meaningfully exercise gaps, normalized malformed data, source order/completeness/substitution, join linkage, pause, deterministic continuation and explicit risk. They do not cover the three blockers above. No existing test assertions/files were weakened or removed.

## Verification

Fresh bounded commands executed from checkout:

```
git status --short
git diff --stat
git diff --check
git rev-parse HEAD
git branch --show-current
git diff --cached --name-only
rg -n 'Repo|Storage|Runtime|Ecto|File\.|System\.|Process\.|spawn|send\(|Task\.|:crypto|Req\.|apply\(' apps/beamlet_agent_core/lib
MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start /tmp/beamlet-review-probes.exs > /tmp/beamlet-review-probes.log 2>&1
ERL_FLAGS='+S 2:2' mix test --no-start apps/beamlet_agent_core/test apps/beamlet_agent/test/beamlet/core_adapter_test.exs --seed 631927 > /tmp/beamlet-review-focused.log 2>&1
```

Fresh no-start tests: **Core 7 + adapter 2 passed**; git diff --check passed; staged list empty. Probe process exits 0 and prints differential failures to compatibility (it is a diagnostic script, not a passing compatibility assertion). One unused alias warning belongs solely to the temporary probe. Exact baseline-module generation and complete probe are reproduced below.

Inspected saved final evidence rather than re-running expensive gates: `/tmp/beamlet-acceptance.QYJ2am/tests.log` per-app totals sum to **512 passed / 37 excluded**; distributed.log **35 passed / 514 excluded**. Inspected strict/default Credo no findings, Dialyzer **0 errors / 0 skips**, Sobelow scan complete, durable.log **two OS-process phases, 1 passed each** and successful final marker, release.log copied server/CLI/Web launch/RPC/exit/control/HTTP results. Final focused log `/tmp/agent-core-focused-final-3.log` reports Core7+Agent106, isolated PostgreSQL `/tmp/agent-core-postgres-final.log` reports 78 passed. These are saved gate evidence, not commands rerun by this reviewer. Existing-PLT analysis is not a forced rebuild; named peers are same-host evidence only.

The full ordinary process began before the final mixed-material guard. The final saved focused tests include that guard's substitution assertion and the fresh no-start run confirms it passes on this tree. That narrow extra-key rejection has sufficient focused final coverage; no additional complete umbrella/release run is needed solely because of its timing. This does **not** cover F1–F3. After fixes, add the missing adversarial tests and rerun Core+Agent focused gates (and appropriate affected history/fork adapter checks); parent determines final acceptance scope. No clean conclusion relies on a diagnostic cache or LSP silence.

## Reproduction appendix

Generate renamed baseline modules without changing checkout:

```sh
python3 - <<'PYCODE'
import subprocess
for filename, name in [('context_builder', 'Context'), ('reducer', 'Reducer')]:
    s = subprocess.check_output(['git', 'show', 'a18f3c7488e08c13a4fc324e602e0a75d67e20bf:apps/beamlet_agent/lib/beamlet/agent/' + filename + '.ex'], text=True)
    original = 'ContextBuilder' if filename == 'context_builder' else 'Reducer'
    target = '/tmp/beamlet-review-baseline-' + name.lower() + '.ex'
    open(target, 'w').write(s.replace('defmodule Beamlet.Agent.' + original + ' do', 'defmodule Beamlet.Review.Baseline' + name + ' do', 1))
PYCODE
```

Save the following as `/tmp/beamlet-review-probes.exs` and run the mix command above:

```elixir
Code.require_file("/tmp/beamlet-review-baseline-context.ex")
defmodule Beamlet.Review.ProbeRepo do
  def one(query, _) do
    Process.put(:reads, Process.get(:reads, 0) + 1)
    {seq, _} = List.last(hd(query.wheres).params)
    if seq == 999, do: nil, else: %{event: Process.get(:event)}
  end
end
alias Beamlet.Agent.Core.{Context, Reducer}
id = "12345678-1234-1234-1234-123456789abc"
payload = %{"text" => String.duplicate("x", 65_536)}
{:ok, digest} = Beamlet.Storage.Codec.digest(payload, :event)
Process.put(:event, %{"id" => id, "type" => "input.accepted", "payload" => payload})
ref = %{"type" => "input", "event_id" => id, "seq" => 2, "digest" => digest}
for {label, timeline} <- [{"overflow_then_missing", List.duplicate(ref, 127) ++ [Map.put(ref, "seq", 999)]}, {"overflow_valid_suffix", List.duplicate(ref, 128)}] do
  control = %{Reducer.new(id) | "timeline" => timeline}
  for mod <- [Beamlet.Review.BaselineContext, Beamlet.Agent.ContextBuilder] do
    Process.put(:reads, 0)
    result = mod.build(Beamlet.Review.ProbeRepo, control, %{})
    IO.inspect({label, mod, result, reads: Process.get(:reads)})
  end
end
# Normalized inherited sources: contract requires safe rejection before reference traversal.
created = %{"id" => id, "scope_id" => id, "seq" => 1, "schema_version" => 1, "type" => "agent.created", "payload" => %{"definition_version" => 1}}
fork = %{created | "seq" => 2, "type" => "agent.forked", "payload" => %{"source_agent_id" => id, "through_seq" => 1, "risk" => "unconfirmed"}}
bad = %{"type" => "inherited_input"}
inherited = %{created | "seq" => 3, "type" => "context.inherited", "payload" => %{"sources" => [bad], "closure" => [bad]}}
IO.inspect(Reducer.replay(Reducer.new(id), [created, fork, inherited]), label: "malformed_inheritance")
Code.require_file("/tmp/beamlet-review-baseline-reducer.ex")
for depth <- 29..32 do
  payload = Enum.reduce(1..depth, 0, fn _, x -> %{"x" => x} end)
  selected = %{created | "seq" => 2, "type" => "context.selected", "payload" => payload}
  for mod <- [Beamlet.Review.BaselineReducer, Beamlet.Agent.Reducer] do
    decoded = mod.decode(selected)
    reduced = mod.reduce(Map.put(mod.new(id), "through_seq", 1), selected)
    replayed = mod.replay(mod.new(id), [created, selected])
    tag = fn result -> case result do {:ok, _} -> :ok; other -> other end end
    IO.inspect({"depth", depth, mod, decoded, tag.(reduced), tag.(replayed)})
  end
end
payload = Enum.reduce(1..31, 0, fn _, x -> %{"x" => x} end)
selected = %{created | "seq" => 2, "type" => "context.selected", "payload" => payload}
IO.inspect({Reducer.decode(selected), Reducer.replay(Reducer.new(id), [created, selected])}, label: "core_batch_depth31")

```

Saved probe output:

```text
{"overflow_then_missing", Beamlet.Review.BaselineContext,
 {:error, :context_limit}, [reads: 16]}
{"overflow_then_missing", Beamlet.Agent.ContextBuilder,
 {:error, :invalid_reference}, [reads: 128]}
{"overflow_valid_suffix", Beamlet.Review.BaselineContext,
 {:error, :context_limit}, [reads: 16]}
{"overflow_valid_suffix", Beamlet.Agent.ContextBuilder,
 {:error, :context_limit}, [reads: 128]}
malformed_inheritance: {:ok,
 %{
   "agent_id" => "12345678-1234-1234-1234-123456789abc",
   "blocked" => nil,
   "consumed" => [],
   "continuation" => "await_input",
   "definition_version" => 1,
   "environment_risk" => "unconfirmed",
   "fork" => %{
     "risk" => "unconfirmed",
     "source_agent_id" => "12345678-1234-1234-1234-123456789abc",
     "through_seq" => 1
   },
   "generation" => 0,
   "inheritance" => %{
     "closure" => [%{"type" => "inherited_input"}],
     "sources" => [%{"type" => "inherited_input"}]
   },
   "inputs" => [],
   "paused" => true,
   "pending" => [],
   "resolutions" => %{},
   "step" => 0,
   "through_seq" => 3,
   "timeline" => [%{"type" => "inherited_input"}],
   "turn_id" => nil
 }}
{"depth", 29, Beamlet.Review.BaselineReducer, :ok, :ok, :ok}
{"depth", 29, Beamlet.Agent.Reducer, :ok, :ok, :ok}
{"depth", 30, Beamlet.Review.BaselineReducer, :ok, :ok, :ok}
{"depth", 30, Beamlet.Agent.Reducer, :ok, :ok, :ok}
{"depth", 31, Beamlet.Review.BaselineReducer, :ok, :ok, :ok}
{"depth", 31, Beamlet.Agent.Reducer, :ok, :ok, :ok}
{"depth", 32, Beamlet.Review.BaselineReducer, :ok, :ok, :ok}
{"depth", 32, Beamlet.Agent.Reducer, {:error, :invalid_history},
 {:error, :invalid_history}, {:error, :invalid_history}}
core_batch_depth31: {:ok, {:error, :invalid_history}}
    warning: unused alias Context
    │
  9 │ alias Beamlet.Agent.Core.{Context, Reducer}
    │ ~
    │
    └─ /tmp/beamlet-review-probes.exs:9:1


```

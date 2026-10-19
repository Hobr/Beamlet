# Typespec conventions

## Ownership and precision

Define shared types in the application and module that own the data. Reuse remote types along existing dependency directions; a type reference must not introduce a reverse dependency. Use `@typedoc` to explain stable public structures, valid construction/intermediate states, and constraints that remain runtime checks. Keep internal accumulators and process records in `@typep` when consumers do not need them.

Use required atom-key fields and tagged unions for stable request, response and state variants. Reuse `Beamlet.Actions.data()` for ordinary bounded Operation payload, placement and metadata values: metadata currently accepts scalars and lists as well as maps, so its type must not impose a map-only restriction. An optional association allows an empty map (`%{optional(binary()) => value()}`); a required association demands a matching key. Operation credentials and claims must allow their valid empty defaults. Schema types include uninserted nil fields. Do not describe only the successful or fully initialized state.

Use `@opaque` only when consumers should not depend on representation. Readable live Ref structs intentionally remain transparent. Opaque declarations do not validate UUIDs or provide runtime security. Preserve input/output relationships with type variables and parameterized types for generic transaction, projection and conversion helpers.

## Function coverage

Every handwritten production `def`, `defp`, `defdelegate`, `defmacro` and `defmacrop` requires an accurate explicit `@spec`. Callback implementations require specs as well as appropriate `@impl`; own behaviours require accurate callbacks and implementation contracts. Describe all clauses and normal error results. `no_return()` means no normal return, not merely a function that can raise.

A default-parameter definition needs its maximum source arity contracted; generated wrappers do not need repeated declarations. Explicit additional arities do. Multi-clause functions and separate heads share a logical identity. Nested modules and quote templates retain their actual scope. Handwritten functions inside quote require contracts; framework-generated functions are classified separately by the AST checker. Dynamic definitions that cannot be attributed fail for review. There is no application/module exemption mechanism.

## Open input and JSON

Validation functions accept `term()` when they reject arbitrary malformed input. Do not narrow away tested rejection paths. Arbitrary handler payloads/reasons, provider settings, dynamic assigns, and structural converters that preserve arbitrary leaves can remain open with an explanation. Stable owned structures should not become unexplained `map()` or `term()`.

Current typespecs cannot express literal string map keys or string enum values. Use semantic JSON object/value aliases and typedocs; runtime validators still enforce exact fields, relationships, enum spellings, proper lists, UTF-8, UUIDs, secrets, depth and size. Do not change persisted/wire string keys to atom keys to satisfy analysis. Typespecs do not replace security or runtime validation.

## Errors and intentionally unused results

Preserve error tags, uncertainty, rollback, exceptions and process protocols. Keep accurate unions for error and intermediate outcomes; never invent return variants to keep unreachable code analyzable. Remove a dead branch only after checking every callee clause and caller, documenting why it cannot execute.

Inspect each unmatched return before adding `_ = expression`. Explicit discards are appropriate for known side effects, extraction strings, migration descriptors, cancellation sends and documented best-effort cleanup. They must not hide required transaction failures or turn a cancellation request into observed termination. Document non-obvious intent near the call. Bang SQL calls still raise; existing affected-row assertions must remain. A true behavior defect needs separate authorization.

## Local checks

From the umbrella root:

```sh
elixir scripts/quality/check-contracts-test.exs
elixir scripts/quality/check-contracts.exs
elixir scripts/quality/check-contracts.exs --inventory
mix format --check-formatted
mix compile --warnings-as-errors
mix dialyzer
```

The source scanner parses without executing production macros. It fails on missing contracts, parse errors and unclassified explicit definitions; 40 fixtures include public/private negative cases, defaults, heads, nested modules, delegates, macros, quote and framework boundaries. Presence alone does not establish semantic accuracy. Review all clauses/callers and use compiler, Dialyzer and owning regression suites.

Root Dialyzer retains default warnings and explicitly includes `:unknown` and `:unmatched_returns`, with no ignore file or suppression. Existing-PLT analysis is distinct from a fresh project PLT build. Root formatting includes `scripts/quality/*.exs`. The two contract hooks check the full production scope once (`pass_filenames: false`), triggered by production sources, checker files and hook/integration wiring. `scripts/deployment/check-local.sh` runs checker tests and coverage first and propagates failures through `set -euo pipefail`.

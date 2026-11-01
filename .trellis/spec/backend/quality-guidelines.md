# Quality and Verification

## Formatting and Environment

[.editorconfig](../../../.editorconfig) defines UTF-8, LF, final newlines,
trailing-whitespace cleanup, and file-type indentation. Rust formatting is
owned by rustfmt; do not hand-format Rust snippets as a substitute for checking
the source when a Rust change is actually authorized.

The [toolchain file](../../../rust-toolchain.toml) pins Rust and components.
Local Linux Cargo builds use the mold linker flag in
[Cargo configuration](../../../.cargo/config.toml).
[README](../../../README.md) describes native and optional Nix setup.
The configured Wasm target alone does not establish a Wasm product feature.

## Choose Checks by Change

Use [justfile](../../../justfile) and [prek.toml](../../../prek.toml) as the
command sources of truth.

| Purpose | Existing command or entry point |
| --- | --- |
| Check formatting without rewriting Rust | cargo fmt --all -- --check |
| Workspace type check | just check |
| Strict Clippy gate | cargo clippy --workspace --all-targets --all-features -- -D warnings |
| Workspace tests | just test |
| Documentation build | just doc |
| Dependency policy | cargo deny check |
| Generate license attribution | just license |

The pre-commit configuration also selects gates by changed file patterns.
Its existence does not prove that hooks are installed or that CI ran.
The tracked [.github configuration](../../../.github/dependabot.yml) provides
dependency updates, not a product test workflow.

For documentation-only changes, check links, source claims, indexes, whitespace,
and change scope. Report those checks separately from Rust builds/tests.
Do not claim a command passed merely because it is listed here.

## Commands with Side Effects

- just fmt rewrites formatting and runs prek across all files. It is not a
  read-only documentation verifier.
- just license generates licenses.html.
- just update updates tools, dependencies, hook revisions, and the Nix lock.
  Treat it as maintenance work, not validation.
- just install-dev installs development tools and fetches advisory data.

Do not weaken gates or alter dependencies as an incidental part of a docs task.

## Tests and License Evidence

[The library test](../../../crates/lib/src/lib.rs) is an inline
`#[cfg(test)]` module using `#[test]` and `assert_eq!` around the generated add function.
It is evidence of the current test location, not broad backend coverage or a
required naming style for new tests. No Console or backend recovery tests are
established by this scaffold.

[deny.toml](../../../deny.toml) owns dependency-policy checks.
[about.toml](../../../about.toml) owns attribution-generation settings.
Read both when an actual dependency change affects licensing; do not copy an
allow-list from an older conversation or silently bypass a rejection.

## Review Checklist

- Use the relevant current package manifest and source, not just root declarations.
- Distinguish a scaffold limitation from a pattern worth repeating.
- Keep product changes out of documentation-only work.
- Report exactly which checks ran and which were intentionally not run.
- Update spec links and navigation with any moved topic.

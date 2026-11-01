# Beamlet Development Guidelines

Use these guides for the code that exists now. They describe the Rust
workspace and Console scaffold, not a completed durable-execution framework.

## Start Here

| Change | Read |
| --- | --- |
| Workspace, Node, or shared library | [Rust workspace guidelines](backend/index.md) |
| Console input, state, rendering, or errors | [Console guidelines](console/index.md) |
| Shared ownership or duplicated behavior | [Reuse guide](guides/code-reuse-thinking-guide.md) |
| Changes spanning events, packages, or build inputs | [Cross-layer guide](guides/cross-layer-thinking-guide.md) |
| Formatting, checks, tests, or licenses | [Quality guidelines](backend/quality-guidelines.md) |

## Current Code Versus Future Direction

The [workspace manifest](../../Cargo.toml) defines three members:
Console, Node, and the shared library. See the
[implementation status](backend/index.md#implementation-status) before
assuming that a declared dependency has a working adapter.

The [Rune-first architecture decision](../tasks/archive/2026-11/11-01-rune-durable-codemode/design.md)
records a high-level future direction. It does not prove that an engine,
database, actor role, protocol, or recovery path has been implemented.
Use current source to document those details when they exist.

## Maintaining These Specs

Write guidance in English. Cite the source, test, configuration, or approved
project decision behind each important rule. Keep observed behavior separate
from limitations and proposed improvements.

Update a topic and its index together when ownership changes. Keep detailed
commands in their owning guide instead of copying them into every index.
Use the [guide index](guides/index.md) for cross-cutting checks.

# Cross-Cutting Guides

These guides cover decisions spanning existing Beamlet files. Start with the
[spec index](../index.md) for package-local rules.

| Trigger | Guide |
| --- | --- |
| Moving behavior, adding a helper, or choosing shared ownership | [Code reuse](code-reuse-thinking-guide.md) |
| Adding an event or changing a package/build boundary | [Cross-layer changes](cross-layer-thinking-guide.md) |

Read the owning source before treating a similar-looking construct as a shared
contract. The Console event stream, the library example, bundled Trellis
tooling, and future durable operations have different purposes.

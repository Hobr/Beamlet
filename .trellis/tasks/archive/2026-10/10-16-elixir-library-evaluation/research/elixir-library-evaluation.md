# Elixir Library Suitability for Beamlet

Research date: **2026-10-16 (UTC)**. Local baseline: **`3ce315594043d7229812f91cb5f8da1fd487f3a6`**, branch `dev`.

## 1. Executive Decision

**Use the capabilities already present before adding infrastructure.** Telemetry, Telemetry.Metrics, and Gettext are already wired into the Phoenix application. The strongest new-library candidates are **Req for the first outbound HTTP integration** and **NimbleOptions for a substantial public configuration interface**. Neither is justification for adding a dependency to an otherwise unused application today.

The remaining candidates are useful at specific thresholds, not a baseline dependency bundle:

- **Cachex** when a measured, reconstructible caching workload appears; **Nebulex** when a cache abstraction, topology, or adapter requirement justifies it. Do not install both by default.
- **Instructor** only for an actual LLM-to-validated-data feature, not as an agent runtime; **Domo** only for sufficiently valuable struct invariants after a toolchain compatibility trial.
- **Tzdata** for named-timezone/DST calculations, not merely UTC timestamps or translated UI text.
- **ErrorTracker** when retained error triage justifies database and UI operations; **PromEx** when a Prometheus-compatible monitoring path is needed.
- **libcluster**, **Flow**, and **Broadway** only after multi-node discovery, substantial parallel data transformation, or producer-backed ingestion respectively becomes a real requirement.

These are research recommendations, **not approved implementation decisions**.

## 2. What Beamlet Actually Contains

| Local evidence | Observation | Implication |
| --- | --- | --- |
| `mix.exs`; `apps/*/mix.exs` | Six-app umbrella: actions, agent, harness, node, runtime, web. The root manifest's comment explicitly says root dependencies are not accessible as application dependencies. | Put any later dependency in the application that uses it; do not rely on incidental umbrella/transitive availability. |
| `apps/beamlet_web/mix.exs`; `mix.lock` | Direct `telemetry_metrics` and `gettext`, locked at 1.2.0 and 1.0.2. `telemetry` 1.4.2 is transitive through several web dependencies; `telemetry_poller` 1.3.0 is direct. | Three nominated libraries are already available. An application directly calling `:telemetry` should declare its own dependency when that code is introduced. |
| `apps/beamlet_web/lib/beamlet_web/{application,telemetry,endpoint}.ex` | Web supervision starts the telemetry supervisor and poller; Phoenix/VM metric definitions exist; endpoint uses `Plug.Telemetry`. Custom periodic measurements are currently empty. | Extend the existing observability seam; metric definitions alone do not create future domain events. |
| `apps/beamlet_web/lib/beamlet_web/router.ex`; `config/dev.exs` | LiveDashboard consumes `Beamlet.Web.Telemetry` under development routes. Router uses a per-request CSP nonce. | Dashboard visibility is currently development-oriented, not a deployed history/alerting system. Any additional operational UI needs access control and CSP review. |
| `apps/beamlet_web/lib/beamlet_web/gettext.ex`; `components/core_components.ex`; `apps/beamlet_web/priv/gettext/` | Gettext backend and actual calls exist, including error translation. The inspected English error catalog contains only its header. | Infrastructure exists, but this is not evidence of a complete multilingual product. |
| `apps/beamlet_{actions,agent,harness,node,runtime}/lib/beamlet/*.ex`; node's `application.ex`; their manifests | These modules expose generated `hello/0`; the node supervisor has no active workers; the five manifests have no active dependencies. | App names do not establish an implemented AI runtime, distributed scheduler, cache workload, or ingestion system. Proposed future owners below are conditional. |
| Application manifests, `mix.lock`, inspected supervision/configuration | No Ecto/database driver, nominated cache, broker producer, nominated HTTP client, cluster supervisor, or PromEx is declared/locked. | Persistence, clustering, caching and exporter infrastructure would be new work, not a small configuration toggle. |
| `flake.nix`; app manifests | Nix is configured for **OTP 29 / Elixir 1.20**. Five core manifests require `~> 1.20`; web requires `~> 1.17`. | Compatibility must be assessed against the configured newer toolchain, not just each library's minimum version. This research did not execute that toolchain. |

The dependency findings concern **declared/locked application dependencies**, not arbitrary packages that might exist in a developer's environment. Negative findings are bounded by the inspected tracked implementation; they are not a promise about future requirements.

## 3. Complete Decision Matrix

Priority meanings: **Leverage** = already present; **First candidate** = preferred when its stated near-term need appears; **Conditional** = wait for a concrete requirement; **Defer** = no current evidence justifies its complexity. All rows have a version/source record in section 4 and a detailed evaluation in section 5.

| # | Requested repository / Hex package | Current Beamlet status | Recommendation | Adoption trigger / likely boundary |
| --- | --- | --- | --- | --- |
| 1 | [wojtekmach/req](https://github.com/wojtekmach/req) / `req` | Not declared or locked | **First candidate** | First outbound API/HTTP integration; put transport behind the actual provider/action integration owner. |
| 2 | [lau/tzdata](https://github.com/lau/tzdata) / `tzdata` | Not declared or locked | **Conditional** | Named timezone conversion or wall-clock/DST scheduling; backend time policy, not locale selection. |
| 3 | [elixir-nebulex/nebulex](https://github.com/elixir-nebulex/nebulex) / `nebulex` | Not declared or locked | **Conditional** | Verified cache need plus an adapter/topology or multi-level-cache requirement. |
| 4 | [whitfin/cachex](https://github.com/whitfin/cachex) / `cachex` | Not declared or locked | **Conditional; first cache candidate** | Repeated expensive/reconstructible reads with measurable benefit and an invalidation policy. |
| 5 | [dashbitco/nimble_options](https://github.com/dashbitco/nimble_options) / `nimble_options` | Not declared or locked | **First candidate** | Nontrivial keyword options for a public runtime/action/provider interface. |
| 6 | [IvanRublev/Domo](https://github.com/IvanRublev/Domo) / `domo` | Not declared or locked | **Defer pending compatibility/value trial** | Real nested domain structs with costly invariant failures; first prove compiler/reload behavior on 1.20/29. |
| 7 | [thmsmlr/instructor_ex](https://github.com/thmsmlr/instructor_ex) / **`instructor`** | Neither repo alias nor actual package is declared/locked | **Conditional** | An LLM extraction/classification feature must produce validated structured values. |
| 8 | [beam-telemetry/telemetry](https://github.com/beam-telemetry/telemetry) / `telemetry` | Transitive, locked 1.4.2; framework instrumentation active | **Leverage** | Add explicit dependency and domain events in each application when it first emits/handles them. |
| 9 | [beam-telemetry/telemetry_metrics](https://github.com/beam-telemetry/telemetry_metrics) / `telemetry_metrics` | Direct web dependency, locked 1.2.0; definitions and Dashboard integration active | **Leverage** | Extend definitions alongside real events and choose a suitable reporter when needed. |
| 10 | [elixir-error-tracker/error-tracker](https://github.com/elixir-error-tracker/error-tracker) / `error_tracker` | Not declared or locked; no configured Ecto repo | **Conditional** | Persisted error grouping/triage is needed and storage/retention/admin access have owners. |
| 11 | [akoutmos/prom_ex](https://github.com/akoutmos/prom_ex) / `prom_ex` | Not declared or locked | **Conditional** | Operational metrics require scraping, history/alerts and an owned monitoring backend. |
| 12 | [bitwalker/libcluster](https://github.com/bitwalker/libcluster) / `libcluster` | Not declared or locked; no active cluster workers observed | **Defer until multi-node requirement** | Multiple BEAM nodes must automatically discover/connect; likely node/application supervision seam. |
| 13 | [dashbitco/flow](https://github.com/dashbitco/flow) / `flow` | Not declared or locked | **Defer until measured data-parallel workload** | A sufficiently large transformation/aggregation needs partitions/windows and beats simpler tools. |
| 14 | [elixir-broadway/broadway](https://github.com/elixir-broadway/broadway) / `broadway` | Not declared or locked | **Defer until ingestion requirement** | Producer-backed ingestion needs concurrency, backpressure, batching and acknowledgements. |
| 15 | [elixir-gettext/gettext](https://github.com/elixir-gettext/gettext) / `gettext` | Direct web dependency, locked 1.0.2; backend and calls active | **Leverage** | Continue using the existing backend for user-facing strings; add locales only when product scope requires them. |

## 4. Version and Maintenance Evidence

The following are **Hex API `latest_stable_version` snapshots queried on the research date**, not versions installed by this task. Release dates use release `inserted_at`, not package `updated_at`: metadata edits do not constitute a new release. Each version links directly to its official release metadata, including runtime requirements and retirement information. The queried releases had no retirement object. Publication recency is a maintenance signal, **not proof of project health or abandonment**.

| Package | Checked stable release | Release date (UTC) | Declared Elixir requirement | Evidence interpretation |
| --- | --- | --- | --- | --- |
| req | [0.7.5](https://hex.pm/api/packages/req/releases/0.7.5) | 2026-10-06 | `~> 1.15` | Recent release; default-branch README advertises a different 0.8 RC line. |
| tzdata | [1.2.2](https://hex.pm/api/packages/tzdata/releases/1.2.2) | 2026-09-26 | `~> 1.12` | Recent release; timezone data and HTTP-client behavior must be checked for this line. |
| nebulex | [3.0.4](https://hex.pm/api/packages/nebulex/releases/3.0.4) | 2026-05-03 | `~> 1.12` | Evaluate v3 plus chosen adapter, not old v2 installation examples. |
| cachex | [4.1.1](https://hex.pm/api/packages/cachex/releases/4.1.1) | 2025-06-30 | `~> 1.7` | Older release date alone does not justify rejecting it. |
| nimble_options | [1.1.1](https://hex.pm/api/packages/nimble_options/releases/1.1.1) | 2024-05-25 | `~> 1.9` | Small mature API; package metadata was updated later, which is not a 2026 release. |
| domo | [1.5.19](https://hex.pm/api/packages/domo/releases/1.5.19) | 2025-11-02 | `>= 1.15.0` | Compiler integration warrants stronger compatibility evidence than this lower bound. |
| instructor | [0.1.0](https://hex.pm/api/packages/instructor/releases/0.1.0) | 2025-02-09 | `~> 1.15` | Old release relative to fast-moving provider APIs; current-provider compatibility remains unverified. |
| telemetry | [1.4.2](https://hex.pm/api/packages/telemetry/releases/1.4.2) | 2026-05-11 | Erlang package; no Elixir requirement in metadata | Already matches Beamlet's lock; no OTP-29 execution proof is implied. |
| telemetry_metrics | [1.2.0](https://hex.pm/api/packages/telemetry_metrics/releases/1.2.0) | 2026-08-25 | `~> 1.14` | Already matches Beamlet's lock. |
| error_tracker | [0.9.0](https://hex.pm/api/packages/error_tracker/releases/0.9.0) | 2026-05-03 | `~> 1.15` | Account for Ecto SQL, database driver, migrations and LiveView, not just one package. |
| prom_ex | [1.12.0](https://hex.pm/api/packages/prom_ex/releases/1.12.0) | 2026-06-19 | `~> 1.14` | Reporter/exporter and integration dependencies are part of adoption cost. |
| libcluster | [3.5.0](https://hex.pm/api/packages/libcluster/releases/3.5.0) | 2025-01-09 | `~> 1.13` | Older publication does not establish abandonment; verify deployment strategy and runtime compatibility. |
| flow | [1.2.4](https://hex.pm/api/packages/flow/releases/1.2.4) | 2023-03-21 | `~> 1.7` | Long release interval; verify toolchain/performance rather than assuming failure or active support. |
| broadway | [1.3.0](https://hex.pm/api/packages/broadway/releases/1.3.0) | 2026-04-17 | `~> 1.7` | Recent release; selected producer/connector must be assessed separately. |
| gettext | [1.0.2](https://hex.pm/api/packages/gettext/releases/1.0.2) | 2025-11-08 | `~> 1.14` | Already matches Beamlet's lock; translation coverage remains a separate concern. |

Default-branch source snapshots were also inspected. Particularly important revisions are Req `f17c7086f5c792885ea7ff7190fd938e8b77aa87`, Domo `18c08ab427cd9b917932a9497f9983d754529522`, and Instructor `c6dcad9e70c0db0d54c65efb85b56de4129d847b`. These snapshots are **not substitutes for release contents**. Avoid copying a moving README's syntax or feature claims into a pinned-release integration without checking that release.

## 5. Per-Library Evaluation

### 5.1 Req — preferred first outbound HTTP client

**Sources:** [repository](https://github.com/wojtekmach/req), [0.7.5 API](https://hexdocs.pm/req/0.7.5/Req.html), [inspected changelog revision](https://github.com/wojtekmach/req/blob/f17c7086f5c792885ea7ff7190fd938e8b77aa87/CHANGELOG.md), and release metadata in section 4.

Req supplies a high-level HTTP API, JSON encoding/decoding, authentication, redirects, retry policy, streaming options and test stubs, with Finch as the default transport. This is a good fit for **a future external-service/action/provider integration**, but no such implementation was found in Beamlet. Place it behind the module that owns that integration rather than spreading transport configuration throughout web handlers or agent orchestration.

Adoption cost is low-to-medium: transport dependencies, connection pools, deadlines, cancellation, response/status mapping, and tests. In 0.7.5 the default retry policy is `:safe_transient`, covering GET/HEAD transient failures; non-idempotent calls require an explicit idempotency/retry policy. Streaming raw response chunks does not by itself implement a provider's SSE protocol, reconnect/resume semantics, or a whole-stream deadline. Restrict untrusted destinations/redirects, preserve TLS verification, and keep credentials/payloads out of logs.

**Version trap:** the inspected default branch documents **0.8 RC**, `Req.stream/4`, automatic SSE decoding, and changed internals/JSON handling. The stable metadata returned **0.7.5**. Treat these as different integration tracks; do not promise 0.8 APIs on the stable version. Prefer the stable track unless a separate task explicitly accepts prerelease risk.

**Decision:** first candidate when outbound HTTP becomes real; no dependency-only change now.

### 5.2 Tzdata — timezone rules, not a default timestamp dependency

**Sources:** [repository](https://github.com/lau/tzdata), [1.2.2 README](https://hexdocs.pm/tzdata/1.2.2/readme.html), and release metadata in section 4.

Tzdata implements IANA timezone rules and `Tzdata.TimeZoneDatabase` for Elixir's time APIs. Use it when backend behavior depends on named zones such as `Europe/Copenhagen`, local wall-clock scheduling, or daylight-saving transitions. Plain UTC timestamps do not justify it, and UI language does not select a timezone.

The documented configuration can set `:elixir, :time_zone_database` globally or pass the database module explicitly. Make that policy belong to the component defining time semantics, rather than adding a hidden global dependency just for formatting. Specify how ambiguous/nonexistent DST-local times are handled in any later scheduling design.

The library polls for timezone-data updates daily by default. Packaged/offline/read-only deployment needs an explicit choice: writable `data_dir` plus allowed outbound updates, or disabled autoupdate plus controlled data refresh in releases. This matters for Beamlet's Nix-oriented development/build setup. **Do not repeat the outdated claim that Hackney is mandatory:** 1.2-line documentation uses OTP `httpc` by default on OTP 25+ and deprecates Hackney support; release metadata marks Hackney optional.

**Decision:** conditional. Trigger on named-zone/DST requirements, with tests around transition boundaries and a data-update owner.

### 5.3 Nebulex — choose a cache abstraction and adapter deliberately

**Sources:** [repository](https://github.com/elixir-nebulex/nebulex), [v3 official adapters](https://hexdocs.pm/nebulex/3.0.4/nbx-adapters.html), [v3 upgrade guide](https://github.com/elixir-nebulex/nebulex/blob/v3.0.4/guides/upgrading/v3.0.md), and release metadata in section 4.

Nebulex is a cache API/framework with adapters. It is useful when a real caching boundary needs interchangeable storage implementations or a selected local, multi-level or distributed topology. That is different from needing a convenient cache for one expensive read.

**Version distinction matters:** in v3 the previously built-in storage/topology adapters moved into separate packages. The official list includes `nebulex_local`, `nebulex_distributed` with Partitioned/Multilevel/Coherent/Replicated adapters, and separate Redis/Cachex adapters. Core alone is not the whole chosen cache implementation. The v3 guide also changes API return conventions to ok/error tuples and bang variants; do not copy v2 examples indiscriminately.

Core requires NimbleOptions, with optional Telemetry and Decorator. The selected adapter adds its own dependencies, supervision, configuration and possibly external services. Adapter versions and consistency guarantees were **not independently audited** here; no universal replication or strong-consistency promise follows from adopting Nebulex.

A future domain owner must define authoritative data, miss recovery, tenant-aware keys, invalidation, acceptable staleness, memory/eviction, node loss and partition behavior. Keep cache access behind that owner rather than introducing cross-umbrella cache calls everywhere.

**Decision:** conditional, currently defer. Select it when a concrete adapter/topology/API-abstraction requirement outweighs the extra layer, not as an automatic upgrade after Cachex.

### 5.4 Cachex — a direct cache candidate, not categorically local-only

**Sources:** [repository](https://github.com/whitfin/cachex), [4.1.1 overview](https://hexdocs.pm/cachex/4.1.1/overview.html), [distributed-cache guide](https://hexdocs.pm/cachex/4.1.1/distributed-caches.html), and release metadata in section 4.

Cachex offers an in-memory cache API with expiration, size controls, warming/fallback patterns, hooks, statistics and other optional facilities. A plausible Beamlet use would be repeated expensive, reconstructible service metadata or read results once such a workload exists. There is currently no evidence of it. Begin with simple standard-library/ETS approaches if those actually satisfy the need; Cachex earns its dependency through lifecycle and policy features, not raw key/value storage alone.

Normal in-memory use needs no external database/broker, but the package is not dependency-free: Eternal, ExHashRing, Jumper, Sleeplocks and Unsafe are production dependencies. Supervise the cache and configure memory, TTL, miss behavior and observability; adding the dependency does not establish those policies.

**Do not label Cachex local-only.** Its Ring router supports consistent distributed key placement and optional node monitoring. The guide says data is not replicated to every node and describes cross-slot restrictions for multi-key operations. Function availability must be consistent across nodes. Filesystem save/restore is not a transactional durability or disaster-recovery guarantee; the library is an ephemeral cache, not a distributed database.

**Decision:** conditional, and the first cache candidate for a straightforward measured workload. Define hit-rate/latency targets, freshness, invalidation, tenant separation and failure recovery first. Start local unless actual deployment requirements justify distributed routing. Nebulex can itself wrap Cachex, so using both is only sensible with an explicit abstraction requirement.

### 5.5 NimbleOptions — a useful small public-options boundary

**Sources:** [repository](https://github.com/dashbitco/nimble_options), [1.1.1 API](https://hexdocs.pm/nimble_options/1.1.1/NimbleOptions.html), and release metadata in section 4.

NimbleOptions validates keyword-list options against schemas and can derive documentation. Required/default fields, nested option schemas and custom validators make it useful when a future runtime/action/provider API acquires a nontrivial option surface: timeouts, concurrency limits, retry limits, adapter choice, or capability switches. Prefer one schema at that API's boundary over repeated caller-specific validation.

Runtime package metadata for 1.1.1 declares **no dependencies**; it does not require a database or a custom compiler. This gives it a much smaller integration footprint than Domo or Instructor. It is not an arbitrary external-JSON decoder, environment-string parser, general domain invariant system, or LLM schema layer. Preserve the distinction between parsing external inputs and validating internal options; never atomize arbitrary user keys just to fit an options schema.

For one or two stable arguments, pattern matching/guards may remain simpler. Validate at construction/start boundaries, not repeatedly in a hot inner loop. Protect secrets in validation errors: do not assume a moving documentation page's newer options exist in 1.1.1. This evaluation does **not** rely on an automatic-redaction feature.

**Decision:** first candidate once the option surface is substantial; defer for generated stubs with no such API.

### 5.6 Domo — struct invariants with a meaningful compiler cost

**Sources:** [repository](https://github.com/IvanRublev/Domo), [1.5.19 API and installation](https://hexdocs.pm/domo/1.5.19/Domo.html), [inspected CI](https://github.com/IvanRublev/Domo/blob/18c08ab427cd9b917932a9497f9983d754529522/.github/workflows/ci.yml), and release metadata in section 4.

Domo generates constructors and validators from a struct's `t()` typespec and optional preconditions, including nested structs. This could reduce drift between declared types and checks if Beamlet later develops nontrivial domain objects. It complements static analysis; it is not automatic runtime enforcement of every ordinary struct literal, map update, or function call. Validation holds when the generated constructor/validator paths are actually used.

The cost is more than a normal dependency: `:domo_compiler` integration, generated type-ensurer code, dependency tracking, umbrella-specific compiler configuration, and Phoenix reload configuration if affected structs participate in reload. Dependencies include NimbleParsec; Ecto and Decimal are optional, so it is not inherently a database choice.

**Important compatibility gap:** the inspected CI explicitly tests Elixir **1.15.0 / OTP 24.3.3** and **1.19.1 / OTP 28.1**. Beamlet's configured 1.20/29 is not in that matrix. The package's `>= 1.15.0` constraint is not proof it works with newer compiler internals, nor proof it fails. A later adoption trial should test clean and incremental compilation, changed remote types, umbrella builds, reloads, Dialyzer and test coverage behavior.

**Decision:** defer. Start with explicit constructors/guards/typespecs unless invariant complexity and demonstrated compatibility justify this additional compiler layer.

### 5.7 Instructor — structured LLM output, not an agent platform

**Sources:** [repository](https://github.com/thmsmlr/instructor_ex), [0.1.0 API](https://hexdocs.pm/instructor/0.1.0/Instructor.html), [inspected changelog](https://github.com/thmsmlr/instructor_ex/blob/c6dcad9e70c0db0d54c65efb85b56de4129d847b/CHANGELOG.md), and release metadata in section 4.

The repository is named `instructor_ex`, but the Hex dependency is **`:instructor`**. It maps LLM output into Ecto schemas/types, supports validation and bounded re-asks, and documents provider adapters and partial/array streaming. An embedded schema can be used **without an Ecto database/repo**. The release brings Ecto, Jason, Jaxon and Req; it is materially more than a small JSON helper.

Its plausible boundary is a future provider/extraction integration used by an agent or action. It does **not** supply agent scheduling, permissions, a tool-execution loop, durable conversation state, or trustworthy reasoning. Valid schema/changeset output can still be factually wrong or unsafe. Streaming partial records must not authorize side effects before final validation; even final records require business authorization. Budget re-asks separately from transport retries to avoid multiplying latency and provider cost.

The most recent stable package returned is 0.1.0 from **2025-02-09**; inspected default-branch source has later changes. Documented provider coverage is not evidence that every current provider/model/protocol works in that published version. Validate the exact adapter, supported JSON-schema subset, validation behavior, stream cancellation/error cases, token accounting and secret handling before adopting it. Reusing Req directly with a provider's native structured-output API may be simpler for one narrow feature, but still requires validation.

**Decision:** conditional, behind a small provider-facing boundary and a focused compatibility/behavior trial once structured LLM output is a concrete feature.

### 5.8 Telemetry — extend the events already emitted

**Sources:** [repository](https://github.com/beam-telemetry/telemetry), [1.4.2 API](https://hexdocs.pm/telemetry/1.4.2/telemetry.html), and release metadata in section 4. Local evidence: `mix.lock`, web `endpoint.ex`, `telemetry.ex`, `application.ex`.

Telemetry dispatches named events with measurements and metadata; `span/3` emits start/stop/exception events around work. It is already transitively present, and Phoenix/Plug instrumentation is active. Once real actions/runtime operations exist, this is the natural foundation for duration, result and failure observations. Declare it directly in an application that owns calls to its API rather than depending on Phoenix to keep pulling it in.

Handlers execute **in the emitting process**. A slow handler adds latency; a handler that raises/exits/throws is removed. Keep handlers fast, nonblocking and safe, and avoid network/database work in the emission path. It is neither a durable event bus nor a metrics database or distributed tracing backend by itself.

Define bounded event names and measurement units together with the operation. Request IDs may help logs/traces, but arbitrary IDs, raw prompts, URLs and tool arguments should not become unbounded metric labels or sensitive metadata by default. Do not add hypothetical token/cost events until actual provider usage/accounting exists.

**Decision:** leverage immediately as the instrumentation convention for new real work; retain current framework instrumentation. No new observability framework is required just to emit events.

### 5.9 Telemetry.Metrics — the existing metric-definition layer

**Sources:** [repository](https://github.com/beam-telemetry/telemetry_metrics), [1.2.0 API](https://hexdocs.pm/telemetry_metrics/1.2.0/Telemetry.Metrics.html), and release metadata in section 4. Local evidence: web `mix.exs`, `telemetry.ex`, `router.ex`.

Telemetry.Metrics defines counters, sums, last values, summaries and distributions over telemetry events. It does **not** emit the application's missing domain events, perform durable storage, or automatically make every backend support every metric type. A reporter consumes definitions and aggregates/exports them.

Beamlet already defines Phoenix/VM summaries and routes LiveDashboard to this module in development. Extend that seam for real application measurements, with explicit unit conversions and bounded labels. A latency distribution for a later Prometheus reporter may need different choices from a development Dashboard summary; verify reporter support rather than copying the entire metric list blindly.

The additional adoption cost for using the current API is low. Production use still needs a decision about reporter/export, retention and access control. Prompt bodies, user IDs, job IDs and dynamic URLs should not be metric dimensions. Keep a consistent event/metric contract to avoid PromEx plugins and custom handlers exporting the same work twice under conflicting names.

**Decision:** leverage the existing dependency and wiring; add a reporter only for a real operational requirement.

### 5.10 ErrorTracker — self-hosted error triage with a real SQL cost

**Sources:** [repository](https://github.com/elixir-error-tracker/error-tracker), [0.9.0 getting started](https://hexdocs.pm/error_tracker/0.9.0/getting-started.html), [web/security guidance](https://hexdocs.pm/error_tracker/0.9.0/ErrorTracker.Web.html), [router nonce option](https://hexdocs.pm/error_tracker/0.9.0/ErrorTracker.Web.Router.html), and release metadata in section 4.

The Mix package is `error_tracker`. It supplies retained exception reporting/grouping and an optional web UI; documented integrations include Phoenix/LiveView, Plug and Oban plus manual reporting. This is useful for operational triage, but not automatic reporting of every failure anywhere in an application. Notifications require additional policy/integration, and retention/pruning needs explicit configuration.

**Storage is not optional merely because drivers are optional dependencies.** A consumer chooses PostgreSQL, MySQL/MariaDB or SQLite3 through an Ecto Repo and migrations. No ETS-only persistence path was established. For Beamlet, which has no configured database, this would introduce storage ownership, migrations, backups/availability and retention decisions. Embedded-Ecto use by Instructor would not supply this infrastructure.

For 0.9.0, published metadata requires Ecto/Ecto.SQL `~> 3.13`, Phoenix.Ecto `~> 4.6`, LiveView `~> 1.0` and Plug `~> 1.10`. Some overview prose lists looser older minima; use release metadata/tagged source for dependency resolution. Beamlet's LiveView 1.2.12 fits the declared range, but the complete graph remains untested.

Captured contexts can expose passwords or personal data. Add filtering, authenticated/authorized admin access, CSRF protection and retention limits. Its router supports `csp_nonce_assign_key`: evaluate this against Beamlet's nonce policy rather than blindly adopting general documentation advice to allow inline scripts/styles. Rendered-asset compatibility needs a later test.

**Decision:** conditional, currently defer. Do not add a SQL subsystem solely because an error dashboard looks convenient; first approve retained-triage requirements and its operational/security owner.

### 5.11 PromEx — production metric export, not metric-history storage

**Sources:** [repository](https://github.com/akoutmos/prom_ex), [1.12.0 API](https://hexdocs.pm/prom_ex/1.12.0/PromEx.html), and release metadata in section 4.

PromEx supplies plugin-oriented Telemetry collection, Prometheus-format export through a Plug, and Grafana dashboard integration. It is a plausible future extension to Beamlet's existing web supervision and instrumentation. It does not install a historical time-series service, an alerting service or a complete Grafana deployment just by being added to Mix.

Existing metric definitions and LiveDashboard remain useful, but PromEx does not automatically turn `Beamlet.Web.Telemetry.metrics/0` into the desired production dashboards. Select plugins/custom definitions deliberately. Account for overlapping measurements/exporters and polling so the same operation is not counted twice under conflicting names.

The dependency footprint includes Finch, Jason, OctoFetch, Peep, Telemetry, Telemetry.Metrics, TelemetryMetricsPrometheus.Core and Telemetry.Poller. Some are already in Beamlet; others and exporter configuration are new. Optional integration requirements still matter when those integrations are present: the checked release lists Phoenix `>= 1.7.0`, LiveView `>= 0.20.0`, and Ecto `>= 3.14.0` among them. This is not a requirement to add Ecto when it is otherwise unused.

Operational adoption needs a scraper/backend, retention/alert ownership, protected metrics exposure and any Grafana credentials. Keep labels bounded and non-sensitive; prompt bodies and arbitrary request IDs are not suitable dimensions.

**Decision:** conditional, the closest new observability extension. Prioritize when a deployment actually needs scrapeable production metrics/history/alerts. A smaller reporter may suffice if only a narrow export requirement exists; no exporter change is needed merely to keep using development LiveDashboard.

### 5.12 libcluster — node discovery and connection only

**Sources:** [repository](https://github.com/bitwalker/libcluster), [3.5.0 supervisor API](https://hexdocs.pm/libcluster/3.5.0/Cluster.Supervisor.html), and release metadata in section 4.

libcluster automatically forms/heals node connections using configured strategies: static/EPMD, DNS, Kubernetes, gossip and others. A future multi-node Beamlet could supervise `Cluster.Supervisor` at the node/application boundary after selecting the deployment strategy. There is no current deployment topology or active worker implementation establishing that need.

This solves discovery/connectivity, **not** leader election/consensus, distributed locks, application-state replication, exactly-once work, durable scheduling, or split-brain policy. Connecting nodes does not make local state safe or cause ordinary workers to distribute themselves.

Operational costs exceed the small code change: consistent node naming, distribution configuration, cookie management, reachable ports, discovery permissions and membership churn. Treat node connections as a trusted-system boundary; default Distributed Erlang connectivity is not a safe Internet-facing API. TLS/private networking and least-privilege discovery configuration require a separate deployment/security design. Multi-node failure and partition tests would be necessary before relying on the cluster.

Release 3.5.0 declares Jason and Telemetry dependencies, the latter `~> 1.3`, compatible at the requirement level with Beamlet's locked 1.4.2. That does not validate the whole toolchain or deployment.

**Decision:** defer until automatic membership discovery is needed on at least two deployed BEAM nodes. A single-node application does not benefit merely because an app is named `beamlet_node`.

### 5.13 Flow — parallel collection processing when its semantics pay off

**Sources:** [repository](https://github.com/dashbitco/flow), [1.2.4 API](https://hexdocs.pm/flow/1.2.4/Flow.html), [tagged manifest](https://github.com/dashbitco/flow/blob/v1.2.4/mix.exs), and release metadata in section 4.

Flow builds GenStage-based parallel transformations for bounded/unbounded data, with partitioning, windows and triggers. It could fit a later large local analysis or aggregation workload; it is not an agent execution framework. GenStage is its required production dependency, and finite local-enumerable use does not inherently need a broker or database.

The complexity is primarily semantic/tuning rather than package count: demand/batch size, stage concurrency, partition skew, reduction placement, window state, sink throughput and memory. Stateful reductions need intentional key placement. Do not assume global result order, durable input/state, or guaranteed speedups just because processing uses multiple stages.

The official documentation cautions that Flow is for sufficiently substantial workloads and discusses demand/batch tradeoffs. There is no Beamlet benchmark supporting it today. Release 1.2.4 dates to 2023-03-21; that is a freshness/verification consideration, not proof of abandonment or incompatibility with newer Elixir.

**Decision:** defer. Use Enum/Stream for simple transformations and consider bounded supervised Task concurrency for independent work. Reconsider Flow when a measured bottleneck and partitioned aggregation/windowing semantics justify it. A future trial must compare representative data, memory, correctness and end-to-end latency, not just task count.

### 5.14 Broadway — ingestion orchestration, not a durable queue/scheduler

**Sources:** [nominated repository](https://github.com/elixir-broadway/broadway), [1.3.0 API](https://hexdocs.pm/broadway/1.3.0/Broadway.html), [tagged manifest](https://github.com/elixir-broadway/broadway/blob/v1.3.0/mix.exs), and release metadata in section 4. Hex metadata still links to the historical Dashbit repository location; this is not an extra package.

Broadway supplies ingestion pipeline concurrency, backpressure, batching, acknowledgements, rate limiting, supervision, graceful shutdown and failure/testing hooks. A future external event/message source may benefit, but no such producer/source contract exists in the current implementation. Core depends on GenStage, NimbleOptions and Telemetry; real integration usually adds a source-specific producer/client, credentials and connection handling. A broker is not compulsory for every custom producer.

**Broadway does not supply retries out of the box:** the documented producer/source contract owns that behavior. Acknowledgements and supervised restarts do not establish durable storage, exactly-once side effects, or guaranteed recovery after abrupt node loss. Define redelivery, poison/dead-letter handling, replay, idempotent writes and acknowledgement timing with the actual source/sink.

Default ordering is not guaranteed. Partitioning helps route related messages, but failure/redelivery can still violate business order. Documented node-local rate limiting should not be mistaken for a global provider quota. Graceful draining is not a substitute for crash recovery.

**Decision:** defer until an ingestion source, throughput target and recovery contract exist. Use it for ingestion, not as a durable agent-job scheduler. Flow may fit transformation-heavy work better; bounded supervised tasks may suffice for small independent operations. None of these choices alone provides persistent agent workflow state.

### 5.15 Gettext — keep using the installed localization seam

**Sources:** [repository](https://github.com/elixir-gettext/gettext), [1.0.2 API](https://hexdocs.pm/gettext/1.0.2/Gettext.html), and release metadata in section 4. Local evidence: web `mix.exs`, `gettext.ex`, `components/core_components.ex`, `priv/gettext/`.

Gettext supplies message translation, interpolation, pluralization and domains, with extraction/merge tooling and PO catalogs. Beamlet already has the modern split between `use Gettext.Backend` and consumers using that backend; actual core-component/error calls demonstrate use beyond dependency declaration.

The useful action is to continue marking user-visible strings consistently and, if multilingual scope is approved later, extract/merge catalogs and establish translation/locale-selection workflows. The current small English catalog is not proof of completed localization, and this research does not choose target languages.

Runtime locale is process-local. Later HTTP, LiveView and spawned-task paths must deliberately set/propagate the intended locale; changing one request's locale is not a global user-preference system. Avoid interpolating untrusted values as HTML and distinguish translated display text from stable machine-readable error codes. Translation coverage and plural/interpolation tests remain product work.

The package does not solve named timezone conversion or a complete localized date/number formatting policy. Gettext and Tzdata can complement one another but neither implies the other is required.

**Decision:** leverage existing wiring. No replacement or extra localization package is justified by this evaluation.

## 6. Cross-Library Boundaries

### Cachex versus Nebulex

The distinction is **direct cache API/routing versus an adapter-oriented cache abstraction**, not local versus distributed. Both can participate in multi-node caching, and Nebulex has a separate Cachex adapter. Prefer the smallest solution satisfying freshness, invalidation, memory and recovery requirements. Do not install both as independent layers without an explicit reason. Neither an ephemeral cache nor a selected distributed topology automatically provides durable workflow state or universally strong consistency; inspect the chosen adapter/router behavior.

### NimbleOptions versus Domo versus Instructor

| Need | Candidate | What it does not establish |
| --- | --- | --- |
| Validate/document a keyword-options interface | NimbleOptions | Arbitrary external-data decoding, domain invariants or trusted LLM output |
| Validate nested struct types and explicit preconditions | Domo | Automatic enforcement on every struct mutation, or compatibility with every future compiler |
| Convert LLM responses into validated schema/type data | Instructor | Factual correctness, authorization, agent orchestration or durable state |

They are not competing implementations of one universal schema system. Use them at distinct boundaries only when needed. Ecto schemas for Instructor do not require a database; ErrorTracker's Ecto SQL persistence does. Do not add Domo on top of every Instructor/Ecto result without identifying an invariant that existing validation does not already own.

### Telemetry versus metric definitions versus PromEx versus ErrorTracker

```text
Actual application/framework work
  -> Telemetry events (measurements + metadata)
  -> Metric definitions + configured reporter/exporter
  -> Dashboard or external scraper/storage/alerting

Reported exceptions + approved context
  -> ErrorTracker + Ecto SQL persistence
  -> Authenticated triage UI / separately designed notifications
```

Telemetry is emission/dispatch; Telemetry.Metrics describes aggregation; a reporter/PromEx exports or aggregates; an external backend owns historical retention and operational alerting. ErrorTracker is complementary exception triage, not a substitute for latency/throughput/error-rate metrics. PromEx has its own plugin/configuration model; existing definitions are not automatically all adopted. Reuse event contracts and avoid duplicate instrumentation, unbounded labels and leaked secrets.

### Flow versus Broadway versus simpler OTP tools

- **Enum/Stream:** simplest sequential or lazy transformation when it meets requirements.
- **Bounded supervised tasks:** independent work with explicit concurrency/timeouts, where partitions/windows/producer acknowledgements are unnecessary.
- **Flow:** substantial data-parallel transformation/reduction with deliberate partition/window semantics.
- **Broadway:** source-backed ingestion with processors, batchers, backpressure and an acknowledgement contract.

Flow and Broadway overlap in staged processing, not in being durable workflow engines. Backpressure and supervision are not persistence or exactly-once business effects. Neither replaces an explicitly designed durable scheduler when that is the actual future need.

### libcluster, language and time are separate concerns

libcluster only establishes node discovery/connection; caching, scheduling and state coordination still need separate contracts. Gettext chooses translated messages, while Tzdata provides named-zone rules. A locale is not a timezone, and a `beamlet_node` application is not evidence that a distributed deployment is needed.

## 7. Suggested Adoption Order

1. **Now: keep and understand existing Telemetry / Telemetry.Metrics / Gettext.** Instrument actual behavior as it is implemented; no speculative domain events or extra localization scope.
2. **With first integrations: evaluate Req and substantial-options validation with NimbleOptions.** Choose direct application ownership, timeouts/errors/tests before introducing provider abstractions.
3. **At a concrete data or reliability need: trial one cache, Instructor, Tzdata, or Domo.** Each has a different trigger; do not make these a bundled prerequisite for the agent/runtime stubs.
4. **At operational deployment: choose retained error triage and/or a metrics exporter/backend deliberately.** ErrorTracker and PromEx solve different problems and introduce distinct operational obligations.
5. **Only after scale/topology evidence: libcluster, Flow or Broadway.** Document actual node membership, transformation size or producer/ack semantics first.

A later adoption task should start with one small representative integration and measurable success/failure behavior, not a broad dependency update.

## 8. Limits and Verification Still Required Before Adoption

- This was source/documentation/metadata research. No dependency installation, compilation, application tests, load tests, external service setup, or paid model requests were performed.
- Declared Elixir constraints are lower-bound/version-range evidence, not end-to-end certification for the configured Elixir 1.20 / OTP 29 environment. Domo's compiler coupling is especially material, but every selected dependency needs a real build/test gate.
- Default-branch source and even documentation examples can diverge from published package contents. Req's 0.8 RC versus 0.7.5 stable is explicit; Instructor adapters and newer NimbleOptions documentation need release-level checking as well.
- Repository archival status, issue response times, security advisories, and a complete dependency/license audit were not exhaustively assessed. No package is declared abandoned or production-safe solely from publication dates.
- No workload evidence establishes caching hit rate, ingestion throughput, data volume, multiple-node topology, required languages/timezones, or an LLM provider. Conditional recommendations must remain conditional until those decisions exist.
- No executable contract changed, so bootstrap code-specs were not updated. This report is research evidence, not a new coding standard or architecture mandate.

## 9. Research Validation Record

- Parent inspected all six application manifests, the root manifest/lockfile, non-web stubs, node/web supervision, telemetry/gettext wiring, router/endpoint, configuration and Nix toolchain declaration. External sources are cited at the owning claims and version table.
- A bounded, project-read-only background researcher independently inspected the six infrastructure candidates (Nebulex, Cachex, ErrorTracker, PromEx, Flow, Broadway), including official versioned docs and package metadata. Its relevant findings were incorporated here; scratch handoffs remain in managed session artifacts, not additional repository reports.
- Source contradictions were resolved explicitly: released package requirements take precedence over ErrorTracker overview minima; Req stable and RC documentation are not merged; Cachex distribution and Nebulex v3 adapter packaging are not oversimplified. Failed fetches/search summaries were not used as evidence.
- Final independent full-scope review (`aa7242cc-8aa6-4a58-98d3-38581a01c6a5`) returned **PASS, no P1/P2 factual or task-contract findings**. It independently checked all 15 release snapshots, local presence/use and key official capability claims. Managed review evidence remains in the session artifacts; results are also recorded in `../implement.md`.
- Coverage assertions passed for all 15 matrix rows/evaluations/release links; all 54 unique official source URLs returned HTTP 200 in a reachability check. Task context validation and final scope/whitespace checks passed. Reachability is not semantic verification, and runtime compatibility remains deliberately untested.

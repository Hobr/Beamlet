# Research Design

## Deliverable and Boundary

One consolidated research report: `.trellis/tasks/10-16-elixir-library-evaluation/research/elixir-library-evaluation.md`. This task designs an evaluation, not a production implementation. Keep repository documentation in English and present the decision summary to the user in Chinese.

## Evidence Flow

1. Inspect application manifests, lockfile, supervision trees, telemetry/gettext wiring, configuration, tests, and actual non-web implementations.
2. Read each nominated first-party repository and official documentation; consult Hex metadata and release/changelog records for current-version and compatibility facts. Record the actual research date; avoid unsupported claims of latest status.
3. Join package capabilities to observed local needs. Label hypothetical future integration points separately.
4. Build the decision matrix, compare alternatives/complements, then derive priority and explicit adoption triggers.

## Evaluation Contract

Each candidate records: repository/docs links; inspected version/revision when available; direct/transitive/absent dependency status; observed code use; purpose; evidence-backed Beamlet use; integration boundary; alternatives/overlap; compatibility constraints; implementation/operational burden; recommendation; trigger; uncertainty.

Decision labels: already present—leverage; prioritize when a specific near-term need exists; conditional; defer. Popularity and recency alone are not suitability criteria. Absence of recent commits is not proof of abandonment. Source-declared requirements are not proof of successful compilation on Beamlet's toolchain.

## Comparison Boundaries

- Cachex/Nebulex: local versus adapter/topology needs, invalidation, consistency, memory limits, and whether caching is needed at all.
- NimbleOptions/Domo/Instructor: configuration validation, runtime data/type validation, and LLM structured output are different contracts; inspect actual API/version before comparing.
- Telemetry/Telemetry.Metrics/PromEx/error tracking: event emission, metric definitions, export/storage/visualization, exception collection, cardinality, privacy, and deployment dependencies.
- Flow/Broadway: data-parallel transformations versus ingestion pipelines, backpressure, producer/acknowledgement behavior, and source-level durability; compare simpler standard-library/OTP tools where appropriate.
- libcluster: node discovery/connection is not consensus, durable jobs, scheduling, authentication policy, or automatic state replication.
- Req/tzdata/Gettext: assess HTTP needs, timezone versus locale requirements, existing usage, update behavior, retries/streaming, and packaged/offline deployment constraints where relevant.

## Tradeoffs and Compatibility

Prefer leveraging existing components over adding abstractions to generated stubs. No installation or runtime experiments in this research task. Explicitly mark validation steps that a later adoption task would need, including Elixir/OTP compatibility and operational/security review.

## Review and Rollback

Review coverage against all 15 repositories and local evidence; check source links and distinguish facts from recommendations. Only task artifacts should change. Rollback consists of reverting this task's documentation if requested; there is no application migration or runtime rollback.

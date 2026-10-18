
## Explicit durable storage composition

`Beamlet.Node.Storage.configuration(roles, storage)` validates the optional host
storage block and returns normalized settings. `datasets/2` supplies explicit
options without requiring executor identity for operator installation. Authority
uses `Beamlet.Agent.Storage.Profiles.authority/0`; executor uses
`Beamlet.Actions.Storage.Profiles.journal/0`. Both are dataset format3.
`Storage.start_link(storage: settings)` owns a generic `Beamlet.Storage.Host`
resource process and explicitly starts the default Admission gate required by
Runtime. Missing/refused resources keep the host running with safe reasons and
admission off. Every configured resource participates in admission, including
executor-only journal hosts. No datasets are initialized at boot.

`Storage.runtime/1` returns authority/journal handles, executor identity and a fresh
boot identity. `Storage.status/1` reports boot identity, fresh dataset status and
admission. A stopped Repo is unavailable. No configured storage, or interaction
roles alone, starts no Repo. Node has no Application callback; Server opts in.

`Beamlet.Node.Storage.Operator.initialize(roles, storage)` explicitly initializes
fresh datasets and stops only the Repos it started. The Mix command remains
`mix beamlet.storage.migrate --storage /absolute/trusted.exs --roles authority,executor`.
Old authority2/journal1 datasets refuse; use fresh paths, preserve old data and
never attempt an automatic upgrade or overwrite. Agent trace envelopes remain
format2 independently of dataset format3.

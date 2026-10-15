# OTP Execution Primitives: Initial Evidence

## Scope and Status

This note supports architecture planning, not implementation. User-owned requirements are authoritative in `../prd.md`; recommendations here are provisional. Environment synchronization, replication, and migration are explicitly outside project responsibility (R10).

The development shell configuration selects OTP 29 and Elixir 1.20 (`flake.nix`). The documentation fetched for this note identifies Elixir v1.20.4 and OTP 29.1.2. No local runtime or application behavior was tested.

## 1. Supervised Distributed Tasks

Primary sources:

- [Task: distributed tasks](https://hexdocs.pm/elixir/Task.html#module-distributed-tasks)
- [Task.Supervisor: async_nolink/5](https://hexdocs.pm/elixir/Task.Supervisor.html#async_nolink/5)
- [Task.Supervisor: OTP behaviour compatibility](https://hexdocs.pm/elixir/Task.Supervisor.html#async_nolink/3-compatibility-with-otp-behaviours)
- [Task.Supervisor: start_link/1](https://hexdocs.pm/elixir/Task.Supervisor.html#start_link/1)

Confirmed documentation facts:

- A named remote task supervisor can be addressed as `{supervisor_name, node}`. Tasks can be started remotely using explicit module/function/arguments.
- The Task documentation recommends explicit module/function/arguments for distributed tasks rather than anonymous functions, whose captured code expects the same module version on participating nodes.
- `async_nolink` avoids linking the task to its caller. It still uses monitoring and delivers a result message `{ref, result}` and a monitor `:DOWN` message; OTP behaviour callers can process these in `handle_info/2`.
- `async_nolink` tasks require the `:temporary` restart setting (the default), because restarting would invalidate the original task reference.
- Task supervisor configuration supports `:max_children`; asynchronous task startup can raise when the maximum is reached.

Architecture implications (inference, not selected contracts):

- OTP can supply supervised execution and result observation without a separate broker.
- A caller/coordinator should remain responsive while work runs; it should process completion messages rather than synchronously awaiting an entire LLM/Tool operation inside its state-management callback.
- Use a known executor entry point plus an action description rather than shipping caller closures as the public action abstraction. This also separates the execution mechanism from AI semantics.
- A task supervisor is not an action scheduler: capability matching, environment eligibility, local admission, normalized outcomes, and caller-facing action identity still require project-owned contracts.
- A task reference is an execution mechanism detail, not a sufficient long-term public action identifier. This is an interface concern only; it does not require persistence design.

## 2. Process-Group Discovery

Primary source:

- [Erlang :pg](https://www.erlang.org/doc/apps/kernel/pg.html)

Confirmed documentation facts:

- `:pg` provides named groups of processes, including membership across directly connected nodes.
- Membership implements strong eventual consistency; membership views may temporarily diverge.
- Visibility is not transitive through an intermediate node: directly disconnected nodes do not see one another's membership merely because both connect to a third node.
- A process can join only local processes into a group.
- Separate scopes are supported. Local membership is not preserved if the scope process exits and restarts.
- Group/scope monitoring supports membership update notifications.

Architecture implications (inference):

- A dedicated process-group scope is a candidate for discovering node agents or role endpoints without a consensus-backed registry.
- A membership group does not itself provide capability/resource reports, fresh capacity, a unique Agent authority, or placement guarantees.
- Scope supervision/re-registration and cluster connectivity assumptions must be explicit. No architecture should treat `:pg` as a globally atomic registry or a substitute for establishing the BEAM cluster.

## 3. Local Process Lookup

Primary source:

- [Elixir Registry](https://hexdocs.pm/elixir/Registry.html)

Confirmed documentation facts:

- `Registry` is local process storage supporting unique or duplicate keys.
- Its built-in PubSub use is local and non-distributed.

Architecture implications (inference):

- A local Registry can locate Agent processes on a known authority node. Remote routing must explicitly address that authority; a local Registry alone cannot locate Agents cluster-wide.
- UI-independent control should not depend on Phoenix merely to find or interact with an Agent.

## 4. Consequences of Confirmed Environment Locality

These are design deductions from R10, not OTP guarantees:

- Capability support, access to a particular environment, and available resource capacity are separate eligibility inputs.
- A node with a Shell Tool implementation is not automatically eligible for a Shell action targeting another node's session or filesystem.
- An environment reference denotes a provider-owned context; the generic runtime should consume opaque placement requirements rather than understand filesystem synchronization or sandbox internals.
- An eligible-node decision may use stale reports. The selected executor must still validate local capability/environment availability and admission before starting work; discovery cannot reserve remote capacity.
- No suitable executor must not silently cause execution in a different environment.

## 5. Supervision, Deployment, and Notification Choices

Primary sources:

- [DynamicSupervisor](https://hexdocs.pm/elixir/DynamicSupervisor.html)
- [Mix releases: umbrellas](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-umbrellas)
- [Mix releases: options](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-options)
- [Phoenix.PubSub: adapters](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html#module-adapters)
- [Erlang processes: signal delivery](https://www.erlang.org/doc/system/ref_man_processes.html#signal-delivery)
- [Erlang processes: monitors](https://www.erlang.org/doc/system/ref_man_processes.html#monitors)
- [Task.await/2: OTP behaviours](https://hexdocs.pm/elixir/Task.html#await/2-compatibility-with-otp-behaviours)
- [Task.shutdown/2](https://hexdocs.pm/elixir/Task.html#shutdown/2)

Confirmed documentation facts:

- `DynamicSupervisor` starts children on demand, supports `:one_for_one`, and can bound child count with `:max_children`. Dynamic child specification IDs are ignored; they do not provide unique Agent registration.
- An umbrella may define releases containing subsets of child applications. Release roots include their dependencies; a package split alone does not guarantee a role-specific deployment.
- Release application modes distinguish starting an application from loading it. A dependency of a started application cannot safely be forced into an incompatible mode merely to suppress its services; release validation checks unsafe combinations.
- Phoenix.PubSub is separately usable and its default distributed adapter exchanges notifications using Distributed Elixir, without Redis. It is an option, not a reason to depend on Phoenix Framework for core execution.
- Erlang signal ordering is scoped to a sender/receiver pair, not all cluster processes. Signal transport does not create a durable event log. Connection loss does not establish that a remote process has stopped.
- Task documentation advises against awaiting long-running tasks inside OTP behaviour callbacks. Task completion and monitor messages can instead be handled asynchronously.
- `Task.shutdown/2` is an owner-side shutdown/wait operation that can return an already-available result. It should not be confused with an instantaneous, guaranteed remote cancellation or a reversal of external effects.

Architecture implications (inference):

- Make reusable libraries export interfaces and child specifications without automatically activating every service. A top-level composition application can start the selected role subtrees, avoiding accidental Agent execution or web listeners on executor-only nodes.
- Use a local Registry for authority-local Agent uniqueness rather than relying on DynamicSupervisor child IDs or introducing a cluster-global uniqueness service.
- A single executor gateway can forward intermediate events and terminal outcomes to an action coordinator. Do not assume ordering among an HTTP provider process, a task process, and an independent result sender.
- Use ordinary subscription PIDs and monitoring for the initial Agent notification interface. Phoenix.PubSub remains a possible later fan-out implementation, not a mandatory core dependency.

## Confirmed Interaction Requirements and Limits

The user confirmed intermediate output and best-effort cancellation (R11–R12). OTP task completion alone does not define those contracts. Progress transport and cancellation must remain separate from durable delivery, replay, or rollback promises. Stopping a BEAM process cannot in general undo external side effects; concrete provider integrations own external-resource cleanup behavior. This is not a promise to terminate every OS child or remote LLM operation when its local task stops.

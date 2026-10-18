defmodule Beamlet.Agent.Durable do
  @moduledoc "Agent-owned input and reference orchestration over Agent authority format 3."
  import Kernel, except: [inspect: 1, inspect: 2]
  alias Beamlet.Agent.ContextBuilder
  alias Beamlet.Agent.Core.Decision
  alias Beamlet.Agent.Loader
  alias Beamlet.Agent.Reducer
  alias Beamlet.Agent.Resources
  alias Beamlet.Agent.Storage.AgentRecords
  alias Beamlet.Agent.Storage.Codec
  alias Beamlet.Runtime.Persistence
  @enforce_keys [:repo, :authority_id, :agent_id]
  defstruct [
    :repo,
    :authority_id,
    :agent_id,
    :definition,
    :version,
    :generation,
    :turn_id,
    :step,
    :runtime,
    :control
  ]

  def step(d), do: d.control["step"]
  def position(d), do: %{agent_id: d.agent_id, lock_version: d.version, generation: d.generation}
  def runtime(%{runtime: nil}), do: {:error, :missing_durable_runtime}
  def runtime(d), do: {:ok, d.runtime}

  def with_runtime(d, runtime) when is_map(runtime) do
    if runtime[:authority_repo] == d.repo and runtime[:journal_repo] != nil and
         Codec.uuid?(runtime[:executor_id]) and Codec.uuid?(runtime[:executor_boot_id]),
       do: {:ok, %{d | runtime: runtime}},
       else: {:error, :invalid_data}
  end

  def persistence(d, prepared) do
    with {:ok, r} <- runtime(d) do
      {:ok,
       %Persistence{
         authority_repo: r.authority_repo,
         journal_repo: r.journal_repo,
         authority_id: d.authority_id,
         executor_id: r.executor_id,
         executor_boot_id: r.executor_boot_id,
         dispatch_scope_id: prepared["dispatch_scope_id"],
         dispatch_epoch: prepared["dispatch_epoch"]
       }}
    end
  end

  def open(repo, attrs) do
    args = %{
      command_id: attrs.command_id,
      id: attrs.agent_id,
      authority_id: attrs.authority_id,
      definition: attrs.definition
    }

    args = if attrs[:alias], do: Map.put(args, :alias, attrs.alias), else: args

    with {:ok, response} <- AgentRecords.create_agent(repo, args),
         {:ok, control} <- Reducer.replay(Reducer.new(attrs.agent_id), response["events"]) do
      {:ok,
       %__MODULE__{
         repo: repo,
         authority_id: attrs.authority_id,
         agent_id: attrs.agent_id,
         definition: attrs.definition,
         version: response["lock_version"],
         generation: response["generation"],
         control: control,
         step: 0
       }}
    end
  end

  def inspect(locator, opts \\ []), do: Loader.load(locator.repo, locator.agent_id, opts)

  def accept_input(d, attrs) do
    args = %{
      command_id: attrs.command_id,
      position: position(d),
      turn_id: attrs.turn_id,
      input: %{"text" => attrs.text}
    }

    with :ok <- execution_gate(d),
         true <- d.control["continuation"] in ~w(await_input completed),
         :ok <- preflight(d, [{"input.accepted", args.input, attrs.turn_id}]),
         {:ok, response} <- write(d, :accept_input, args),
         {:ok, next} <- committed(d, response) do
      {:ok, next}
    else
      false -> {:error, :busy}
      error -> error
    end
  end

  def prepare(d, operations, role, sources, _policy \\ %{}) do
    with true <- role in ~w(model tool),
         {:ok, r} <- runtime(d),
         members =
           operations
           |> Enum.with_index()
           |> Enum.map(fn {item, ordinal} ->
             op = item.operation
             description = Persistence.description(op)

             %{
               operation: %{
                 id: Ecto.UUID.generate(),
                 owner_agent_id: d.agent_id,
                 turn_id: d.turn_id,
                 step_id: "step-#{d.control["step"] + if(role == "model", do: 1, else: 0)}",
                 role: role,
                 ordinal: ordinal,
                 tool_call_id: item[:id],
                 description: description,
                 sources: sources
               },
               attempt: %{
                 attempt_id: Ecto.UUID.generate(),
                 executor_id: r.executor_id,
                 executor_boot_id: r.executor_boot_id,
                 budget: %{"budget_ms" => op.budget_ms}
               }
             }
           end),
         :ok <- preflight(d, preparation_events(members)),
         {:ok, response} <-
           write(d, :prepare_operations, %{
             command_id: Ecto.UUID.generate(),
             position: position(d),
             turn_id: d.turn_id,
             operations: members,
             orchestration: %{"mode" => "all"}
           }),
         {:ok, next} <- committed(d, response) do
      {:ok, next, response["operations"]}
    else
      false -> {:error, :invalid_data}
      error -> error
    end
  end

  def consume(d, ids, position) do
    with {:ok, refs} <- accepted_refs(d, ids),
         specs =
           Enum.map(
             refs,
             &{"operation.result_consumed", Map.put(&1, "join", %{"position" => position}),
              d.turn_id}
           ),
         :ok <- preflight(d, specs),
         {:ok, response} <-
           write(d, :consume_results, %{
             command_id: Ecto.UUID.generate(),
             position: position(d),
             turn_id: d.turn_id,
             accepted_refs: refs,
             join: %{"position" => position}
           }) do
      committed(d, response)
    end
  end

  def accepted_refs(d, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, refs} ->
      with {:ok, %{"operation" => op}} <-
             Loader.operation(d.repo, d.agent_id, %{"operation_id" => id}),
           result when is_map(result) <- op["accepted_result"],
           true <-
             result["status"] not in ~w(uncertain cancelled deadline unknown) or
               Map.has_key?(d.control["resolutions"], id),
           {:ok, digest} <- Codec.digest(result, :result) do
        ref = %{
          "operation_id" => id,
          "accepted_digest" => digest,
          "consumption_kind" => consumption_kind(d, op, id)
        }

        {:cont, {:ok, refs ++ [ref]}}
      else
        _ -> {:halt, {:error, :unresolved_execution}}
      end
    end)
  end

  defp consumption_kind(d, op, id) do
    if Map.has_key?(d.control["resolutions"], id),
      do: "evidence_resolution",
      else: if(op["role"] == "model", do: "model_result", else: "tool_result")
  end

  def block(d, reason) do
    advance(d, "turn.interrupted", %{"reason" => to_string(reason)})
  end

  def decide(d, attrs) do
    ids = Enum.map(d.control["pending"], & &1["operation_id"])

    with :ok <- validate_decision(d, attrs.decision, ids),
         :ok <- resumable(d, ids, attrs.decision) do
      advance(
        d,
        "agent.continue_decided",
        %{
          "position" => d.control["continuation"],
          "resume_operations" => ids,
          "decision" => attrs.decision
        },
        attrs.command_id
      )
    else
      false -> {:error, :unresolved_execution}
      error -> error
    end
  end

  defp validate_decision(d, %{"risk" => "accepted"} = decision, _ids)
       when map_size(decision) == 1 do
    if d.control["environment_risk"] == "unconfirmed",
      do: :ok,
      else: {:error, {:blocked, :no_pending_risk}}
  end

  defp validate_decision(d, decision, _ids) when decision == %{}, do: execution_gate(d)

  defp validate_decision(d, %{"resolutions" => list} = decision, ids)
       when map_size(decision) == 1 and is_list(list) and length(list) in 1..8 do
    Enum.reduce_while(list, :ok, fn item, :ok ->
      case validate_resolution(d, item, ids) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_decision(d, decision, ids), do: validate_resolution(d, decision, ids)

  defp validate_resolution(d, %{"operation_id" => id, "resolution" => resolution} = decision, ids)
       when map_size(decision) == 2 and resolution in ~w(confirmed_failed confirmed_executed) do
    with true <- id in ids,
         {:ok, %{"operation" => %{"accepted_result" => %{"status" => status}}}} <-
           Loader.operation(d.repo, d.agent_id, %{"operation_id" => id}),
         true <- status in ~w(uncertain cancelled deadline unknown) do
      :ok
    else
      _ -> {:error, :invalid_reference}
    end
  end

  defp validate_resolution(_, _, _), do: {:error, :invalid_data}

  defp resumable(d, ids, decision) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      with {:ok, %{"operation" => op, "attempt" => attempt}} <-
             Loader.operation(d.repo, d.agent_id, %{"operation_id" => id}),
           true <- resumable_result?(op, attempt, decision) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :unresolved_execution}}
      end
    end)
  end

  defp resumable_result?(%{"accepted_result" => nil}, attempt, _decision),
    do: attempt["dispatch_state"] == "prepared"

  defp resumable_result?(op, _attempt, decision) do
    op["accepted_result"]["status"] not in ~w(uncertain cancelled deadline unknown) or
      Enum.any?(Reducer.decisions(decision), &(&1["operation_id"] == op["id"]))
  end

  defp advance(d, type, payload, command \\ nil) do
    with :ok <- preflight(d, [{type, payload, d.turn_id}]),
         {:ok, response} <-
           write(d, :advance, %{
             command_id: command || Ecto.UUID.generate(),
             position: position(d),
             turn_id: d.turn_id,
             type: type,
             payload: payload
           }),
         do: committed(d, response)
  end

  defp execution_gate(d) do
    if d.control["environment_risk"] == "unconfirmed",
      do: {:error, {:blocked, :environment_risk_unconfirmed}},
      else: :ok
  end

  @doc "Fork a safe committed sequence into paused, independent direct references."
  def fork(locator, through, expected, command) do
    with {:ok, source} <- fork_source(Map.get(locator, :source, %{})) do
      request = %{"through_seq" => through, "expected_version" => expected, "source" => source}

      case AgentRecords.command_response(locator.repo, locator.agent_id, command) do
        {:ok, %{"fork_request" => ^request} = response} -> fork_response(locator, response)
        {:ok, _} -> {:error, :conflict}
        {:error, :conflict} -> fork_new(locator, through, expected, command, request)
        error -> error
      end
    end
  end

  defp fork_source(source) when source == %{}, do: {:ok, %{}}

  defp fork_source(%{environment: environment} = source)
       when map_size(source) == 1 and environment in [:confirmed_stopped, :unconfirmed],
       do: {:ok, %{"environment" => Atom.to_string(environment)}}

  defp fork_source(_), do: {:error, :invalid_data}

  defp fork_new(locator, through, expected, command, request) do
    with {:ok, loaded} <- inspect(locator, through_seq: through),
         :ok <- inactive(loaded.agent),
         true <- loaded.agent["lock_version"] == expected,
         :ok <- safe_fork(loaded.control),
         :ok <- Resources.fence_agent(locator.agent_id, loaded.agent["generation"]),
         {:ok, messages} <- ContextBuilder.materialize(locator.repo, loaded.control),
         :ok <- ContextBuilder.complete_boundary(messages),
         risk =
           if(
             get_in(locator, [:source, :environment]) == :confirmed_stopped and
               is_nil(loaded.control["environment_risk"]),
             do: nil,
             else: "unconfirmed"
           ),
         args = %{
           command_id: command,
           fork_request: request,
           position: %{
             agent_id: locator.agent_id,
             lock_version: expected,
             generation: loaded.agent["generation"]
           },
           id: fork_id(command),
           through_seq: through,
           timeline: loaded.control["timeline"],
           inheritance: loaded.control["inheritance"],
           resolutions: loaded.control["resolutions"],
           risk: risk
         },
         {:ok, response} <- fork_write(locator, args) do
      fork_response(locator, response)
    else
      false -> {:error, :conflict}
      {:error, :already_active} -> {:error, :source_not_frozen}
      error -> error
    end
  end

  defp fork_response(locator, response) do
    {:ok,
     %{
       agent_id: response["agent_id"],
       locator: locator |> Map.put(:agent_id, response["agent_id"]) |> Map.delete(:source),
       version: response["lock_version"],
       generation: response["generation"],
       through_seq: response["through_seq"],
       risk: Enum.at(response["events"], 1)["payload"]["risk"],
       source: %{agent_id: locator.agent_id, through_seq: response["fork_request"]["through_seq"]}
     }}
  end

  # The new identity is stable across unknown outcomes and identical command replay.
  defp fork_id(command) do
    if Codec.uuid?(command), do: command, else: nil
  end

  defp fork_write(locator, args) do
    case AgentRecords.fork(locator.repo, args) do
      {:error, :storage_outcome_unknown} ->
        AgentRecords.command_response(locator.repo, locator.agent_id, args.command_id)

      result ->
        result
    end
  end

  defp safe_fork(control) do
    if Decision.safe_fork?(control),
      do: :ok,
      else: {:error, :unsafe_position}
  end

  def restore(locator, expected, command) when is_integer(expected) and expected >= 0 do
    with {:ok, loaded} <- inspect(locator),
         :ok <- inactive(loaded.agent),
         d = from_loaded(locator, loaded),
         {:ok, next} <- activate(d, expected, command) do
      {:ok, %{durable: next, alias: loaded.agent["alias"], control: next.control}}
    end
  end

  def restore(_, _, _), do: {:error, :invalid_data}

  defp inactive(agent) do
    if Process.whereis(Beamlet.Agent.Registry) &&
         Registry.lookup(Beamlet.Agent.Registry, agent["alias"] || agent["id"]) != [],
       do: {:error, :already_active},
       else: :ok
  end

  defp activate(%{version: expected} = d, expected, command) do
    with :ok <- Resources.fence_agent(d.agent_id, d.generation),
         {:ok, response} <- write(d, :restore, %{command_id: command, position: position(d)}),
         do: committed(d, response)
  end

  defp activate(d, expected, command) do
    with {:ok, %{"lock_version" => version, "events" => [%{"type" => "agent.activated"}]}} <-
           AgentRecords.command_response(d.repo, d.agent_id, command),
         true <- version == expected + 1 and version == d.version do
      {:ok, d}
    else
      _ -> {:error, :conflict}
    end
  end

  defp from_loaded(locator, loaded) do
    a = loaded.agent

    %__MODULE__{
      repo: locator.repo,
      authority_id: a["authority_id"],
      agent_id: a["id"],
      definition: a["definition"],
      version: a["lock_version"],
      generation: a["generation"],
      turn_id: loaded.control["turn_id"],
      step: loaded.control["step"],
      control: loaded.control,
      runtime: locator[:runtime]
    }
  end

  def context(d, catalogue), do: ContextBuilder.build(d.repo, d.control, catalogue)

  defp committed(d, response) do
    with {:ok, control} <- Reducer.replay(d.control, response["events"]) do
      {:ok,
       %{
         d
         | version: response["lock_version"],
           generation: response["generation"],
           turn_id: control["turn_id"],
           step: control["step"],
           control: control
       }}
    end
  end

  # Storage enforces transaction/reference invariants, not Agent policy. Reject
  # unsupported transitions before committing a history the pure reducer cannot read.
  defp preflight(d, specs) do
    events =
      specs
      |> Enum.with_index(d.control["through_seq"] + 1)
      |> Enum.map(fn {{type, payload, turn}, seq} ->
        %{
          "id" => Ecto.UUID.generate(),
          "scope_id" => d.agent_id,
          "seq" => seq,
          "schema_version" => 1,
          "type" => type,
          "payload" => payload,
          "turn_id" => turn,
          "operation_id" => payload["operation_id"]
        }
      end)

    case Reducer.replay(d.control, events) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp preparation_events(members) do
    Enum.map(members, fn %{operation: op} ->
      type = if op.role == "tool", do: "tool.batch_prepared", else: "model.request_prepared"

      {type,
       %{
         "operation_id" => op.id,
         "step_id" => op.step_id,
         "ordinal" => op.ordinal,
         "join" => %{"mode" => "all"}
       }, op.turn_id}
    end)
  end

  defp write(d, function, args) do
    case apply(AgentRecords, function, [d.repo, args]) do
      {:error, :storage_outcome_unknown} ->
        AgentRecords.command_response(d.repo, d.agent_id, args.command_id)

      result ->
        result
    end
  end
end

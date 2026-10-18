defmodule Beamlet.Agent.Durable do
  @moduledoc """
  Opt-in durable Agent history, checkpoints and paused restore.

  Every function here is one authority transaction through the stage-A/B record
  facades. Nothing reads application environment, starts a Repo or performs a
  network/handler effect: the caller (Server or embedding code) dispatches only
  after a commit returns. Checkpoints are self-contained plain data carrying the
  effective messages, pending Tool calls, ordered joins, consumption set and an
  explicit continuation; recovery reads the checkpoint and referenced Operation
  rows only, never historical events or old handlers.

  The definition stores references (provider/profile/environment/secret/artifact)
  and never credentials. Display entries, activities, annotation ids, PIDs, Refs
  and provider sessions are not persisted anywhere in this module.

  A durable Tool batch is dispatched through the normal Runtime: `with_runtime/2`
  attaches the live Repo handles and executor identities, `prepare_batch/2`
  commits one prepared attempt per Operation, and `persistence/2` yields the
  per-Operation Runtime configuration that binds dispatch to those rows. A durable
  Instance without that wiring blocks a Tool batch instead of dispatching it
  ephemerally; `restore/3` attaches the wiring the caller passes in its locator.
  """
  alias Beamlet.Actions.Operation
  alias Beamlet.Harness.Context
  alias Beamlet.Runtime.Persistence
  alias Beamlet.Storage.{AgentRecords, Artifacts, Codec, OperationRecords, Records}

  @schema_version 1
  @schema "beamlet.agent.checkpoint"
  @continuations ~w(await_input await_model_result reply_recorded await_tool_results results_to_consume blocked completed)
  @resolutions ~w(confirmed_failed confirmed_executed)
  @consumption_kinds ~w(tool_result model_result evidence_resolution)
  # Copy/provenance facts belong to the Agent, not to one turn, so every later
  # checkpoint of the same Agent carries them forward.
  @provenance_keys ~w(fork environment)

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
    :runtime
  ]

  def step(%__MODULE__{step: step}), do: step || 0

  @doc """
  Attaches the live Runtime wiring a durable Tool batch is dispatched through:
  `authority_repo`, `journal_repo`, `executor_id` and `executor_boot_id`. These are
  opaque Repo handles and stable executor identities, never credentials; nothing
  here is persisted or read from application environment.
  """
  def with_runtime(%__MODULE__{} = durable, runtime) when is_map(runtime) do
    with {:ok, runtime} <- runtime_config(runtime) do
      {:ok, %{durable | runtime: runtime}}
    end
  end

  @doc "The attached Runtime wiring, or `{:error, :missing_runtime}`."
  def runtime(%__MODULE__{runtime: nil}), do: {:error, :missing_runtime}
  def runtime(%__MODULE__{runtime: runtime}), do: {:ok, runtime}

  @doc """
  The per-Operation Runtime persistence for one prepared batch member. Its owner
  carries the reserved accept position, so the accepted Result lands on the row
  the batch committed instead of an unrelated Operation.
  """
  def persistence(%__MODULE__{} = durable, prepared) do
    with {:ok, turn_id} <- uuid(durable.turn_id),
         {:ok, accept_seq} <- count(Map.get(prepared, "accept_seq")) do
      runtime_persistence(durable, %{
        agent_id: durable.agent_id,
        turn_id: turn_id,
        expected_generation: durable.generation,
        accept_seq: accept_seq
      })
    end
  end

  @doc """
  Runtime persistence for the model step of a durable turn: it owns no Agent
  Operation, so it carries no owner position.
  """
  def model_persistence(%__MODULE__{} = durable), do: runtime_persistence(durable, nil)

  defp runtime_persistence(%__MODULE__{} = durable, owner) do
    with {:ok, runtime} <- runtime(durable) do
      {:ok,
       %Persistence{
         authority_repo: runtime.authority_repo,
         journal_repo: runtime.journal_repo,
         authority_id: durable.authority_id,
         executor_id: runtime.executor_id,
         executor_boot_id: runtime.executor_boot_id,
         owner: owner
       }}
    end
  end

  defp attach_runtime(durable, nil), do: {:ok, durable}
  defp attach_runtime(durable, runtime), do: with_runtime(durable, runtime)

  defp runtime_config(runtime) do
    with {:ok, authority_repo} <- repo(runtime[:authority_repo]),
         {:ok, journal_repo} <- repo(runtime[:journal_repo]),
         {:ok, executor_id} <- uuid(runtime[:executor_id]),
         {:ok, executor_boot_id} <- uuid(runtime[:executor_boot_id]) do
      {:ok,
       %{
         authority_repo: authority_repo,
         journal_repo: journal_repo,
         executor_id: executor_id,
         executor_boot_id: executor_boot_id
       }}
    end
  end

  ## Creation

  @doc """
  Creates the durable Agent, its initial `await_input` checkpoint and the creation
  command in one transaction. `definition` holds references only.
  """
  def open(repo, attrs) do
    with {:ok, input} <- validate_open(attrs),
         {:ok, definition_digest} <- digest(input.definition),
         {:ok, response} <-
           AgentRecords.create_agent(repo, %{
             command: command(input.agent_id, input.command_id, %{"create" => input.definition}),
             id: input.agent_id,
             authority_id: input.authority_id,
             alias: input.alias,
             definition: input.definition,
             generation: 0,
             # The initial checkpoint is always `await_input`; the facade owns that.
             checkpoint: %{id: input.checkpoint_id, data: state(%{}), safe_to_fork: true},
             event: event("agent.created", %{"definition_digest" => definition_digest})
           }) do
      {:ok,
       %__MODULE__{
         repo: repo,
         authority_id: input.authority_id,
         agent_id: input.agent_id,
         definition: input.definition,
         version: response["lock_version"],
         generation: 0,
         turn_id: nil
       }}
    end
  end

  ## Input acceptance

  @doc """
  Commits command dedupe, the input event, the turn and the `await_model_result`
  checkpoint before the caller may request a model reply. A stored command
  identity returns the stored turn and `replayed?: true`.
  """
  def accept_input(%__MODULE__{} = durable, attrs) do
    with {:ok, input} <- validate_input(attrs),
         :ok <- risk_clear(durable) do
      data =
        state_with_provenance(durable, %{
          "messages" => input.messages,
          "continuation" => "await_model_result",
          "turn_id" => input.turn_id,
          "step" => 0,
          "blocked" => nil
        })

      case AgentRecords.accept_input(durable.repo, %{
             command: command(durable.agent_id, input.command_id, %{"input" => input.params}),
             agent_id: durable.agent_id,
             expected_version: durable.version,
             expected_generation: durable.generation,
             turn_id: input.turn_id,
             checkpoint: checkpoint(input.checkpoint_id, data, "await_model_result", true),
             event: event("input.accepted", %{"turn_id" => input.turn_id})
           }) do
        {:ok, response} ->
          {:ok,
           %{
             turn_id: input.turn_id,
             version: response["lock_version"],
             generation: durable.generation,
             replayed?: response["checkpoint_id"] != input.checkpoint_id
           }}

        {:error, reason} ->
          {:error, normalize(reason)}
      end
    end
  end

  ## Full model reply

  @doc """
  Persists the complete normalized reply and its request identity before the batch
  is validated. The stored reply is re-validated on recovery instead of being
  requested again.
  """
  def record_reply(%__MODULE__{} = durable, attrs) do
    with {:ok, input} <- validate_reply(attrs),
         {:ok, request_digest} <- digest(input.request) do
      data =
        state_with_provenance(durable, %{
          "messages" => input.messages,
          "continuation" => "reply_recorded",
          "turn_id" => durable.turn_id,
          "step" => input.step,
          "assistant" => input.reply,
          "request_digest" => request_digest
        })

      AgentRecords.advance(durable.repo, %{
        agent_id: durable.agent_id,
        expected_version: durable.version,
        expected_generation: durable.generation,
        turn_id: durable.turn_id,
        checkpoint: checkpoint(input.checkpoint_id, data, "reply_recorded", false),
        event:
          event("model.reply_recorded", %{
            "turn_id" => durable.turn_id,
            "request_digest" => request_digest,
            "kind" => input.kind
          })
      })
      |> commit(durable)
    end
  end

  ## Tool batch

  @doc """
  Commits every Operation of the batch, its one prepared attempt, its event and
  the `await_tool_results` checkpoint in one transaction. Dispatch happens only
  after this returns and it must use the returned attempt identity, so the
  accepted Result lands on these rows.
  """
  def prepare_batch(%__MODULE__{} = durable, attrs) do
    with {:ok, runtime} <- runtime(durable),
         {:ok, calls} <- batch_calls(attrs[:calls]),
         {:ok, checkpoint_id} <- uuid(attrs[:checkpoint_id]),
         {:ok, messages} <- list(attrs[:messages]),
         {:ok, step} <- count(Map.get(attrs, :step, step(durable))),
         {:ok, order} <- call_ids(calls) do
      operations =
        calls
        |> Enum.with_index()
        |> Enum.map(fn {%{id: call_id, operation: operation}, index} ->
          %{
            id: call_operation_id(durable, call_id),
            description: Persistence.description(operation),
            owner_agent_id: durable.agent_id,
            turn_id: durable.turn_id,
            tool_call_id: call_id,
            ordinal: index + 1,
            attempt: attempt(operation, runtime)
          }
        end)

      data =
        state_with_provenance(durable, %{
          "messages" => messages,
          "continuation" => "await_tool_results",
          "turn_id" => durable.turn_id,
          "step" => step,
          "assistant" => Map.get(attrs, :assistant),
          "order" => order,
          "pending" => Enum.map(operations, &pending_entry/1),
          "results" => %{}
        })

      events =
        Enum.map(operations, fn operation ->
          event("operation.prepared", %{
            "operation_id" => operation.id,
            "tool_call_id" => operation.tool_call_id,
            "ordinal" => operation.ordinal
          })
        end)

      OperationRecords.prepare_batch(durable.repo, %{
        operations: operations,
        events: events,
        agent: %{
          expected_version: durable.version,
          expected_generation: durable.generation
        },
        checkpoint: checkpoint(checkpoint_id, data, "await_tool_results", false)
      })
      |> case do
        {:ok, %{"operations" => operations, "lock_version" => version}}
        when is_list(operations) and is_integer(version) ->
          {:ok, %{operations: operations, version: version}}

        {:ok, _response} ->
          {:error, :invalid_data}

        {:error, reason} ->
          {:error, normalize(reason)}
      end
    end
  end

  @doc """
  Commits the tool messages (in ordinal order), the consumption markers and the
  next checkpoint in one transaction. Consuming twice replays the stored markers;
  a partial overlap or a foreign Operation is a conflict.
  """
  def consume_results(%__MODULE__{} = durable, attrs) do
    with {:ok, operations} <- consumptions(attrs[:operations]),
         {:ok, checkpoint_id} <- uuid(attrs[:checkpoint_id]),
         {:ok, messages} <- list(attrs[:messages]),
         {:ok, order} <- list(attrs[:order]),
         {:ok, step} <- count(Map.get(attrs, :step, step(durable))) do
      data =
        state_with_provenance(durable, %{
          "messages" => messages,
          "continuation" => "await_model_result",
          "turn_id" => durable.turn_id,
          "step" => step,
          "pending" => [],
          "order" => [],
          "results" => %{},
          "assistant" => nil,
          "consumed" => order
        })

      AgentRecords.consume_result(durable.repo, %{
        agent_id: durable.agent_id,
        expected_version: durable.version,
        expected_generation: durable.generation,
        turn_id: durable.turn_id,
        operations: operations,
        # Every Tool result of the turn is in the context and nothing is in
        # flight, so this is a complete message boundary a fork may copy.
        checkpoint: checkpoint(checkpoint_id, data, "await_model_result", true)
      })
      |> case do
        {:ok, response} ->
          {:ok, %{consumed: response["consumed"], version: response["lock_version"]}}

        {:error, reason} ->
          {:error, normalize(reason)}
      end
    end
  end

  @doc """
  Records a blocked continuation (uncertain external effect, unconfirmed stop,
  missing journal) so progression waits for an explicit decision.
  """
  def block(%__MODULE__{} = durable, reason) do
    with {:ok, checkpoint_id} <- uuid(Ecto.UUID.generate()),
         {:ok, reason} <- safe_reason(reason),
         head = head(durable),
         {:ok, data} <- head_data(head, durable) do
      data =
        state(
          Map.merge(data, %{
            "continuation" => "blocked",
            "blocked" => %{"reason" => reason}
          })
        )

      durable
      |> advance_raw(checkpoint_id, data, "blocked", "agent.blocked", %{"reason" => reason})
      |> commit(durable)
    end
  end

  ## Decisions and continuation

  @doc """
  Records one explicit decision and returns the continuation to resume. Nothing is
  dispatched here.

  Two decisions exist beyond the plain blocked-state release:

    * `%{"risk" => "accepted"}` accepts a shared-environment risk a fork recorded as
      unconfirmed; it is the only way such an Agent may start work.
    * `%{"resolution" => "confirmed_executed" | "confirmed_failed", "operation_id" =>
      id}` resolves one stored accepted Result with later evidence. The accepted
      Result is never overwritten; an unanswered Tool-call slot is filled once from
      the stored Result, and a slot already consumed gets a separate correction
      message instead of a second Tool result.
  """
  def decide(%__MODULE__{} = durable, attrs) do
    with {:ok, input} <- validate_decision(attrs),
         head = head(durable),
         {:ok, data} <- head_data(head, durable),
         {:ok, plan} <- decision_plan(durable, data, input) do
      case plan do
        {:risk, next, data} ->
          accept_risk(durable, data, next, input)

        {:resolution, from, next, data, adoption} ->
          resolve(durable, data, from, next, input, adoption)
      end
    end
  end

  defp decision_plan(_durable, data, %{risk: "accepted"} = input) do
    environment = data["environment"]

    cond do
      Map.get(input, :resolution) != nil ->
        {:error, {:blocked, :ambiguous_decision}}

      data["continuation"] != "await_input" ->
        {:error, {:blocked, :unexpected_risk_position}}

      not is_map(environment) or environment["risk"] != "unconfirmed" ->
        {:error, {:blocked, :no_pending_risk}}

      true ->
        {:ok,
         {:risk, "await_input", state(Map.put(data, "environment", risk_accepted(environment)))}}
    end
  end

  defp decision_plan(_durable, data, %{operation_id: nil} = input) do
    with {:ok, next} <- next_continuation(data["continuation"], input.resolution),
         {:ok, decided} <- decision_data(data, next, input.resolution) do
      {:ok, {:resolution, data["continuation"], next, decided, nil}}
    end
  end

  defp decision_plan(durable, data, %{operation_id: operation_id} = input) do
    with {:ok, next} <- next_continuation(data["continuation"], input.resolution),
         {:ok, operation} <- adoption_operation(durable, operation_id),
         {:ok, messages} <- adopt_messages(data["messages"], operation, input.resolution),
         {:ok, decided} <-
           decision_data(Map.put(data, "messages", messages), next, input.resolution),
         {:ok, digest} <- result_digest(operation["accepted_result"]) do
      {:ok,
       {:resolution, data["continuation"], next, decided,
        %{operation_id: operation_id, accepted_digest: digest}}}
    end
  end

  defp risk_accepted(environment) do
    environment
    |> Map.merge(%{"risk" => nil, "risk_accepted" => true})
    |> Map.put("risk_acceptance", %{
      "source_agent_id" => Map.get(environment, "source_agent_id"),
      "source_checkpoint_id" => Map.get(environment, "source_checkpoint_id")
    })
  end

  defp accept_risk(durable, data, next, input) do
    payload = %{
      "continuation" => next,
      "risk" => "accepted",
      "source_agent_id" => get_in(data, ["fork", "source_agent_id"]),
      "source_checkpoint_id" => get_in(data, ["fork", "source_checkpoint_id"]),
      "command_id" => input.command_id
    }

    durable
    |> advance_raw(
      input.checkpoint_id,
      data,
      next,
      "agent.risk_accepted",
      payload,
      %{params: %{"risk" => %{"accept" => true}}, command_id: input.command_id},
      nil
    )
    |> decision_response(durable, next)
  end

  defp resolve(durable, data, from, next, input, adoption) do
    payload = %{
      "continuation" => next,
      "decision" => input.resolution,
      "command_id" => input.command_id,
      "operation_id" => input.operation_id,
      "adopted" => adoption != nil,
      "evidence" => input.evidence,
      "evidence_digest" => evidence_digest(input.evidence)
    }

    params = %{
      "continue" => %{
        "from" => from,
        "decision" => input.resolution,
        "operation_id" => input.operation_id
      }
    }

    durable
    |> advance_raw(
      input.checkpoint_id,
      data,
      next,
      "agent.decision",
      payload,
      %{params: params, command_id: input.command_id},
      adoption
    )
    |> decision_response(durable, next)
  end

  defp decision_response({:ok, response}, durable, next) do
    {:ok,
     %{continuation: next, version: response["lock_version"], generation: durable.generation}}
  end

  defp decision_response({:error, reason}, _durable, _next), do: {:error, normalize(reason)}

  # The stored Result is the accepted fact; a decision can only point at it.
  defp adoption_operation(durable, operation_id) do
    case OperationRecords.fetch(durable.repo, operation_id) do
      {:ok, %{"operation" => operation}} ->
        cond do
          operation["owner_agent_id"] != durable.agent_id ->
            {:error, {:blocked, :missing_operation}}

          is_nil(operation["accepted_result"]) ->
            {:error, {:blocked, :unresolved_effect}}

          true ->
            {:ok, operation}
        end

      _ ->
        {:error, {:blocked, :missing_operation}}
    end
  end

  defp adopt_messages(messages, operation, resolution) when is_list(messages) do
    call_id = operation["tool_call_id"]

    addition =
      if occupied?(messages, call_id),
        do: correction_message(operation, call_id, resolution),
        else: observation_message(operation, call_id, resolution)

    case Context.append(messages, [addition]) do
      {:ok, all} -> {:ok, all}
      {:error, _reason} -> {:error, :limit}
    end
  end

  defp adopt_messages(_messages, _operation, _resolution),
    do: {:error, {:blocked, :schema_unsupported}}

  defp occupied?(messages, call_id) do
    Enum.any?(messages, fn message ->
      Map.get(message, "role") == "tool" and Map.get(message, "call_id") == call_id
    end)
  end

  defp observation_message(operation, call_id, resolution) do
    result = operation["accepted_result"]

    %{
      "role" => "tool",
      "call_id" => call_id,
      "content" =>
        Jason.encode!(%{
          "status" => Map.get(result, "status"),
          "value" => Map.get(result, "value"),
          "reason" => Map.get(result, "reason"),
          "operation_id" => operation["id"],
          "resolution" => resolution,
          "adopted" => true
        })
    }
  end

  defp correction_message(operation, call_id, resolution) do
    status = Map.get(operation["accepted_result"], "status")

    %{
      "role" => "user",
      "content" =>
        "Late evidence resolved Tool call #{call_id} as #{resolution} " <>
          "(stored Result: #{status}, operation #{operation["id"]}). " <>
          "The accepted Result is unchanged; this is a review correction."
    }
  end

  defp evidence_digest(nil), do: nil

  defp evidence_digest(evidence) do
    case Codec.digest(evidence, :event) do
      {:ok, digest} -> digest
      {:error, _reason} -> nil
    end
  end

  defp result_digest(result) do
    case Codec.digest(result, :result) do
      {:ok, digest} -> {:ok, digest}
      {:error, _reason} -> {:error, :invalid_data}
    end
  end

  ## Fork

  @doc """
  Copies one immutable checkpoint of the source Agent into a new independent Agent
  in one authority transaction and returns its locator. The new Agent starts
  paused at `await_input` with the copied effective context, configuration and
  Tool schema; `forked_from_*` is provenance only, so loading it never reads the
  source.

  `locator.source` declares the source's operational state and is never inferred
  from reachability: `%{freeze: :frozen | :idle, environment: :confirmed_stopped |
  :unconfirmed}`; omitting it means `idle` and `unconfirmed`. A source that still
  has work in flight requires `freeze: :frozen`, and an unconfirmed stop marks the
  new Agent `environment.risk == "unconfirmed"`, which blocks input until an
  explicit `%{"risk" => "accepted"}` decision is recorded. Nothing is dispatched
  or executed here, and the source rows are not modified.
  """
  def fork(locator, checkpoint_id, expected_version, command_id) do
    with {:ok, loc} <- validate_locator(locator),
         {:ok, checkpoint_id} <- uuid(checkpoint_id),
         {:ok, version} <- count(expected_version),
         {:ok, command_id} <- uuid(command_id),
         {:ok, source} <- fork_source(loc[:source]),
         {:ok, fetched} <- fa(AgentRecords.fetch(loc.repo, loc.agent_id)),
         agent = fetched["agent"],
         {:ok, response} <-
           AgentRecords.fork(loc.repo, %{
             command:
               command(loc.agent_id, command_id, %{
                 "fork" => %{
                   "checkpoint_id" => checkpoint_id,
                   "version" => version,
                   "freeze" => Atom.to_string(source.freeze),
                   "environment" => Atom.to_string(source.environment)
                 }
               }),
             id: Ecto.UUID.generate(),
             new_checkpoint_id: Ecto.UUID.generate(),
             authority_id: agent["authority_id"],
             alias: nil,
             source_agent_id: loc.agent_id,
             checkpoint_id: checkpoint_id,
             expected_version: version,
             source: source,
             data: state(%{}),
             event:
               event("agent.forked", %{
                 "source_agent_id" => loc.agent_id,
                 "source_checkpoint_id" => checkpoint_id
               })
           }) do
      {:ok, fork_result(loc, response)}
    end
  end

  defp fork_source(nil), do: {:ok, %{freeze: :idle, environment: :unconfirmed}}

  defp fork_source(source) when is_map(source) do
    with {:ok, _} <- fields(source, [:freeze, :environment], []),
         freeze when freeze in [:frozen, :idle] <- source[:freeze],
         environment when environment in [:confirmed_stopped, :unconfirmed] <-
           source[:environment] do
      {:ok, %{freeze: freeze, environment: environment}}
    else
      _ -> {:error, :invalid_data}
    end
  end

  defp fork_source(_), do: {:error, :invalid_data}

  defp fork_result(loc, response) do
    %{
      agent_id: response["agent_id"],
      checkpoint_id: response["checkpoint_id"],
      version: response["lock_version"],
      generation: 0,
      risk: response["risk"],
      copied: response["copied"],
      source: %{
        agent_id: response["source_agent_id"],
        checkpoint_id: response["source_checkpoint_id"]
      },
      locator: %{
        repo: loc.repo,
        agent_id: response["agent_id"],
        model: loc[:model],
        tools: Map.get(loc, :tools, %{}),
        catalogue: Map.get(loc, :catalogue, %{}),
        environment: loc[:environment],
        runtime: loc[:runtime]
      }
    }
  end

  ## Restore

  @doc """
  Loads a paused instance from the head checkpoint and referenced Operation rows.

  `locator` carries the authority Repo, the stable `agent_id` and the live
  dependency resolution (`model`, `tools`, `environment`). A missing dependency or
  artifact returns `{:error, {:blocked, reason}}` after writing nothing, so no
  substitute environment or node is used and zero work is dispatched.
  """
  def restore(locator, expected_version, command_id) do
    with {:ok, loc} <- validate_locator(locator),
         {:ok, version} <- count(expected_version),
         {:ok, command_id} <- uuid(command_id),
         {:ok, fetched} <- fa(AgentRecords.fetch(loc.repo, loc.agent_id)),
         agent = fetched["agent"],
         head = fetched["head_checkpoint"],
         :ok <- present(head),
         :ok <- supported(agent, head),
         :ok <- dependencies(loc, agent["definition"]),
         :ok <- pending_state(loc.repo, head["data"]),
         {:ok, data} <- head_data(head, nil),
         restored_id = Ecto.UUID.generate(),
         {:ok, response} <-
           AgentRecords.restore(loc.repo, %{
             command:
               command(
                 loc.agent_id,
                 command_id,
                 %{"restore" => %{"checkpoint_id" => head["id"], "version" => version}}
               ),
             agent_id: loc.agent_id,
             expected_version: version,
             expected_generation: agent["generation"],
             turn_id: head["turn_id"],
             checkpoint:
               checkpoint(
                 restored_id,
                 Map.put(data, "restored_generation", agent["generation"] + 1),
                 data["continuation"],
                 false
               ),
             event:
               event("agent.restored", %{
                 "source_checkpoint_id" => head["id"],
                 "generation" => agent["generation"] + 1,
                 "continuation" => data["continuation"]
               })
           }) do
      durable = %__MODULE__{
        repo: loc.repo,
        authority_id: agent["authority_id"],
        agent_id: loc.agent_id,
        definition: agent["definition"],
        version: response["lock_version"],
        generation: response["generation"],
        turn_id: data["turn_id"]
      }

      with {:ok, durable} <- attach_runtime(durable, loc[:runtime]) do
        {:ok,
         %{
           durable: durable,
           checkpoint: data,
           checkpoint_id: restored_id,
           alias: agent["alias"],
           locator: loc
         }}
      end
    end
  end

  ## Checkpoint/state helpers

  @doc "The plain checkpoint state; display data is never part of it."
  def state(overrides) do
    Map.merge(
      %{
        "schema" => @schema,
        "version" => @schema_version,
        "messages" => [],
        "continuation" => "await_input",
        "turn_id" => nil,
        "step" => 0,
        "pending" => [],
        "order" => [],
        "consumed" => [],
        "assistant" => nil,
        "results" => %{},
        "blocked" => nil,
        "request_digest" => nil
      },
      overrides
    )
  end

  defp state_with_provenance(durable, overrides) do
    case head(durable) do
      %{"data" => data} when is_map(data) ->
        state(Map.merge(Map.take(data, @provenance_keys), overrides))

      _ ->
        state(overrides)
    end
  end

  @doc "Bounded server-side state of a restored checkpoint, with no live PIDs/Refs."
  def restored_state(%{checkpoint: data}), do: data

  def continuations, do: @continuations

  ## Internal writes

  # `command_identity` carries the two command fields (`:params`, `:command_id`) so
  # a durable advance stays within the argument bound.
  defp advance_raw(
         durable,
         checkpoint_id,
         data,
         continuation,
         type,
         payload,
         command_identity,
         adoption
       ) do
    attrs = %{
      agent_id: durable.agent_id,
      expected_version: durable.version,
      expected_generation: durable.generation,
      turn_id: durable.turn_id,
      checkpoint: checkpoint(checkpoint_id, data, continuation, false),
      event: event(type, payload),
      command: command(durable.agent_id, command_identity.command_id, command_identity.params)
    }

    attrs = if is_nil(adoption), do: attrs, else: Map.put(attrs, :adoption, adoption)
    AgentRecords.advance(durable.repo, attrs)
  end

  defp advance_raw(durable, checkpoint_id, data, continuation, type, payload) do
    AgentRecords.advance(durable.repo, %{
      agent_id: durable.agent_id,
      expected_version: durable.version,
      expected_generation: durable.generation,
      turn_id: durable.turn_id,
      checkpoint: checkpoint(checkpoint_id, data, continuation, false),
      event: event(type, payload)
    })
  end

  defp commit({:ok, response}, _durable),
    do: {:ok, %{version: response["lock_version"], checkpoint_id: response["checkpoint_id"]}}

  defp commit({:error, reason}, _durable), do: {:error, normalize(reason)}

  defp head(%__MODULE__{repo: repo, agent_id: agent_id}) do
    case AgentRecords.fetch(repo, agent_id) do
      {:ok, %{"head_checkpoint" => head}} -> head
      _ -> nil
    end
  end

  defp head_data(nil, _durable), do: {:error, {:blocked, :missing_checkpoint}}

  defp head_data(%{"data" => data}, durable) when is_map(data) do
    continuation = data["continuation"]

    cond do
      data["schema"] != @schema -> {:error, {:blocked, :schema_unsupported}}
      continuation not in @continuations -> {:error, {:blocked, :schema_unsupported}}
      is_nil(durable) -> {:ok, data}
      durable.turn_id not in [nil, data["turn_id"]] -> {:error, {:blocked, :turn_mismatch}}
      true -> {:ok, data}
    end
  end

  defp head_data(_, _), do: {:error, {:blocked, :schema_unsupported}}

  defp next_continuation("blocked", decision) do
    if decision in @resolutions,
      do: {:ok, "await_input"},
      else: {:error, {:blocked, :unresolved_effect}}
  end

  defp next_continuation(current, _decision) when current in ["await_input", "completed"],
    do: {:ok, "await_input"}

  defp next_continuation(current, _decision), do: {:ok, current}

  defp decision_data(data, "await_input", decision) do
    {:ok,
     state(
       Map.merge(data, %{
         "continuation" => "await_input",
         "turn_id" => nil,
         "blocked" => nil,
         "pending" => [],
         "order" => [],
         "results" => %{},
         "assistant" => nil,
         "decision" => decision
       })
     )}
  end

  defp decision_data(data, next, decision),
    do: {:ok, state(Map.merge(data, %{"continuation" => next, "decision" => decision}))}

  # A forked Agent may not start work while its shared-environment risk is
  # unconfirmed. The version CAS on the write still fences the read: an acceptance
  # moves the Agent version, so a stale caller cannot pass this with an old version.
  defp risk_clear(%__MODULE__{repo: repo, agent_id: agent_id}) do
    case AgentRecords.fetch(repo, agent_id) do
      {:ok, %{"head_checkpoint" => %{"data" => data}}} when is_map(data) ->
        case data["environment"] do
          %{"risk" => "unconfirmed"} -> {:error, {:blocked, :environment_risk_unconfirmed}}
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  ## Dependency references

  defp dependencies(loc, definition) do
    with {:ok, model} <- model_reference(definition),
         :ok <- model_match(model, loc[:model]),
         :ok <- secret_ref(model, loc[:model]),
         :ok <- tools_match(definition["tools"], loc[:tools]),
         :ok <- environment(definition, loc) do
      artifacts(loc.repo, definition)
    end
  end

  defp model_reference(definition) do
    case definition do
      %{"model" => %{"provider" => provider} = model} when is_binary(provider) -> {:ok, model}
      _ -> {:error, {:blocked, :missing_model}}
    end
  end

  defp model_match(model, binding) when is_map(binding) do
    if Map.get(binding, :provider) == model["provider"],
      do: :ok,
      else: {:error, {:blocked, :provider_mismatch}}
  end

  defp model_match(_model, _binding), do: {:error, {:blocked, :missing_model}}

  defp secret_ref(model, binding) when is_map(binding) do
    if Map.get(model, "secret_ref") == nil or map_size(Map.get(binding, :credentials, %{})) > 0,
      do: :ok,
      else: {:error, {:blocked, :missing_secret}}
  end

  defp secret_ref(_model, _binding), do: {:error, {:blocked, :missing_secret}}

  defp tools_match(nil, _tools), do: :ok

  defp tools_match(tools, resolved) when is_map(tools) and is_map(resolved) do
    missing =
      Enum.find_value(tools, fn {name, reference} ->
        expected = reference["profile"]

        case Map.fetch(resolved, name) do
          {:ok, %{id: ^expected}} -> nil
          _ -> :missing_profile
        end
      end)

    if missing, do: {:error, {:blocked, missing}}, else: :ok
  end

  defp tools_match(tools, _resolved) when is_map(tools),
    do: {:error, {:blocked, :missing_profile}}

  defp tools_match(_tools, _resolved), do: :ok

  defp environment(%{"environment" => nil}, _loc), do: :ok

  defp environment(%{"environment" => reference}, loc) do
    if loc[:environment] == reference, do: :ok, else: {:error, {:blocked, :missing_environment}}
  end

  defp environment(_definition, _loc), do: :ok

  defp artifacts(repo, definition) do
    ids =
      definition
      |> Map.get("tools", %{})
      |> Enum.flat_map(fn {_name, reference} -> Map.get(reference, "artifact_refs", []) end)
      |> Enum.uniq()

    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case Artifacts.fetch(repo, id) do
        {:ok, _} -> {:cont, :ok}
        _ -> {:halt, {:error, {:blocked, :artifact_missing}}}
      end
    end)
  end

  defp pending_state(repo, %{"pending" => pending}) when is_list(pending) do
    Enum.reduce_while(pending, :ok, &pending_entry_state(repo, &1, &2))
  end

  defp pending_state(_repo, _data), do: {:error, {:blocked, :schema_unsupported}}

  defp pending_entry_state(repo, entry, :ok) do
    case OperationRecords.fetch(repo, entry["operation_id"]) do
      {:ok, %{"operation" => operation}} -> accepted_entry_state(operation)
      _ -> {:halt, {:error, {:blocked, :missing_operation}}}
    end
  end

  defp accepted_entry_state(operation) do
    if operation["accepted_result"],
      do: {:cont, :ok},
      else: {:halt, {:error, {:blocked, :unconfirmed_tool_result}}}
  end

  defp supported(agent, head) do
    cond do
      get_in(agent, ["definition", "schema_version"]) != @schema_version ->
        {:error, {:blocked, :schema_unsupported}}

      head["schema_version"] != @schema_version ->
        {:error, {:blocked, :schema_unsupported}}

      true ->
        :ok
    end
  end

  defp present(nil), do: {:error, {:blocked, :missing_checkpoint}}
  defp present(_head), do: :ok

  ## Validation

  defp validate_open(attrs) do
    with {:ok, _} <- fields(attrs, [:agent_id, :authority_id, :definition, :command_id], [:alias]),
         {:ok, agent_id} <- uuid(attrs[:agent_id]),
         {:ok, authority_id} <- uuid(attrs[:authority_id]),
         {:ok, command_id} <- uuid(attrs[:command_id]),
         {:ok, alias_name} <- text(attrs[:alias], 255),
         {:ok, definition} <- definition(attrs[:definition]) do
      {:ok,
       %{
         agent_id: agent_id,
         authority_id: authority_id,
         command_id: command_id,
         alias: alias_name,
         definition: definition,
         checkpoint_id: Ecto.UUID.generate()
       }}
    end
  end

  defp validate_input(attrs) do
    with {:ok, _} <- fields(attrs, [:command_id, :turn_id, :messages, :checkpoint_id], []),
         {:ok, command_id} <- uuid(attrs[:command_id]),
         {:ok, turn_id} <- uuid(attrs[:turn_id]),
         {:ok, checkpoint_id} <- uuid(attrs[:checkpoint_id]),
         {:ok, messages} <- list(attrs[:messages]) do
      {:ok,
       %{
         command_id: command_id,
         turn_id: turn_id,
         checkpoint_id: checkpoint_id,
         messages: messages,
         params: hd(Enum.reverse(messages))
       }}
    end
  end

  defp validate_reply(attrs) do
    with {:ok, _} <- fields(attrs, [:request, :messages, :reply, :checkpoint_id], [:step]),
         {:ok, messages} <- list(attrs[:messages]),
         {:ok, reply} <- map(attrs[:reply]),
         {:ok, step} <- count(Map.get(attrs, :step, 0)),
         {:ok, kind} <- text(reply["kind"], 32) do
      {:ok,
       %{
         request: attrs[:request],
         messages: messages,
         reply: reply,
         kind: kind,
         step: step,
         checkpoint_id: attrs[:checkpoint_id]
       }}
    end
  end

  defp validate_decision(attrs) do
    with {:ok, _} <- fields(attrs, [:command_id, :checkpoint_id], [:decision]),
         {:ok, command_id} <- uuid(attrs[:command_id]),
         {:ok, checkpoint_id} <- uuid(attrs[:checkpoint_id]),
         {:ok, decision} <- decision(attrs[:decision]) do
      {:ok,
       %{
         command_id: command_id,
         checkpoint_id: checkpoint_id,
         resolution: decision.resolution,
         risk: decision.risk,
         operation_id: decision.operation_id,
         evidence: decision.evidence
       }}
    end
  end

  defp decision(nil), do: {:ok, %{resolution: nil, risk: nil, operation_id: nil, evidence: nil}}

  defp decision(value) when is_map(value) and not is_struct(value) do
    with {:ok, keys} <- decision_keys(value),
         {:ok, resolution} <- resolution(keys[:resolution]),
         {:ok, risk} <- decision_risk(keys[:risk]),
         {:ok, operation_id} <- decision_operation(keys[:operation_id]),
         {:ok, evidence} <- decision_evidence(keys[:evidence]),
         :ok <- decision_shape(resolution, risk, operation_id) do
      {:ok, %{resolution: resolution, risk: risk, operation_id: operation_id, evidence: evidence}}
    end
  end

  defp decision(_), do: {:error, {:blocked, :unresolved_effect}}

  defp decision_keys(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, child}, {:ok, acc} ->
      case decision_key(key) do
        nil -> {:halt, {:error, :invalid_data}}
        key -> {:cont, {:ok, Map.put(acc, key, child)}}
      end
    end)
  end

  defp decision_key(key) when key in [:resolution, :risk, :operation_id, :evidence], do: key
  defp decision_key("resolution"), do: :resolution
  defp decision_key("risk"), do: :risk
  defp decision_key("operation_id"), do: :operation_id
  defp decision_key("evidence"), do: :evidence
  defp decision_key(_), do: nil

  defp resolution(nil), do: {:ok, nil}
  defp resolution(value) when value in @resolutions, do: {:ok, value}
  defp resolution(_), do: {:error, {:blocked, :unresolved_effect}}

  defp decision_risk(nil), do: {:ok, nil}
  defp decision_risk("accepted"), do: {:ok, "accepted"}
  defp decision_risk(_), do: {:error, {:blocked, :unresolved_effect}}

  defp decision_operation(nil), do: {:ok, nil}
  defp decision_operation(value), do: uuid(value)

  defp decision_evidence(nil), do: {:ok, nil}
  defp decision_evidence(value), do: json(value)

  defp decision_shape(nil, nil, nil), do: :ok
  defp decision_shape(resolution, nil, _operation_id) when resolution != nil, do: :ok
  defp decision_shape(nil, "accepted", nil), do: :ok
  defp decision_shape(nil, "accepted", _operation_id), do: {:error, :invalid_data}
  defp decision_shape(_resolution, _risk, _operation_id), do: {:error, :invalid_data}

  defp validate_locator(locator) when is_map(locator) do
    with {:ok, repo} <- repo(locator[:repo]),
         {:ok, agent_id} <- uuid(locator[:agent_id]) do
      {:ok, Map.put(locator, :repo, repo) |> Map.put(:agent_id, agent_id)}
    end
  end

  defp validate_locator(_), do: {:error, :invalid_data}

  defp repo(module) when is_atom(module) and not is_nil(module) do
    if function_exported?(module, :get, 3), do: {:ok, module}, else: {:error, :invalid_data}
  end

  defp repo(_), do: {:error, :invalid_data}

  defp definition(definition) when is_map(definition) do
    keys = Map.keys(definition)

    with true <- Enum.all?(keys, &(&1 in ~w(schema_version model tools environment))),
         @schema_version <- definition["schema_version"],
         {:ok, _model} <- model_reference(definition),
         true <- is_map(Map.get(definition, "tools", %{})),
         {:ok, definition} <- json(definition) do
      {:ok, definition}
    else
      {:error, _reason} -> {:error, :invalid_data}
      _ -> {:error, :invalid_data}
    end
  end

  defp definition(_), do: {:error, :invalid_data}

  defp batch_calls(calls) when is_list(calls) and length(calls) in 1..8 do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, acc} ->
      case batch_call(call) do
        {:ok, call} -> {:cont, {:ok, [call | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} ->
        calls = Enum.reverse(acc)

        if length(Enum.uniq_by(calls, & &1.id)) == length(calls),
          do: {:ok, calls},
          else: {:error, :invalid_data}

      error ->
        error
    end
  end

  defp batch_calls(_), do: {:error, :invalid_data}

  # The Operation is the one the Runtime will dispatch, so its description digest
  # is the digest the executor verifies against its own journal.
  defp batch_call(%{id: id, operation: %Operation{} = operation}) do
    with {:ok, id} <- text(id, 128),
         :ok <- Operation.validate(operation) do
      {:ok, %{id: id, operation: operation}}
    end
  end

  defp batch_call(_), do: {:error, :invalid_data}

  defp consumptions(operations) when is_list(operations) and length(operations) in 1..128 do
    operations
    |> Enum.reduce_while({:ok, []}, &consumption_entry/2)
    |> reverse_ok()
  end

  defp consumptions(_), do: {:error, :invalid_data}

  defp consumption_entry(operation, {:ok, acc}) do
    with {:ok, _} <- fields(operation, [:operation_id], [:consumption_kind]),
         {:ok, id} <- uuid(operation[:operation_id]) do
      kind = Map.get(operation, :consumption_kind, "tool_result")

      if kind in @consumption_kinds and not Enum.any?(acc, &(&1.operation_id == id)),
        do: {:cont, {:ok, [%{operation_id: id, consumption_kind: kind} | acc]}},
        else: {:halt, {:error, :invalid_data}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp reverse_ok({:ok, acc}), do: {:ok, Enum.reverse(acc)}
  defp reverse_ok(error), do: error

  defp call_ids(calls) do
    ids = Enum.map(calls, & &1.id)
    {:ok, ids}
  end

  defp call_operation_id(_durable, _call_id), do: Ecto.UUID.generate()

  defp attempt(%Operation{} = operation, runtime) do
    %{
      attempt_id: Ecto.UUID.generate(),
      executor_id: runtime.executor_id,
      executor_boot_id: runtime.executor_boot_id,
      budget: %{"budget_ms" => operation.budget_ms}
    }
  end

  defp pending_entry(operation) do
    %{
      "operation_id" => operation.id,
      "tool_call_id" => operation.tool_call_id,
      "ordinal" => operation.ordinal,
      "name" => Map.get(operation.description["payload"], "profile")
    }
  end

  ## Small helpers

  defp command(scope_id, command_id, params) do
    %{scope_id: scope_id, command_id: command_id, params: params}
  end

  defp checkpoint(id, data, continuation, safe_to_fork) do
    %{id: id, data: data, continuation: continuation, safe_to_fork: safe_to_fork}
  end

  defp event(type, payload) do
    %{id: Ecto.UUID.generate(), type: type, payload: payload}
  end

  defp fa({:ok, value}), do: {:ok, value}
  defp fa({:error, reason}), do: {:error, normalize(reason)}

  defp normalize(reason) when is_atom(reason), do: reason
  defp normalize({:blocked, reason}), do: {:blocked, reason}
  defp normalize(_), do: :invalid_data

  defp safe_reason(reason) when is_atom(reason), do: {:ok, Atom.to_string(reason)}

  defp safe_reason(reason) when is_binary(reason) and byte_size(reason) in 1..128,
    do: {:ok, reason}

  defp safe_reason(_), do: {:error, :invalid_data}

  defp fields(attrs, required, optional) do
    Records.fields(attrs, required, optional)
  end

  defp uuid(value), do: Records.uuid(value)
  defp text(value, max), do: Records.text(value, max)
  defp count(value), do: Records.count(value)
  defp map(value) when is_map(value) and not is_struct(value), do: {:ok, value}
  defp map(_), do: {:error, :invalid_data}
  defp list(value) when is_list(value), do: {:ok, value}
  defp list(_), do: {:error, :invalid_data}

  defp json(value) do
    case Codec.encode(value, :checkpoint) do
      {:ok, _} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp digest(value) do
    case Codec.digest(value, :checkpoint) do
      {:ok, digest} -> {:ok, digest}
      {:error, _} -> {:error, :invalid_data}
    end
  end
end

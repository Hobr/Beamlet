defmodule Beamlet.Agent.Durable do
  @typedoc """
  已提交控制及可选执行接线；未开始 turn 或未接线时相关字段可为 nil。

  Committed control plus optional live dispatch wiring; freshly opened instances have nil generation/turn/runtime fields.
  """
  @type t :: %__MODULE__{
          repo: module(),
          authority_id: binary(),
          agent_id: binary(),
          definition: Beamlet.Agent.Core.Data.object() | nil,
          version: non_neg_integer() | nil,
          generation: non_neg_integer() | nil,
          turn_id: binary() | nil,
          step: non_neg_integer() | nil,
          runtime: runtime() | nil,
          control: Beamlet.Agent.Core.Reducer.state() | nil
        }
  @typedoc "同 authority Repo、独立 journal 及 executor/boot 身份，不携带凭证。"
  @type runtime :: %{
          authority_repo: module(),
          journal_repo: module(),
          executor_id: binary(),
          executor_boot_id: binary()
        }
  @typedoc "恢复后的暂停控制、实时 alias 与 Durable 接线，不含自动执行许可。"
  @type restored :: %{
          durable: t(),
          alias: binary() | nil,
          control: Beamlet.Agent.Core.Reducer.state()
        }
  @typedoc "暂停子实例定位与源截止位；risk 可为 unconfirmed，默认不授权后续执行。"
  @type forked :: %{
          agent_id: binary(),
          locator: Beamlet.Agent.locator(),
          version: non_neg_integer(),
          generation: non_neg_integer(),
          through_seq: pos_integer(),
          risk: binary() | nil,
          source: %{agent_id: binary(), through_seq: pos_integer()}
        }
  @typep object :: Beamlet.Agent.Core.Data.object()
  @typep result(value) :: Beamlet.Agent.result(value)
  @spec step(t()) :: non_neg_integer()
  @spec position(t()) :: %{
          agent_id: binary(),
          lock_version: non_neg_integer(),
          generation: non_neg_integer() | nil
        }
  @spec runtime(t()) :: {:ok, runtime()} | {:error, :missing_durable_runtime}
  @spec with_runtime(t(), map()) :: {:ok, t()} | {:error, :invalid_data}
  @spec persistence(t(), object()) :: result(Beamlet.Runtime.Persistence.t())
  @spec open(module(), %{
          required(:command_id) => binary(),
          required(:agent_id) => binary(),
          required(:authority_id) => binary(),
          required(:definition) => object(),
          optional(:alias) => binary()
        }) :: result(t())
  @spec inspect(Beamlet.Agent.locator(), keyword()) :: result(Beamlet.Agent.Loader.loaded())
  @spec accept_input(t(), %{command_id: binary(), turn_id: binary(), text: binary()}) ::
          result(t())
  @spec prepare(
          t(),
          [%{required(:operation) => Beamlet.Actions.Operation.t(), optional(:id) => binary()}],
          binary(),
          [Beamlet.Agent.Core.Data.value()],
          term()
        ) :: {:ok, t(), [object()]} | Beamlet.Agent.error()
  @spec consume(t(), [binary()], binary()) :: result(t())
  @spec accepted_refs(t(), [binary()]) :: result([object()])
  @spec consumption_kind(t(), object(), binary()) :: binary()
  @spec block(t(), atom() | binary()) :: result(t())
  @spec decide(t(), %{command_id: binary(), checkpoint_id: binary(), decision: term()}) ::
          result(t())
  @spec validate_decision(t(), term(), [binary()]) :: :ok | Beamlet.Agent.error()
  @spec validate_resolution(t(), term(), [binary()]) :: :ok | Beamlet.Agent.error()
  @spec resumable(t(), [binary()], term()) :: :ok | Beamlet.Agent.error()
  @spec resumable_result?(object(), object(), term()) :: boolean()
  @spec advance(t(), binary(), object(), binary() | nil) :: result(t())
  @spec execution_gate(t()) :: :ok | {:error, {:blocked, :environment_risk_unconfirmed}}
  @spec fork(Beamlet.Agent.locator(), term(), term(), term()) :: result(forked())
  @spec fork_source(term()) :: result(object())
  @spec fork_new(Beamlet.Agent.locator(), term(), term(), term(), object()) :: result(forked())
  @spec fork_response(Beamlet.Agent.locator(), object()) :: {:ok, forked()}
  @spec fork_id(term()) :: binary() | nil
  @spec fork_write(Beamlet.Agent.locator(), map()) :: result(object())
  @spec safe_fork(object()) :: :ok | {:error, :unsafe_position}
  @spec restore(term(), term(), term()) :: result(restored())
  @spec inactive(object()) :: :ok | {:error, :already_active}
  @spec activate(t(), non_neg_integer(), term()) :: result(t())
  @spec from_loaded(Beamlet.Agent.locator(), Beamlet.Agent.Loader.loaded()) :: t()
  @spec context(t(), Beamlet.Harness.Catalogue.t()) :: result(Beamlet.Agent.Core.Context.built())
  @spec committed(t(), object()) :: result(t())
  @spec preflight(t(), [{binary(), object(), binary() | nil}]) :: :ok | Beamlet.Agent.error()
  @spec preparation_events([%{operation: map()}]) :: [{binary(), object(), binary() | nil}]
  @spec write(t(), atom(), map()) :: result(object())
  @moduledoc """
  Agent 拥有的输入、准备与结果引用消费编排，使用 format3 authority。只把已提交事件归约到控制状态；未知写入按命令 ID 读取原响应，不重发写入或业务工作。恢复会提升 generation 并暂停，已声明发送而未解决的尝试不可再次发送。

  Agent-owned input and reference orchestration over Agent authority format 3.
  """
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

  @doc "读取当前归约控制的模型步骤。"
  def step(d), do: d.control["step"]
  @doc "返回 Agent/CAS version/generation 位置，供事务验证。"
  def position(d), do: %{agent_id: d.agent_id, lock_version: d.version, generation: d.generation}
  @doc "读取可选执行接线，缺失返回 missing_durable_runtime。"
  def runtime(%{runtime: nil}), do: {:error, :missing_durable_runtime}
  def runtime(d), do: {:ok, d.runtime}

  @doc "附加与当前 Repo 一致的运行时接线和有效 executor/boot UUID，不启动资源。"
  def with_runtime(d, runtime) when is_map(runtime) do
    if runtime[:authority_repo] == d.repo and runtime[:journal_repo] != nil and
         Codec.uuid?(runtime[:executor_id]) and Codec.uuid?(runtime[:executor_boot_id]),
       do: {:ok, %{d | runtime: runtime}},
       else: {:error, :invalid_data}
  end

  @doc "为既有 prepared 的 scope/epoch 构造 Runtime 接线，缺少 runtime 拒绝。"
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

  @doc "显式创建持久化 Agent 并归约返回的提交事件；definition 不应包含凭证。"
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

  @doc "只读固定高水位重建，无需模型绑定、provider 或 executor。"
  def inspect(locator, opts \\ []), do: Loader.load(locator.repo, locator.agent_id, opts)

  @doc "先校验风险、continuation 与事件语义，再以命令 ID 原子接受输入。"
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

  @doc "模型或工具批次原子准备，先 preflight 再提交；返回 durable 与有序 prepared，提交后才可执行。"
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

  @doc "按输入顺序读取完整已接受结果并提交消费引用与 join 位置，不触发执行。"
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

  @doc "取得有序接受摘要引用；不确定结果未明确解决时返回 unresolved_execution。"
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

  @doc "记录 turn.interrupted 并更新归约控制，不证明远端停止。"
  def block(d, reason) do
    advance(d, "turn.interrupted", %{"reason" => to_string(reason)})
  end

  @doc "验证风险或逐 Operation 决策后提交继续事实；claimed unresolved 不允许再次发送。"
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

  @doc """
  安全位置同 authority 引用分叉，command UUID 是稳定子 ID；注册源拒绝，默认环境风险未确认。

  Fork a safe committed sequence into paused, independent direct references.
  """
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

  @doc "验证历史、清退旧本地发送者，再激活新 generation 并暂停；不调用模型/工具。"
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

  @doc "按当前已提交控制与 catalogue 构造来源校验后的原生上下文。"
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

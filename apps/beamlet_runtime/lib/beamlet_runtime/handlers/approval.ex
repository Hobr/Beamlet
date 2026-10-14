defmodule BeamletRuntime.Handlers.Approval do
  @moduledoc """
  human.approval.v1 against the durable local Approval.Store resource.

  Input explicitly fixes service, subject and authorized responders. Approval and
  denial are normal Success. No callback/NotExecuted/cancel capability is claimed.
  Pending recovers by authenticated local queries to the configured resource Repo.
  Binding uses the original Intent context, not Execution/incarnation, as creation
  deduplication key. The guarantee requires permanent retention of the service DB.
  """
  @behaviour BeamletRuntime.Handler
  alias Beamlet.{Identity, Report, Value}
  alias Beamlet.Report.Source
  alias BeamletRuntime.Approval.Store

  @impl true
  def identity(_config), do: "beamlet.local-approval-handler.v1"
  @impl true
  def operations(_config), do: ["human.approval.v1"]

  @impl true
  def validate_input(definition, config) do
    with true <- definition.operation == "human.approval.v1" and definition.constraints == %{},
         :ok <- Store.validate_request(definition.input),
         true <- definition.input["service"] == config.service.identity do
      :ok
    else
      false -> {:error, :unsupported_approval_definition}
      error -> error
    end
  end

  @impl true
  def bind(intent, _execution, environment, config) do
    binding = binding_for(intent, config)
    with :ok <- validate_binding(intent, binding, environment, config), do: {:ok, binding}
  end

  @impl true
  def validate_binding(intent, binding, environment, config) do
    with :ok <- validate_input(intent.definition, config),
         true <-
           environment["approval_service"] == config.service.identity and
             binding === binding_for(intent, config) do
      :ok
    else
      false -> {:error, :approval_resource_mismatch}
      error -> error
    end
  end

  defp binding_for(intent, config) do
    %{
      "operation" => "human.approval.v1",
      "handler" => identity(config),
      "protocol" => "local-approval.v1",
      "resource" => %{"service" => config.service.identity, "instance" => config.service.instance},
      "completion" => %{
        "protocol" => "local-approval-query.v1",
        "collection" => intent.identity.collection,
        "approval_ref" => intent.id
      },
      "query" => %{
        "protocol" => "local-approval-query.v1",
        "service" => config.service.identity,
        "instance" => config.service.instance,
        "collection" => intent.identity.collection,
        "approval_ref" => intent.id
      },
      "idempotency" => %{
        "protocol" => "local-approval-create.v1",
        "key" => intent.id,
        "scope" => %{
          "service" => config.service.identity,
          "instance" => config.service.instance,
          "collection" => intent.identity.collection
        },
        "valid_through" => nil
      }
    }
  end

  @impl true
  def validate_result("human.approval.v1", :success, body, _config) when is_map(body) do
    valid =
      Enum.sort(Map.keys(body)) == ["approval_ref", "decision", "decision_ref"] and
        body["decision"] in ["approved", "denied"] and Identity.valid_text?(body["approval_ref"]) and
        Identity.valid_text?(body["decision_ref"])

    if valid, do: Value.validate(body), else: {:error, :invalid_approval_result}
  end

  def validate_result("human.approval.v1", :pending, %{"approval_ref" => ref} = body, _config)
      when map_size(body) == 1 do
    if Identity.valid_text?(ref), do: :ok, else: {:error, :invalid_approval_result}
  end

  def validate_result("human.approval.v1", :not_found, nil, _config), do: :ok
  def validate_result(_operation, _kind, _body, _config), do: {:error, :invalid_approval_result}

  @impl true
  def invoke(grant, config) do
    case create_bound(grant, config) do
      {:ok, %{decision: nil} = approval} -> {:pending, %{"approval_ref" => approval.approval_ref}}
      {:ok, approval} -> {:success, result(approval)}
      {:error, reason} -> {:uncertain, reason}
    end
  end

  defp create_bound(grant, config) do
    with :ok <- bound_service(grant.binding, config) do
      Store.create(
        config.service,
        grant.intent.identity.collection,
        grant.intent.id,
        grant.intent.definition.input
      )
    end
  end

  @impl true
  def query(intent, execution, config) do
    with :ok <- bound_service(execution.binding, config) do
      read_observation(intent, execution, config)
    end
  end

  defp bound_service(binding, config) do
    if binding["resource"] === %{
         "service" => config.service.identity,
         "instance" => config.service.instance
       }, do: :ok, else: {:error, :approval_service_mismatch}
  end

  defp read_observation(intent, execution, config) do
    case Store.read(config.service, intent.identity.collection, intent.id) do
      {:ok, %{request: request} = approval} when request === intent.definition.input ->
        observation(intent, execution, approval)

      {:ok, _changed} ->
        {:error, :approval_request_conflict}

      {:error, :approval_not_found} ->
        query_report(intent, execution, "missing", :not_found, nil)

      error ->
        error
    end
  end

  defp observation(intent, execution, %{decision: nil}),
    do: query_report(intent, execution, "awaiting", :not_found, nil)

  defp observation(intent, execution, approval),
    do: query_report(intent, execution, approval.decision_ref, :success, result(approval))

  defp result(approval),
    do: %{
      "decision" => approval.decision,
      "approval_ref" => approval.approval_ref,
      "decision_ref" => approval.decision_ref
    }

  defp query_report(intent, execution, id, kind, body) do
    source = %Source{
      kind: :query,
      collection: intent.identity.collection,
      intent_id: intent.id,
      execution_id: execution.id,
      binding: execution.binding["query"]
    }

    {:ok,
     %Report{
       id: id,
       source: source,
       operation: intent.definition.operation,
       kind: kind,
       body: body
     }}
  end
end

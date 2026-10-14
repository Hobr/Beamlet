defmodule BeamletRuntime.Handlers.FencedObject do
  @moduledoc """
  A distinct local object protocol with permanent per-Execution resource exclusion.
  No idempotency guarantee is advertised: safe replacement requires an actual proof.
  Invocations and fencing serialize in the resource database, outside Authority SQL.
  """
  @behaviour BeamletRuntime.Handler
  alias Beamlet.Exclusion
  alias Beamlet.Report
  alias Beamlet.Report.Source
  alias BeamletRuntime.Handlers.SharedObject
  alias BeamletRuntime.Object.Store

  @operation "object.fenced_replace_if_version.v1"
  @impl true
  def identity(_config), do: "beamlet.local-fenced-object-handler.v1"
  @impl true
  def operations(_config), do: [@operation]
  @impl true
  def validate_input(%{operation: @operation} = definition, config),
    do:
      SharedObject.validate_input(
        %{definition | operation: "object.replace_if_version.v1"},
        config
      )

  def validate_input(_definition, _config), do: {:error, :unsupported_object_definition}

  @impl true
  def bind(intent, _execution, environment, config) do
    binding = binding_for(intent, config)
    with :ok <- validate_binding(intent, binding, environment, config), do: {:ok, binding}
  end

  @impl true
  def validate_binding(intent, binding, environment, config) do
    with :ok <- original_binding(intent, binding, config),
         true <-
           environment["object_service"] == config.service.identity and
             environment["object_account"] == config.service.account do
      :ok
    else
      false -> {:error, :object_resource_mismatch}
      error -> error
    end
  end

  defp original_binding(intent, binding, config) do
    with :ok <- validate_input(intent.definition, config),
         true <- binding === binding_for(intent, config) do
      :ok
    else
      false -> {:error, :object_resource_mismatch}
      error -> error
    end
  end

  defp binding_for(intent, config) do
    resource = %{
      "service" => config.service.identity,
      "instance" => config.service.instance,
      "account" => config.service.account,
      "object" => intent.definition.input["object"]
    }

    query = %{
      "protocol" => "local-object-exclusion-query.v1",
      "resource" => resource,
      "collection" => intent.identity.collection,
      "intent_id" => intent.id,
      "operation" => @operation
    }

    %{
      "operation" => @operation,
      "handler" => identity(config),
      "protocol" => "local-object-fenced-cas.v1",
      "resource" => resource,
      "query" => query,
      "fencing" => %{"protocol" => "local-object-exclusion.v1", "resource" => resource}
    }
  end

  @impl true
  def validate_result(@operation, :not_executed, nil, _config), do: :ok

  def validate_result(@operation, kind, body, config),
    do: SharedObject.validate_result("object.replace_if_version.v1", kind, body, config)

  def validate_result(_operation, _kind, _body, _config), do: {:error, :invalid_object_result}

  @impl true
  def invoke(grant, config) do
    with :ok <- original_binding(grant.intent, grant.binding, config),
         {:ok, receipt} <-
           Store.invoke_fenced(config.service, grant.token, grant.intent.definition.input) do
      {:success, receipt.body}
    else
      {:error, reason} -> {:uncertain, reason}
    end
  end

  @impl true
  def query(intent, execution, config), do: observe(intent, execution, config, :query)
  @impl true
  def fence(intent, execution, config), do: observe(intent, execution, config, :fence)

  defp observe(intent, execution, config, kind) do
    with :ok <- original_binding(intent, execution.binding, config) do
      response =
        if kind == :fence,
          do: Store.fence(config.service, execution.authorization, intent.definition.input),
          else:
            Store.read_fenced_receipt(
              config.service,
              execution.authorization,
              intent.definition.input
            )

      report(intent, execution, response)
    end
  end

  defp report(intent, execution, response) do
    source = %Source{
      kind: :query,
      collection: intent.identity.collection,
      intent_id: intent.id,
      execution_id: execution.id,
      binding: execution.binding["query"]
    }

    base = %Report{
      id: "missing",
      source: source,
      operation: @operation,
      kind: :not_found,
      body: nil
    }

    case response do
      {:ok, %{kind: :success, receipt: receipt}} ->
        {:ok, %{base | id: receipt.body["receipt_ref"], kind: :success, body: receipt.body}}

      {:ok, %{kind: :not_executed} = proof} ->
        exclusion = %Exclusion{
          authorization: proof.authorization,
          query_binding: source.binding,
          evidence_ref: proof.evidence_ref
        }

        {:ok, %{base | id: proof.evidence_ref, kind: :not_executed, exclusion: exclusion}}

      {:error, :object_receipt_not_found} ->
        {:ok, base}

      error ->
        error
    end
  end
end

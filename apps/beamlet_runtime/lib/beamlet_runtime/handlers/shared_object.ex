defmodule BeamletRuntime.Handlers.SharedObject do
  @moduledoc """
  object.replace_if_version.v1 against a durable local CAS + receipt resource.
  Both applied and version_mismatch are Success. Query only trusts the original
  request receipt; current content/version or a missing receipt is not execution
  exclusion. No Pending/callback/cancel capability. Resource/account/instance,
  object and original Intent key are saved before invoke.
  """
  @behaviour BeamletRuntime.Handler
  alias Beamlet.{Identity, Report, Value}
  alias Beamlet.Report.Source
  alias BeamletRuntime.Object.Store

  @operation "object.replace_if_version.v1"
  @impl true
  def identity(_config), do: "beamlet.local-object-handler.v1"
  @impl true
  def operations(_config), do: [@operation]

  @impl true
  def validate_input(definition, config) do
    with true <- definition.operation == @operation and definition.constraints == %{},
         :ok <- Store.validate_request(definition.input),
         true <-
           definition.input["service"] == config.service.identity and
             definition.input["account"] == config.service.account do
      :ok
    else
      false -> {:error, :unsupported_object_definition}
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

  defp binding_for(intent, config) do
    resource = %{
      "service" => config.service.identity,
      "instance" => config.service.instance,
      "account" => config.service.account,
      "object" => intent.definition.input["object"]
    }

    query = %{
      "protocol" => "local-object-receipt.v1",
      "resource" => resource,
      "collection" => intent.identity.collection,
      "intent_id" => intent.id,
      "operation" => @operation
    }

    %{
      "operation" => @operation,
      "handler" => identity(config),
      "protocol" => "local-object-cas.v1",
      "resource" => resource,
      "query" => query,
      "idempotency" => %{
        "protocol" => "local-object-cas-receipt.v1",
        "key" => intent.id,
        "scope" =>
          Map.merge(resource, %{
            "collection" => intent.identity.collection,
            "operation" => @operation
          }),
        "valid_through" => nil
      }
    }
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

  @impl true
  def validate_result(@operation, :success, body, _config) when is_map(body) do
    applied = body["applied"]

    valid =
      result_shape?(applied, body) and
        Identity.valid_text?(body["object_ref"]) and Identity.valid_text?(body["receipt_ref"]) and
        is_integer(body["version"]) and body["version"] in 0..9_007_199_254_740_991

    if valid, do: Value.validate(body), else: {:error, :invalid_object_result}
  end

  def validate_result(@operation, :not_found, nil, _config), do: :ok
  def validate_result(_operation, _kind, _body, _config), do: {:error, :invalid_object_result}

  defp result_shape?(true, body),
    do: Enum.sort(Map.keys(body)) == ["applied", "object_ref", "receipt_ref", "version"]

  defp result_shape?(false, body),
    do:
      Enum.sort(Map.keys(body)) == ["applied", "object_ref", "reason", "receipt_ref", "version"] and
        body["reason"] == "version_mismatch"

  defp result_shape?(_applied, _body), do: false

  @impl true
  def invoke(grant, config) do
    with :ok <- original_binding(grant.intent, grant.binding, config),
         {:ok, receipt} <-
           Store.replace(
             config.service,
             grant.token.collection,
             grant.token.intent_id,
             grant.intent.definition.input
           ) do
      {:success, receipt.body}
    else
      {:error, reason} -> {:uncertain, reason}
    end
  end

  @impl true
  def query(intent, execution, config) do
    with :ok <- original_binding(intent, execution.binding, config) do
      case Store.read_receipt(
             config.service,
             intent.identity.collection,
             intent.id,
             intent.definition.input
           ) do
        {:ok, receipt} ->
          query_report(intent, execution, receipt.body["receipt_ref"], :success, receipt.body)

        {:error, :object_receipt_not_found} ->
          query_report(intent, execution, "missing", :not_found, nil)

        error ->
          error
      end
    end
  end

  defp query_report(intent, execution, id, kind, body) do
    source = %Source{
      kind: :query,
      collection: intent.identity.collection,
      intent_id: intent.id,
      execution_id: execution.id,
      binding: execution.binding["query"]
    }

    {:ok, %Report{id: id, source: source, operation: @operation, kind: kind, body: body}}
  end
end

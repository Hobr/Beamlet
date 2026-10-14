defmodule BeamletRuntime.Handlers.Echo do
  @moduledoc "Versioned synchronous example. Returns input unchanged; declares no external idempotency, Pending or query guarantee."
  @behaviour BeamletRuntime.Handler
  alias Beamlet.Value

  @impl true
  def identity(_config), do: "beamlet.echo-handler.v1"
  @impl true
  def operations(_config), do: ["beamlet.echo.v1"]
  @impl true
  def validate_input(definition, _config) do
    if definition.operation == "beamlet.echo.v1" and definition.constraints == %{},
      do: Value.validate(definition.input),
      else: {:error, :unsupported_echo_definition}
  end

  @impl true
  def bind(intent, _execution, environment, config) do
    binding = %{
      "operation" => intent.definition.operation,
      "handler" => identity(config),
      "protocol" => "beamlet.echo.v1",
      "resource" => %{"kind" => "local-pure", "name" => "echo"}
    }

    with :ok <- validate_binding(intent, binding, environment, config), do: {:ok, binding}
  end

  @impl true
  def validate_binding(intent, binding, environment, config) do
    if binding == %{
         "operation" => "beamlet.echo.v1",
         "handler" => identity(config),
         "protocol" => "beamlet.echo.v1",
         "resource" => %{"kind" => "local-pure", "name" => "echo"}
       } and
         environment["echo"] == true,
       do: validate_input(intent.definition, config),
       else: {:error, :resource_unavailable}
  end

  @impl true
  def validate_result("beamlet.echo.v1", :success, body, _config), do: Value.validate(body)
  def validate_result(_operation, _kind, _body, _config), do: {:error, :invalid_echo_result}
  @impl true
  def invoke(grant, _config), do: {:success, grant.intent.definition.input}
end

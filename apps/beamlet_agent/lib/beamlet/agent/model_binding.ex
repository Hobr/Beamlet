defmodule Beamlet.Agent.ModelBinding do
  @typedoc "Portable immutable provider configuration; adapter resolution belongs to the authority."
  @type t :: %{
          required(:provider) => binary(),
          required(:config) => Beamlet.Harness.Model.json_object(),
          optional(:credentials) => Beamlet.Harness.Model.json_object(),
          optional(:placement) => placement()
        }
  @type placement :: %{
          optional(:environment) => binary() | nil,
          optional(:allowed_nodes) => [node()] | nil,
          optional(:claims) => %{optional(binary()) => pos_integer()}
        }
  @spec registry() :: Beamlet.Harness.Model.registry()
  @spec portable?(term()) :: boolean()
  @spec valid?(term()) :: boolean()
  @spec invocation(map()) :: %{config: term(), credentials: term()}
  @spec validate(module(), term()) :: :ok | {:error, :invalid_invocation}
  @spec validate_adapter(module(), Beamlet.Harness.Model.invocation()) ::
          :ok | {:error, :invalid_invocation}
  @moduledoc "Validation of the immutable authority-owned model binding."
  alias Beamlet.Actions.Operation
  alias Beamlet.Harness.Model

  def registry do
    case Registry.meta(Beamlet.Agent.Registry, :model_providers) do
      {:ok, registry} -> registry
      _ -> Model.default_providers()
    end
  catch
    :exit, _ -> Model.default_providers()
  end

  # Delegation validates portable data here; only the creating authority resolves adapters.
  def portable?(binding) when is_map(binding) do
    with true <- Map.keys(binding) -- [:provider, :config, :credentials, :placement] == [],
         true <- Model.provider_id?(binding[:provider]),
         :ok <- Model.validate_invocation(invocation(binding)),
         placement <- Map.get(binding, :placement, %{}),
         true <-
           is_map(placement) and
             Map.keys(placement) -- [:environment, :allowed_nodes, :claims] == [],
         {:ok, _} <- Operation.new(Map.merge(%{kind: "agent.native"}, placement)) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  def portable?(_), do: false

  def valid?(binding) do
    with true <- portable?(binding),
         {:ok, module} <- Map.fetch(registry(), binding.provider),
         :ok <- validate_adapter(module, invocation(binding)) do
      true
    else
      _ -> false
    end
  end

  defp invocation(binding),
    do: %{config: binding[:config], credentials: Map.get(binding, :credentials, %{})}

  def validate(module, invocation) do
    with :ok <- Model.validate_invocation(invocation),
         :ok <- validate_adapter(module, invocation) do
      :ok
    else
      _ -> {:error, :invalid_invocation}
    end
  end

  defp validate_adapter(module, invocation) do
    case module.validate_invocation(invocation) do
      :ok -> :ok
      _ -> {:error, :invalid_invocation}
    end
  rescue
    _ -> {:error, :invalid_invocation}
  catch
    _, _ -> {:error, :invalid_invocation}
  end
end

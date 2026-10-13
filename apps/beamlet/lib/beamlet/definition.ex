defmodule Beamlet.Definition do
  @moduledoc """
  Immutable operation definition, including expanded initial policy defaults.

  Unknown fields and a missing input are rejected. Explicit nil is a valid input.
  Runtime attempts, Handler releases and scheduling state are not part of equality.
  """

  alias Beamlet.{Identity, Value}

  @enforce_keys [:operation, :input]
  defstruct [:operation, :input, constraints: %{}, policy: :stop_on_failure]

  @type t :: %__MODULE__{
          operation: String.t(),
          input: Value.t(),
          constraints: %{String.t() => Value.t()},
          policy: :stop_on_failure | :retry_once
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    cond do
      Map.keys(attrs) -- [:operation, :input, :constraints, :policy] != [] ->
        {:error, :unknown_definition_field}

      not Map.has_key?(attrs, :input) ->
        {:error, :missing_input}

      not Identity.valid_text?(Map.get(attrs, :operation)) ->
        {:error, :invalid_operation}

      Map.get(attrs, :policy, :stop_on_failure) not in [:stop_on_failure, :retry_once] ->
        {:error, :invalid_policy}

      not is_map(Map.get(attrs, :constraints, %{})) ->
        {:error, :invalid_constraints}

      true ->
        definition = struct!(__MODULE__, attrs)

        with :ok <- Value.validate(definition.input),
             :ok <- Value.validate(definition.constraints) do
          {:ok, definition}
        end
    end
  end

  def new(_attrs), do: {:error, :invalid_definition}

  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{} = left, %__MODULE__{} = right), do: left === right
end

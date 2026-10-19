defmodule Beamlet.Actions.Operation do
  @moduledoc "Bounded, non executable operation description. All labels are opaque."
  defstruct kind: nil,
            version: 1,
            payload: %{},
            credentials: %{},
            capabilities: [],
            environment: nil,
            allowed_nodes: nil,
            claims: %{},
            budget_ms: 60_000,
            metadata: %{}

  @typedoc "Validated description. Payload and placement labels are open bounded data; credentials are JSON."
  @type t :: %__MODULE__{
          kind: binary(),
          version: 1,
          payload: Beamlet.Actions.data(),
          credentials: Beamlet.Actions.json_object(),
          capabilities: [Beamlet.Actions.data()],
          environment: Beamlet.Actions.data(),
          allowed_nodes: [node()] | nil,
          claims: %{optional(binary()) => pos_integer()},
          budget_ms: pos_integer(),
          metadata: Beamlet.Actions.data()
        }

  @spec new(term()) :: {:ok, t()} | {:error, :invalid_operation}
  def new(attrs) do
    operation = struct!(__MODULE__, attrs)

    case validate(operation) do
      :ok -> {:ok, operation}
      error -> error
    end
  rescue
    _ -> {:error, :invalid_operation}
  end

  @spec validate(term()) :: :ok | {:error, :invalid_operation}
  def validate(%__MODULE__{} = op) do
    valid =
      header?(op) and placement?(op) and claims?(op.claims) and
        Beamlet.Actions.credentials?(op.credentials) and
        Beamlet.Actions.bounded?(Map.delete(Map.from_struct(op), :credentials), 262_144) and
        :erlang.external_size(op) <= 262_144

    if valid, do: :ok, else: {:error, :invalid_operation}
  rescue
    _ -> {:error, :invalid_operation}
  end

  def validate(_), do: {:error, :invalid_operation}

  @spec header?(%__MODULE__{}) :: boolean()
  defp header?(op) do
    is_binary(op.kind) and byte_size(op.kind) in 1..128 and op.version == 1 and
      is_integer(op.budget_ms) and op.budget_ms in 1..3_600_000
  end

  @spec placement?(%__MODULE__{}) :: boolean()
  defp placement?(op) do
    is_list(op.capabilities) and length(op.capabilities) <= 32 and nodes?(op.allowed_nodes)
  end

  @spec nodes?(term()) :: boolean()
  defp nodes?(nil), do: true
  defp nodes?(nodes), do: is_list(nodes) and length(nodes) <= 64 and Enum.all?(nodes, &is_atom/1)

  @spec claims?(term()) :: boolean()
  defp claims?(claims) do
    is_map(claims) and map_size(claims) <= 32 and
      Enum.all?(claims, fn {k, v} -> is_binary(k) and is_integer(v) and v > 0 end)
  end
end

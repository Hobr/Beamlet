defmodule Beamlet.Storage.JSON do
  @moduledoc false
  use Ecto.ParameterizedType
  alias Beamlet.Storage.Codec

  def init(opts), do: %{max_bytes: Keyword.fetch!(opts, :max_bytes)}
  def type(_), do: :string

  def max_bytes({:parameterized, {__MODULE__, %{max_bytes: max_bytes}}}), do: max_bytes
  def max_bytes(_), do: nil

  def cast(value, %{max_bytes: max_bytes}) do
    case Codec.encode(value, max_bytes) do
      {:ok, _} -> {:ok, value}
      _ -> :error
    end
  end

  def dump(nil, _, _), do: {:ok, nil}

  def dump(value, _, %{max_bytes: max_bytes}) do
    case Codec.encode(value, max_bytes) do
      {:ok, bytes} -> {:ok, bytes}
      _ -> :error
    end
  end

  def load(nil, _, _), do: {:ok, nil}

  def load(bytes, _, %{max_bytes: max_bytes}) do
    case Codec.decode(bytes, max_bytes) do
      {:ok, value} -> {:ok, value}
      _ -> :error
    end
  end
end

defmodule Beamlet.Storage.JSON do
  @moduledoc false
  use Ecto.ParameterizedType
  alias Beamlet.Storage.Codec

  def init(opts), do: %{kind: Keyword.get(opts, :kind, :event)}
  def type(_), do: :string

  def kind({:parameterized, {__MODULE__, %{kind: kind}}}), do: kind
  def kind(_), do: nil

  def cast(value, %{kind: kind}) do
    case Codec.encode(value, kind) do
      {:ok, _} -> {:ok, value}
      _ -> :error
    end
  end

  def dump(nil, _, _), do: {:ok, nil}

  def dump(value, _, %{kind: kind}) do
    case Codec.encode(value, kind) do
      {:ok, bytes} -> {:ok, bytes}
      _ -> :error
    end
  end

  def load(nil, _, _), do: {:ok, nil}

  def load(bytes, _, %{kind: kind}) do
    case Codec.decode(bytes, kind) do
      {:ok, value} -> {:ok, value}
      _ -> :error
    end
  end
end

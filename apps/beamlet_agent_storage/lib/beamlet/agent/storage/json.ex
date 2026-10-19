defmodule Beamlet.Agent.Storage.JSON do
  @moduledoc false
  # 严格 JSON 列边界：cast/dump/load 均复用领域预算；不能将损坏字节当普通字符串加载。
  @type params :: %{kind: atom()}
  @spec init(keyword()) :: params()
  @spec type(term()) :: :string
  @spec kind(term()) :: atom() | nil
  @spec cast(term(), params()) :: {:ok, Beamlet.Agent.Storage.Records.value()} | :error
  @spec dump(term(), term(), params()) :: {:ok, binary() | nil} | :error
  @spec load(term(), term(), params()) :: {:ok, Beamlet.Agent.Storage.Records.value()} | :error
  use Ecto.ParameterizedType
  alias Beamlet.Agent.Storage.Codec
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

defmodule Beamlet.Storage.JSON do
  @moduledoc false
  # 隐藏的 Ecto 参数化类型；schema 必须显式提供 max_bytes，cast/dump/load 均使用基础 Codec，损坏字节拒绝加载而非宽松解码。
  use Ecto.ParameterizedType
  alias Beamlet.Storage.Codec

  @typep params :: %{max_bytes: pos_integer()}
  @spec init(keyword()) :: params()
  def init(opts), do: %{max_bytes: Keyword.fetch!(opts, :max_bytes)}
  @spec type(term()) :: :string
  def type(_), do: :string

  @spec max_bytes(term()) :: pos_integer() | nil
  def max_bytes({:parameterized, {__MODULE__, %{max_bytes: max_bytes}}}), do: max_bytes
  def max_bytes(_), do: nil

  @spec cast(value, params()) :: {:ok, value} | :error when value: var
  def cast(value, %{max_bytes: max_bytes}) do
    case Codec.encode(value, max_bytes) do
      {:ok, _} -> {:ok, value}
      _ -> :error
    end
  end

  @spec dump(term(), term(), params()) :: {:ok, binary() | nil} | :error
  def dump(nil, _, _), do: {:ok, nil}

  def dump(value, _, %{max_bytes: max_bytes}) do
    case Codec.encode(value, max_bytes) do
      {:ok, bytes} -> {:ok, bytes}
      _ -> :error
    end
  end

  @spec load(term(), term(), params()) :: {:ok, Codec.value()} | :error
  def load(nil, _, _), do: {:ok, nil}

  def load(bytes, _, %{max_bytes: max_bytes}) do
    case Codec.decode(bytes, max_bytes) do
      {:ok, value} -> {:ok, value}
      _ -> :error
    end
  end
end

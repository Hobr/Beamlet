defmodule Beamlet.Agent.Ref do
  @typedoc """
  可读的实时 authority/ID/PID/incarnation 组合；不是持久化 locator。

  Live incarnation identity; fields are intentionally readable. It is not a durable locator.
  """
  @type t :: %__MODULE__{authority: node(), id: binary(), incarnation: reference(), pid: pid()}
  @moduledoc """
  包含 authority、ID、PID 和 incarnation 的实时身份。基础设施丢失后不重建；持久化读取使用 locator，重新连接必须显式发现当前实例。

  Ephemeral authority-local identity. Never reconstructed after infrastructure loss.
  """
  @enforce_keys [:authority, :id, :incarnation, :pid]
  defstruct @enforce_keys
end

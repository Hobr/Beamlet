defmodule Beamlet.Agent.Core.Decision do
  @moduledoc """
  纯继续/分叉分类，不派发、不持久化，也不证明外部执行已停止。宿主负责验证完整状态、处理不确定性和资源退役。

  Existing Agent continuation classifications, without dispatch or persistence.
  """

  @spec reply_position(term()) :: binary() | {:error, :invalid_reply}
  @spec resumable?(term()) :: boolean()
  @spec resume(position) ::
          :idle
          | :advance
          | :replay_reply
          | :pending
          | {:error, {:unsupported_continuation, position}}
        when position: var
  @spec safe_fork?(term()) :: boolean()

  @doc """
  仅按回复 kind 选择 completed 或 reply_recorded；不是完整回复校验。
  """
  def reply_position(%{kind: :text}), do: "completed"
  def reply_position(%{kind: :tool_calls}), do: "reply_recorded"
  def reply_position(_), do: {:error, :invalid_reply}

  @doc """
  判断位置是否属于已知可恢复分类；blocked 也在此集合中，但不表示 resume/1 可直接推进。
  """
  def resumable?(position),
    do:
      position in ~w(await_input completed blocked await_model_result reply_recorded model_prepared await_tool_results)

  @doc """
  把位置映射为 idle/advance/replay_reply/pending；blocked 或未知位置返回 unsupported_continuation，不能自动重执行 pending 工作。
  """
  def resume(position) when position in ~w(await_input completed), do: :idle
  def resume("await_model_result"), do: :advance
  def resume("reply_recorded"), do: :replay_reply
  def resume(position) when position in ~w(model_prepared await_tool_results), do: :pending
  def resume(position), do: {:error, {:unsupported_continuation, position}}

  @doc """
  检查无 pending、无 blocked 且位于允许的完整控制位置；不验证环境停止、来源闭包或存储归属。
  """
  def safe_fork?(control) when is_map(control),
    do:
      control["pending"] == [] and is_nil(control["blocked"]) and
        control["continuation"] in ~w(await_input await_model_result completed)

  def safe_fork?(_), do: false
end

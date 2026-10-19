defmodule Beamlet.Agent.Core.Decision do
  @moduledoc "Existing Agent continuation classifications, without dispatch or persistence."

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

  def reply_position(%{kind: :text}), do: "completed"
  def reply_position(%{kind: :tool_calls}), do: "reply_recorded"
  def reply_position(_), do: {:error, :invalid_reply}

  def resumable?(position),
    do:
      position in ~w(await_input completed blocked await_model_result reply_recorded model_prepared await_tool_results)

  def resume(position) when position in ~w(await_input completed), do: :idle
  def resume("await_model_result"), do: :advance
  def resume("reply_recorded"), do: :replay_reply
  def resume(position) when position in ~w(model_prepared await_tool_results), do: :pending
  def resume(position), do: {:error, {:unsupported_continuation, position}}

  def safe_fork?(control) when is_map(control),
    do:
      control["pending"] == [] and is_nil(control["blocked"]) and
        control["continuation"] in ~w(await_input await_model_result completed)

  def safe_fork?(_), do: false
end

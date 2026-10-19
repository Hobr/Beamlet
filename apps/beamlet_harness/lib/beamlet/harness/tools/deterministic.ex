defmodule Beamlet.Harness.Tools.Deterministic do
  @moduledoc """
  确定性 echo 工具，回传最多 1024 码点文本，并发出本地进度；settings 不参与结果。

  Deterministic native fixture Tool with local progress and cancellation hooks.
  """
  @behaviour Beamlet.Harness.Tool
  alias Beamlet.Harness.{Arguments, Context}
  @impl true
  @doc """
  返回静态数据描述；不访问本地设置、文件或认证。
  """
  @spec descriptor() :: Beamlet.Harness.Catalogue.descriptor()
  def descriptor do
    %{
      "name" => "echo",
      "description" => "Return bounded fixture text",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"text" => %{"type" => "string", "maxLength" => 1024}},
        "required" => ["text"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  @doc """
  校验参数和调用前取消状态后执行一次；使用可选本地 Context，不重试。
  """
  @spec invoke(term(), term(), Context.t()) ::
          {:ok, %{text: String.t()}} | {:error, :cancelled | :invalid_arguments}
  def invoke(arguments, _settings, context \\ %Context{}) do
    with false <- Context.cancelled?(context),
         :ok <- Arguments.validate(arguments, descriptor()["parameters"]) do
      Context.emit(context, %{phase: "echo"})
      {:ok, %{text: arguments["text"]}}
    else
      true -> {:error, :cancelled}
      error -> error
    end
  end
end

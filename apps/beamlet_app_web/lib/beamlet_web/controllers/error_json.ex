defmodule Beamlet.Web.ErrorJSON do
  @moduledoc """
  JSON 错误响应渲染器。只返回 errors.detail 状态文字，不序列化异常 assigns；这不定义业务 API 校验协议。

  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  @doc "根据模板名返回公开 HTTP 状态文字，忽略错误 assigns，不输出异常详情。"
  @spec render(binary(), map()) :: %{errors: %{detail: binary()}}
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

defmodule Beamlet.Web.ErrorHTML do
  @moduledoc """
  HTML 错误响应渲染器。忽略异常 assigns，仅由模板名返回 Phoenix 状态文字，避免暴露内部错误。

  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use Beamlet.Web, :html

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib//controllers/error_html/404.html.heex
  #   * lib//controllers/error_html/500.html.heex
  #
  # embed_templates "error_html/*"

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  @doc "根据模板名返回公开 HTTP 状态文字，忽略错误 assigns，不输出异常详情。"
  @spec render(binary(), map()) :: binary()
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule Beamlet.Web.PageController do
  @moduledoc "保留的脚手架首页控制器；当前根路由由 WorkbenchLive 处理，此控制器不承担 Agent 创建。"
  use Beamlet.Web, :controller

  @doc "呈现保留的 home 模板；根路由实际由 WorkbenchLive 使用。"
  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    render(conn, :home)
  end
end

defmodule Beamlet.Web do
  @moduledoc """
  Phoenix 接口的 use 宏入口。共享引用片段只设置 imports/uses/aliases；额外运行函数应放在独立模块，避免在每个调用模块中重复定义。

  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use Beamlet.Web, :controller
      use Beamlet.Web, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  @doc "返回允许从 priv/static 服务的路径名称。"
  @spec static_paths() :: [binary()]
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  @doc "生成路由模块所需 imports 与 Phoenix.Router 设置。"
  @spec router() :: Macro.t()
  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  @doc "生成 Phoenix.Channel 设置。"
  @spec channel() :: Macro.t()
  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  @doc "生成 HTML/JSON 控制器、Web 翻译与验证路由设置。"
  @spec controller() :: Macro.t()
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: Beamlet.Web.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @doc "生成 LiveView 与共享 HTML 辅助引用。"
  @spec live_view() :: Macro.t()
  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  @doc "生成 LiveComponent 与共享 HTML 辅助引用。"
  @spec live_component() :: Macro.t()
  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  @doc "生成 Phoenix.Component 与共享 HTML 辅助引用。"
  @spec html() :: Macro.t()
  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  @spec html_helpers() :: Macro.t()
  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: Beamlet.Web.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import Beamlet.Web.CoreComponents

      # Common modules used in templates
      alias Beamlet.Web.Layouts
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  @doc "生成绑定本 Endpoint/Router/静态路径的验证路由设置。"
  @spec verified_routes() :: Macro.t()
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: Beamlet.Web.Endpoint,
        router: Beamlet.Web.Router,
        statics: Beamlet.Web.static_paths()
    end
  end

  @doc """
  按受信 atom 选择对应接口的引用片段。

  When used, dispatch to the appropriate controller/view/etc.
  """
  @spec __using__(atom()) :: Macro.t()
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

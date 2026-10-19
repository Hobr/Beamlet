defmodule Beamlet.Web.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false
  # Host 与 Endpoint 分开监督；关闭后端角色仍可服务页面，更新配置只转交 Endpoint。

  use Application

  alias Beamlet.Web.Endpoint

  @impl true
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, _args) do
    children = [
      {Beamlet.Web.Host, Application.get_env(:beamlet_app_web, :host, [])},
      Beamlet.Web.Telemetry,
      {Phoenix.PubSub, name: Beamlet.Web.PubSub},
      Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Beamlet.Web.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  @spec config_change(keyword(), keyword(), [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end

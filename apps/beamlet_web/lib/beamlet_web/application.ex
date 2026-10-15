defmodule Beamlet.Web.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Beamlet.Web.Telemetry,
      {Phoenix.PubSub, name: Beamlet.Web.PubSub},
      Beamlet.Web.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Beamlet.Web.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Beamlet.Web.Endpoint.config_change(changed, removed)
    :ok
  end
end

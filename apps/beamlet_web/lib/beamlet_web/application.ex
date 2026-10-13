defmodule BeamletWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BeamletWeb.Telemetry,
      # Start a worker by calling: BeamletWeb.Worker.start_link(arg)
      # {BeamletWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      BeamletWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BeamletWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeamletWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

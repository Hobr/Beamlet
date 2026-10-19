defmodule Beamlet.Node.Routes do
  @moduledoc "Public portable routes and data-only catalogue, independent of executor settings."
  use GenServer

  @typep options :: [
           {:roles, [Beamlet.Node.role()]}
           | {:routes, %{optional(binary()) => Beamlet.Agent.Integration.Caller.profile()}}
           | {:catalogue, Beamlet.Harness.Catalogue.t()}
         ]
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  @spec init(options()) :: {:ok, options()}
  def init(opts), do: {:ok, opts}
  @impl true
  @spec handle_call({:profile, binary()} | :roles | :catalogue, GenServer.from(), options()) ::
          {:reply,
           {:ok,
            Beamlet.Agent.Integration.Caller.profile()
            | [Beamlet.Node.role()]
            | Beamlet.Harness.Catalogue.t()}
           | :error, options()}
  def handle_call({:profile, id}, _, opts), do: {:reply, Map.fetch(opts[:routes], id), opts}
  def handle_call(:roles, _, opts), do: {:reply, {:ok, opts[:roles]}, opts}
  def handle_call(:catalogue, _, opts), do: {:reply, {:ok, opts[:catalogue]}, opts}
end

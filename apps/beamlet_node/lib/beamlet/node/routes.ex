defmodule Beamlet.Node.Routes do
  @moduledoc "Public portable routes and data-only catalogue, independent of executor settings."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(opts), do: {:ok, opts}
  @impl true
  def handle_call({:profile, id}, _, opts), do: {:reply, Map.fetch(opts[:routes], id), opts}
  def handle_call(:roles, _, opts), do: {:reply, {:ok, opts[:roles]}, opts}
  def handle_call(:catalogue, _, opts), do: {:reply, {:ok, opts[:catalogue]}, opts}
end

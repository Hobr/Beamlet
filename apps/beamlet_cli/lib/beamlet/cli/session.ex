defmodule Beamlet.CLI.Session do
  @moduledoc "Single dispatcher with at most128 local aliases to immutable real Refs."
  alias Beamlet.Agent
  alias Beamlet.CLI.{Client, Command, Renderer}
  alias Beamlet.Node.{Agents, Cluster}
  defstruct aliases: %{}, allowed_nodes: [], discovery: nil

  @typedoc "Local aliases and one retained eventual discovery result."
  @type t :: %__MODULE__{
          aliases: %{optional(binary()) => Agent.Ref.t()},
          allowed_nodes: [binary()],
          discovery: Agents.result() | nil
        }
  @typep output :: (binary() -> term())
  @typep identity :: %{authority: node(), id: binary(), pid: pid(), incarnation: reference()}
  @spec new([binary()]) :: t()
  def new(allowed \\ []), do: %__MODULE__{allowed_nodes: allowed}

  @spec execute(t(), term(), output()) :: {:quit | :continue, t()}
  def execute(session, line, output \\ &Owl.IO.puts/1) do
    result = with {:ok, command} <- Command.parse(line), do: dispatch(session, command, output)

    case result do
      {:quit, state} ->
        {:quit, state}

      {state, response} when is_struct(state, __MODULE__) ->
        output.(Renderer.render(response))
        {:continue, state}

      error ->
        output.(Renderer.render(error))
        {:continue, session}
    end
  end

  @spec dispatch(t(), Command.t(), output()) :: {:quit, t()} | {t(), term()} | Agent.error()
  defp dispatch(s, {"help"}, _), do: {s, :help}
  defp dispatch(s, {"quit"}, _), do: {:quit, %{s | aliases: %{}}}
  defp dispatch(s, {"nodes"}, _), do: {s, Cluster.connected(s.allowed_nodes)}
  defp dispatch(s, {:connect, name}, _), do: {s, Cluster.connect(name, s.allowed_nodes)}

  defp dispatch(s, {:agents, name}, _) do
    result = with {:ok, nodes} <- targets(s, name), do: Agents.discover(nodes)

    case result do
      {:ok, snapshot} -> {%{s | discovery: snapshot}, {:ok, Map.put(snapshot, :page, 1)}}
      error -> {%{s | discovery: nil}, error}
    end
  end

  defp dispatch(%{discovery: nil} = s, {:agents_page, _}, _),
    do: {s, {:error, :invalid_command}}

  defp dispatch(s, {:agents_page, page}, _) do
    if page <= max(1, div(length(s.discovery.agents) + 7, 8)),
      do: {s, {:ok, Map.put(s.discovery, :page, page)}},
      else: {s, {:error, :invalid_command}}
  end

  defp dispatch(s, {:create, name, path}, _) do
    with {:ok, authority} <- Cluster.authority(name, s.allowed_nodes),
         {:ok, options} <- creation_options(path),
         alias_name = Keyword.get(options, :id),
         :ok <- available(s, alias_name),
         {:ok, ref} <- Client.create(authority, options) do
      {%{s | aliases: Map.put(s.aliases, alias_name, ref)}, {:ok, identity(ref)}}
    end
  end

  defp dispatch(s, {:attach, name, id, alias_name}, _) do
    with :ok <- available(s, alias_name),
         {:ok, authority} <- Cluster.authority(name, s.allowed_nodes),
         {:ok, ref} <- Agent.lookup(authority, id),
         {:ok, snapshot} <- Agent.snapshot(ref) do
      {%{s | aliases: Map.put(s.aliases, alias_name, ref)},
       {:ok, %{identity: identity(ref), snapshot: snapshot}}}
    end
  end

  defp dispatch(s, {"detach", name}, _) do
    with {:ok, _} <- fetch(s, name), do: {%{s | aliases: Map.delete(s.aliases, name)}, :ok}
  end

  defp dispatch(s, {"close", name}, _) do
    with {:ok, ref} <- fetch(s, name), :ok <- Client.close(ref) do
      {%{s | aliases: Map.reject(s.aliases, fn {_, r} -> r == ref end)}, :ok}
    end
  end

  defp dispatch(s, {command, name}, _) when command in ["status", "stop"] do
    with {:ok, ref} <- fetch(s, name) do
      {s, if(command == "status", do: Client.status(ref), else: Client.stop(ref))}
    end
  end

  defp dispatch(s, {:input, name, text}, _) do
    with {:ok, ref} <- fetch(s, name), do: {s, Client.input(ref, text)}
  end

  defp dispatch(s, {:watch, name, options}, output) do
    with {:ok, ref} <- fetch(s, name),
         do: {s, Client.watch(ref, Keyword.put(options, :output, output))}
  end

  @spec identity(Agent.Ref.t()) :: identity()
  defp identity(ref), do: Map.take(ref, [:authority, :id, :pid, :incarnation])
  @spec targets(t(), binary() | nil) :: {:ok, [node()]} | {:error, :invalid_authority}
  defp targets(s, nil), do: Cluster.connected(s.allowed_nodes)

  defp targets(s, name) do
    with {:ok, authority} <- Cluster.authority(name, s.allowed_nodes), do: {:ok, [authority]}
  end

  @spec fetch(t(), binary()) :: {:ok, Agent.Ref.t()} | {:error, :unknown_alias}
  defp fetch(s, name), do: Map.fetch(s.aliases, name) |> found()
  @spec found({:ok, Agent.Ref.t()} | :error) :: {:ok, Agent.Ref.t()} | {:error, :unknown_alias}
  defp found({:ok, ref}), do: {:ok, ref}
  defp found(:error), do: {:error, :unknown_alias}

  @spec available(t(), term()) :: :ok | {:error, :invalid_alias | :alias_exists | :alias_limit}
  defp available(s, name) do
    cond do
      not is_binary(name) -> {:error, :invalid_alias}
      not Regex.match?(~r/\A[a-zA-Z0-9_-]{1,128}\z/, name) -> {:error, :invalid_alias}
      Map.has_key?(s.aliases, name) -> {:error, :alias_exists}
      map_size(s.aliases) >= 128 -> {:error, :alias_limit}
      true -> :ok
    end
  end

  @spec creation_options(binary()) :: {:ok, keyword()} | {:error, :invalid_configuration}
  defp creation_options(path) do
    with true <- Path.type(path) == :absolute,
         [{:beamlet_cli, [agent_options: options]}] <- Config.Reader.read!(path),
         true <- is_list(options) and Keyword.keyword?(options) do
      {:ok, options}
    else
      _ -> {:error, :invalid_configuration}
    end
  rescue
    _ -> {:error, :invalid_configuration}
  catch
    _, _ -> {:error, :invalid_configuration}
  end
end

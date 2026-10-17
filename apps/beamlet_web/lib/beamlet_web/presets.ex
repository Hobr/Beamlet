defmodule Beamlet.Web.Presets do
  @moduledoc "Immutable trusted startup catalogue. Public descriptors never include resolved bindings."
  use GenServer
  alias Beamlet.Actions.Operation
  alias Beamlet.Agent.{Display, ModelBinding}
  alias Beamlet.Agent.Integration.Caller
  alias Beamlet.Harness.{Catalogue, Model}
  alias Beamlet.Node.Cluster

  def start_link(config), do: GenServer.start_link(__MODULE__, config, name: __MODULE__)
  @impl true
  def init(config), do: {:ok, config}
  def describe, do: GenServer.call(__MODULE__, :describe)
  def reset(id), do: GenServer.call(__MODULE__, {:reset, id})
  def resolve(draft), do: GenServer.call(__MODULE__, {:resolve, draft})

  def configuration(config, allowed, providers \\ Model.default_providers()) do
    with true <- plain?(config),
         true <-
           Map.keys(config) --
             [:presets, :models, :tools, :environments, :authorities, :default_authority] == [],
         config <-
           Map.merge(
             %{
               presets: %{},
               models: %{},
               tools: %{},
               environments: %{},
               authorities: %{},
               default_authority: nil
             },
             config
           ),
         true <- entries?(config.presets, 32, [:model, :tools, :environment]),
         true <- entries?(config.models, 32, [:binding]),
         true <- entries?(config.tools, 64, [:route, :descriptor, :environments]),
         true <- entries?(config.environments, 32, [:value]),
         true <- entries?(config.authorities, 32, [:target]),
         true <- Enum.all?(config.models, fn {_, m} -> model?(m.binding, providers) end),
         true <-
           Enum.all?(config.environments, fn {_, e} ->
             match?(
               {:ok, _},
               Operation.new(kind: "agent.native", environment: e.value)
             )
           end),
         true <-
           Enum.all?(config.authorities, fn {_, a} ->
             a.target == :local or match?({:ok, _}, Cluster.authority(a.target, allowed))
           end),
         true <-
           config.default_authority == nil or
             Map.has_key?(config.authorities, config.default_authority),
         true <- Enum.all?(config.tools, fn {_, t} -> tool?(t, config) end),
         true <-
           Enum.uniq(Enum.map(config.tools, fn {_, t} -> t.descriptor["name"] end)) ==
             Enum.map(config.tools, fn {_, t} -> t.descriptor["name"] end),
         true <- Enum.all?(config.presets, fn {id, _} -> match?({:ok, _}, reset(config, id)) end),
         true <-
           Enum.all?(config.presets, fn {id, _} ->
             {:ok, draft} = reset(config, id)

             match?(
               {:ok, _},
               resolve(
                 config,
                 Map.put(
                   draft,
                   "authority",
                   config.default_authority || List.first(Map.keys(config.authorities))
                 )
               )
             )
           end) do
      {:ok, config}
    else
      _ -> {:error, :invalid_web_catalogue}
    end
  rescue
    _ -> {:error, :invalid_web_catalogue}
  catch
    _, _ -> {:error, :invalid_web_catalogue}
  end

  defp model?(binding, providers) do
    ModelBinding.portable?(binding) and
      case Map.fetch(providers, binding.provider) do
        {:ok, module} ->
          ModelBinding.validate(module, %{
            config: binding.config,
            credentials: Map.get(binding, :credentials, %{})
          }) == :ok

        :error ->
          false
      end
  end

  defp tool?(t, c) do
    Caller.profile?(t.route) and
      Catalogue.validate(%{t.descriptor["name"] => t.descriptor}) == :ok and
      ids?(t.environments, 32) and Enum.all?(t.environments, &Map.has_key?(c.environments, &1)) and
      Enum.all?(t.environments, fn id ->
        Caller.profile?(Map.put(t.route, :environment, c.environments[id].value))
      end) and
      not Map.has_key?(t.route, :environment)
  end

  defp entries?(map, max, private) do
    plain?(map) and map_size(map) <= max and
      Enum.all?(map, fn {id, e} ->
        label?(id) and plain?(e) and Map.keys(e) -- ([:title, :description] ++ private) == [] and
          label?(e[:title]) and text?(Map.get(e, :description, ""), 2048)
      end)
  end

  defp plain?(v), do: is_map(v) and not is_struct(v)
  defp label?(v), do: text?(v, 128) and byte_size(v) > 0
  defp text?(v, max), do: is_binary(v) and byte_size(v) <= max and String.valid?(v)

  defp ids?(v, max),
    do: is_list(v) and length(v) <= max and Enum.all?(v, &label?/1) and Enum.uniq(v) == v

  def describe(c) do
    Map.new([:presets, :models, :tools, :environments, :authorities], fn kind ->
      {kind,
       Map.new(c[kind], fn {id, e} ->
         fields =
           case kind do
             :presets -> [:title, :description, :model, :tools, :environment]
             :tools -> [:title, :description, :environments]
             _ -> [:title, :description]
           end

         {id, Map.take(e, fields)}
       end)}
    end)
    |> Map.put(:default_authority, c.default_authority)
  end

  def reset(c, id) do
    with true <- label?(id),
         {:ok, p} <- Map.fetch(c.presets, id),
         true <- Map.keys(p) -- [:title, :description, :model, :tools, :environment] == [] do
      {:ok,
       %{
         "preset" => id,
         "model" => p.model,
         "tools" => p.tools,
         "environment" => Map.get(p, :environment),
         "authority" => c.default_authority,
         "title" => p.title,
         "task" => ""
       }}
    else
      _ -> {:error, :invalid_draft}
    end
  end

  def resolve(c, d) do
    with true <- plain?(d),
         true <- Map.keys(d) -- ~w(preset model tools environment authority title task) == [],
         true <- label?(d["preset"]) and Map.has_key?(c.presets, d["preset"]),
         true <- label?(d["model"]) and label?(d["authority"]),
         {:ok, model} <- Map.fetch(c.models, d["model"]),
         {:ok, authority} <- Map.fetch(c.authorities, d["authority"]),
         true <- ids?(d["tools"], 64),
         true <- label?(d["title"]) and text?(d["task"], 65_536),
         true <- Enum.all?(d["tools"], &Map.has_key?(c.tools, &1)),
         selected <- Enum.map(d["tools"], &c.tools[&1]),
         {:ok, environment} <- environment(c, d["environment"], selected),
         routes <- Map.new(selected, &{&1.descriptor["name"], route(&1, environment)}),
         catalogue <- Map.new(selected, &{&1.descriptor["name"], &1.descriptor}),
         true <- map_size(routes) == length(selected),
         :ok <- Catalogue.validate(catalogue),
         ids <- %{model: d["model"], tools: d["tools"]},
         ids <- if(d["environment"], do: Map.put(ids, :environment, d["environment"]), else: ids),
         metadata <- %{title: d["title"], preset_id: d["preset"], option_ids: ids},
         true <- Display.metadata?(metadata) do
      {:ok,
       %{
         authority: authority.target,
         task: d["task"],
         options: [
           model: model.binding,
           tools: routes,
           catalogue: catalogue,
           display_metadata: metadata
         ]
       }}
    else
      _ -> {:error, :invalid_draft}
    end
  rescue
    _ -> {:error, :invalid_draft}
  end

  defp route(%{route: route, environments: []}, _), do: route
  defp route(%{route: route}, env), do: Map.put(route, :environment, env)

  defp environment(c, id, selected) do
    needs = Enum.filter(selected, &(&1.environments != []))

    cond do
      id == nil and needs == [] ->
        {:ok, nil}

      label?(id) and Map.has_key?(c.environments, id) and
          Enum.all?(needs, &(id in &1.environments)) ->
        {:ok, c.environments[id].value}

      true ->
        {:error, :invalid_draft}
    end
  end

  @impl true
  def handle_call(:describe, _, c), do: {:reply, describe(c), c}
  def handle_call({:reset, id}, _, c), do: {:reply, reset(c, id), c}
  def handle_call({:resolve, draft}, _, c), do: {:reply, resolve(c, draft), c}
end

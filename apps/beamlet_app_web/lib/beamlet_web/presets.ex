defmodule Beamlet.Web.Presets do
  @moduledoc "Immutable trusted startup catalogue. Public descriptors never include resolved bindings."
  use GenServer
  alias Beamlet.Actions.Operation
  alias Beamlet.Agent.{Display, ModelBinding}
  alias Beamlet.Agent.Integration.Caller
  alias Beamlet.Harness.{Catalogue, Model}
  alias Beamlet.Node.Cluster

  @typedoc "Trusted private catalogue; environment values are opaque bounded placement data, validated by Operation."
  @type preset :: %{
          required(:title) => binary(),
          required(:model) => binary(),
          required(:tools) => [binary()],
          optional(:environment) => binary() | nil,
          optional(:description) => binary()
        }
  @type model :: %{
          required(:title) => binary(),
          required(:binding) => ModelBinding.t(),
          optional(:description) => binary()
        }
  @type tool :: %{
          required(:title) => binary(),
          required(:route) => Caller.profile(),
          required(:descriptor) => Catalogue.descriptor(),
          required(:environments) => [binary()],
          optional(:description) => binary()
        }
  @type environment :: %{
          required(:title) => binary(),
          required(:value) => term(),
          optional(:description) => binary()
        }
  @type authority :: %{
          required(:title) => binary(),
          required(:target) => :local | binary(),
          optional(:description) => binary()
        }
  @type entry :: preset() | model() | tool() | environment() | authority()
  @type configuration :: %{
          presets: %{optional(binary()) => preset()},
          models: %{optional(binary()) => model()},
          tools: %{optional(binary()) => tool()},
          environments: %{optional(binary()) => environment()},
          authorities: %{optional(binary()) => authority()},
          default_authority: binary() | nil
        }
  @typedoc "Public descriptors omit bindings, credentials, routes and resolved environment values."
  @type public_entry :: %{
          required(:title) => binary(),
          optional(:description) => binary(),
          optional(:model) => binary(),
          optional(:tools) => [binary()],
          optional(:environment) => binary() | nil,
          optional(:environments) => [binary()]
        }
  @type public_entries :: %{optional(binary()) => public_entry()}
  @type description :: %{
          presets: public_entries(),
          models: public_entries(),
          tools: public_entries(),
          environments: public_entries(),
          authorities: public_entries(),
          default_authority: binary() | nil
        }
  @typedoc "String-key draft; exact fields and selections are checked at runtime."
  @type draft :: %{optional(binary()) => binary() | [binary()] | nil}
  @type resolved :: %{
          authority: :local | binary(),
          task: binary(),
          options: [
            {:model, ModelBinding.t()}
            | {:tools, %{optional(binary()) => Caller.profile()}}
            | {:catalogue, Catalogue.t()}
            | {:display_metadata, Display.metadata()}
          ]
        }
  @typep resolution :: {:ok, resolved()} | {:error, :invalid_draft}
  @spec start_link(configuration()) :: GenServer.on_start()
  def start_link(config), do: GenServer.start_link(__MODULE__, config, name: __MODULE__)
  @impl true
  @spec init(configuration()) :: {:ok, configuration()}
  def init(config), do: {:ok, config}
  @spec describe() :: description()
  def describe, do: GenServer.call(__MODULE__, :describe)
  @spec reset(term()) :: {:ok, draft()} | {:error, :invalid_draft}
  def reset(id), do: GenServer.call(__MODULE__, {:reset, id})
  @spec resolve(term()) :: resolution()
  def resolve(draft), do: GenServer.call(__MODULE__, {:resolve, draft})

  @spec configuration(term(), term(), %{optional(binary()) => module()}) ::
          {:ok, configuration()} | {:error, :invalid_web_catalogue}
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

  @spec model?(term(), %{optional(binary()) => module()}) :: boolean()
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

  @spec tool?(tool(), configuration()) :: boolean()
  defp tool?(t, c) do
    Caller.profile?(t.route) and
      Catalogue.validate(%{t.descriptor["name"] => t.descriptor}) == :ok and
      ids?(t.environments, 32) and Enum.all?(t.environments, &Map.has_key?(c.environments, &1)) and
      Enum.all?(t.environments, fn id ->
        Caller.profile?(Map.put(t.route, :environment, c.environments[id].value))
      end) and
      not Map.has_key?(t.route, :environment)
  end

  @spec entries?(term(), non_neg_integer(), [atom()]) :: boolean()
  defp entries?(map, max, private) do
    plain?(map) and map_size(map) <= max and
      Enum.all?(map, fn {id, e} ->
        label?(id) and plain?(e) and Map.keys(e) -- ([:title, :description] ++ private) == [] and
          label?(e[:title]) and text?(Map.get(e, :description, ""), 2048)
      end)
  end

  @spec plain?(term()) :: boolean()
  defp plain?(v), do: is_map(v) and not is_struct(v)
  @spec label?(term()) :: boolean()
  defp label?(v), do: text?(v, 128) and byte_size(v) > 0
  @spec text?(term(), non_neg_integer()) :: boolean()
  defp text?(v, max), do: is_binary(v) and byte_size(v) <= max and String.valid?(v)

  @spec ids?(term(), non_neg_integer()) :: boolean()
  defp ids?(v, max),
    do: is_list(v) and length(v) <= max and Enum.all?(v, &label?/1) and Enum.uniq(v) == v

  @spec describe(configuration()) :: description()
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

  @spec reset(configuration(), term()) :: {:ok, draft()} | {:error, :invalid_draft}
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

  @spec resolve(configuration(), term()) :: resolution()
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

  @spec route(tool(), term()) :: Caller.profile()
  defp route(%{route: route, environments: []}, _), do: route
  defp route(%{route: route}, env), do: Map.put(route, :environment, env)

  @spec environment(configuration(), term(), [tool()]) ::
          {:ok, term()} | {:error, :invalid_draft}
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
  @spec handle_call(
          :describe | {:reset, term()} | {:resolve, term()},
          GenServer.from(),
          configuration()
        ) ::
          {:reply, description() | {:ok, draft() | resolved()} | {:error, :invalid_draft},
           configuration()}
  def handle_call(:describe, _, c), do: {:reply, describe(c), c}
  def handle_call({:reset, id}, _, c), do: {:reply, reset(c, id), c}
  def handle_call({:resolve, draft}, _, c), do: {:reply, resolve(c, draft), c}
end

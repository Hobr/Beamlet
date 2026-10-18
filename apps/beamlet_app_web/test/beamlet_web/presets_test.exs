defmodule Beamlet.Web.PresetsTest do
  use ExUnit.Case, async: true
  alias Beamlet.Web.Presets

  def catalogue do
    Config.Reader.read!(Path.expand("../../priv/examples/host.exs", __DIR__))[:beamlet_app_web][
      :host
    ][
      :catalogue
    ]
  end

  test "explicit example validates and reset/resolve preserve immutable source" do
    source = catalogue()
    assert {:ok, c} = Presets.configuration(source, [])
    assert {:ok, d} = Presets.reset(c, "basic")
    assert {:ok, r} = Presets.resolve(c, %{d | "task" => "hello", "title" => "Edited"})
    assert r.options[:tools] == %{}
    assert r.options[:catalogue] == %{}
    assert r.options[:model] == source.models["local"].binding
    assert r.options[:display_metadata].title == "Edited"
    assert {:ok, ^d} = Presets.reset(c, "basic")
    assert catalogue() == source
    refute inspect(Presets.describe(c)) =~ "binding"
  end

  test "strict browser envelope rejects unknown fields, types, duplicates and UTF-8/byte overflow" do
    {:ok, c} = Presets.configuration(catalogue(), [])
    {:ok, d} = Presets.reset(c, "basic")

    for bad <- [
          Map.put(d, "binding", %{}),
          Map.put(d, "node", node()),
          %{d | "tools" => ["x", "x"]},
          %{d | "tools" => ["x" | :bad]},
          %{d | "model" => :local},
          %{d | "authority" => "forged"},
          %{d | "task" => String.duplicate("x", 65_537)},
          %{d | "title" => String.duplicate("é", 65)},
          %{d | "title" => <<255>>},
          %{d | "environment" => "root"},
          %{d | "preset" => "missing"},
          nil
        ] do
      assert {:error, :invalid_draft} = Presets.resolve(c, bad)
    end

    assert {:ok, _} =
             Presets.resolve(c, %{
               d
               | "title" => String.duplicate("é", 64),
                 "task" => String.duplicate("x", 65_536)
             })
  end

  test "startup bounds, references and static errors do not expose secrets" do
    c = catalogue()

    for bad <- [
          %{c | models: Map.new(1..33, &{to_string(&1), c.models["local"]})},
          Map.put(c, :private, "SECRET/root"),
          put_in(c, [:models, "local", :binding, :config], %{"key_env" => "SECRET"}),
          put_in(c, [:presets, "basic", :model], "unknown"),
          put_in(c, [:models, "local", :title], <<255>>),
          put_in(c, [:models, "local", :description], String.duplicate("x", 2049))
        ] do
      assert {:error, :invalid_web_catalogue} = Presets.configuration(bad, [])
    end
  end

  test "tool catalogue matches routes exactly and requires only compatible selected environments" do
    c = catalogue()

    descriptor = %{
      "name" => "read",
      "description" => "Read",
      "parameters" => %{"type" => "object", "properties" => %{}}
    }

    c =
      Map.merge(c, %{
        tools: %{
          "read" => %{
            title: "Read",
            route: %{id: "reader", capability: "read"},
            descriptor: descriptor,
            environments: ["safe"]
          }
        },
        environments: %{"safe" => %{title: "Safe", value: "workspace"}}
      })

    {:ok, c} = Presets.configuration(c, [])
    {:ok, d} = Presets.reset(c, "basic")
    assert {:error, :invalid_draft} = Presets.resolve(c, %{d | "tools" => ["read"]})
    assert {:ok, r} = Presets.resolve(c, %{d | "tools" => ["read"], "environment" => "safe"})
    assert Map.keys(r.options[:tools]) == Map.keys(r.options[:catalogue])
    assert r.options[:tools]["read"].environment == "workspace"
    assert {:ok, r} = Presets.resolve(c, d)
    assert r.options[:tools] == %{}
  end

  test "all catalogue count caps and serialized metadata guard are enforced" do
    source = catalogue()
    {:ok, c} = Presets.configuration(source, [])

    for {kind, max, entry} <- [
          {:models, 32, c.models["local"]},
          {:presets, 32, c.presets["basic"]},
          {:environments, 32, %{title: "Safe", value: "workspace"}},
          {:tools, 64,
           %{
             title: "Tool",
             route: %{id: "tool", capability: "tool"},
             environments: [],
             descriptor: %{}
           }}
        ] do
      oversized = Map.put(source, kind, Map.new(1..(max + 1), &{to_string(&1), entry}))
      assert {:error, :invalid_web_catalogue} = Presets.configuration(oversized, [])
    end

    tools =
      Map.new(1..64, fn i ->
        id = String.pad_leading(to_string(i), 128, "x")
        name = "tool#{i}"

        {id,
         %{
           title: "Tool",
           route: %{id: name, capability: "tool"},
           environments: [],
           descriptor: %{
             "name" => name,
             "description" => "Tool",
             "parameters" => %{"type" => "object", "properties" => %{}}
           }
         }}
      end)

    assert {:ok, c} = Presets.configuration(Map.put(source, :tools, tools), [])
    {:ok, d} = Presets.reset(c, "basic")
    assert {:error, :invalid_draft} = Presets.resolve(c, %{d | "tools" => Map.keys(tools)})
    assert {:ok, _} = Presets.resolve(c, %{d | "tools" => Enum.take(Map.keys(tools), 10)})
  end

  test "private explicit credentials never enter public descriptors or reset draft" do
    source = catalogue()

    binding = %{
      provider: "openai-compatible",
      config: %{"base_url" => "https://example.invalid/v1", "model" => "example"},
      credentials: %{"api_key" => "PRIVATE_SECRET_SENTINEL"}
    }

    assert {:ok, c} =
             Presets.configuration(put_in(source, [:models, "local", :binding], binding), [])

    {:ok, d} = Presets.reset(c, "basic")
    public = inspect({Presets.describe(c), d})
    refute public =~ "PRIVATE_SECRET_SENTINEL"
    refute public =~ "base_url"
    refute public =~ "credentials"
    assert {:ok, resolved} = Presets.resolve(c, d)
    assert resolved.options[:model] == binding
    # Missing default remains an explicit choice in the draft, never a fallback.
    assert {:ok, missing} = Presets.configuration(%{source | default_authority: nil}, [])
    {:ok, draft} = Presets.reset(missing, "basic")
    assert draft["authority"] == nil
    assert {:error, :invalid_draft} = Presets.resolve(missing, draft)
  end

  test "resolver accepts exactly 4096 serialized metadata bytes and rejects one extra" do
    source = catalogue()
    {:ok, c} = Presets.configuration(source, [])
    {:ok, d} = Presets.reset(c, "basic")
    ids = Enum.map(1..32, &String.pad_trailing("id#{&1}-", 100, "x"))
    metadata = %{title: d["title"], preset_id: "basic", option_ids: %{model: "local", tools: ids}}
    remaining = 4096 - :erlang.external_size(metadata)
    assert remaining > 0 and remaining < 32 * 28

    {ids, 0} =
      Enum.map_reduce(ids, remaining, fn id, left ->
        extra = min(left, 28)
        {id <> String.duplicate("x", extra), left - extra}
      end)

    c = with_tools(source, ids)
    assert {:ok, r} = Presets.resolve(c, %{d | "tools" => ids})
    assert :erlang.external_size(r.options[:display_metadata]) == 4096
    oversized = List.update_at(ids, -1, &(&1 <> "x"))
    c = with_tools(source, oversized)
    assert {:error, :invalid_draft} = Presets.resolve(c, %{d | "tools" => oversized})
  end

  defp with_tools(source, ids) do
    tools =
      ids
      |> Enum.with_index()
      |> Map.new(fn {id, i} ->
        name = "t#{i}"

        {id,
         %{
           title: "Tool",
           route: %{id: name, capability: "tool"},
           environments: [],
           descriptor: %{
             "name" => name,
             "description" => "Tool",
             "parameters" => %{"type" => "object", "properties" => %{}}
           }
         }}
      end)

    assert {:ok, c} = Presets.configuration(Map.put(source, :tools, tools), [])
    c
  end
end

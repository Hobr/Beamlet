defmodule Beamlet.Agent.CoreAdapterTest do
  use ExUnit.Case, async: true
  alias Beamlet.Agent.Core.Data
  alias Beamlet.Agent.Core.Reducer, as: Core
  alias Beamlet.Agent.Reducer
  alias Beamlet.Agent.Storage.Codec

  test "normalized UUID spelling matches the unchanged storage authority" do
    id = Ecto.UUID.generate()

    for value <- [
          id,
          String.upcase(id),
          String.replace(id, "-", ""),
          "",
          nil,
          12,
          <<0::128>>,
          "00000000-0000-0000-0000-000000000000",
          "ffffffff-ffff-ffff-ffff-ffffffffffff",
          "g2345678-1234-1234-1234-123456789abc"
        ] do
      assert Data.uuid?(value) == Codec.uuid?(value)
    end
  end

  test "storage normalization preserves canonical digests and pure replay projection" do
    id = Ecto.UUID.generate()

    created = %{
      "id" => Ecto.UUID.generate(),
      "scope_id" => id,
      "schema_version" => 1,
      "seq" => 1,
      "type" => "agent.created",
      "payload" => %{"definition_version" => 1}
    }

    input =
      %{
        created
        | "id" => Ecto.UUID.generate(),
          "seq" => 2,
          "type" => "input.accepted",
          "payload" => %{"text" => "中文"}
      }
      |> Map.put("turn_id", Ecto.UUID.generate())

    {:ok, digest} = Codec.digest(input["payload"], :event)
    assert {:ok, projected} = Reducer.replay(Reducer.new(id), [created, input])

    assert {:ok, ^projected} =
             Core.replay(Core.new(id), [created, Map.put(input, "input_digest", digest)])

    assert [source] = projected["inputs"]
    assert source["digest"] == digest
    refute Map.has_key?(projected, "input_digest")
    assert {:error, :invalid_history} = Reducer.decode(Map.put(input, "payload", []))
  end

  test "payload depth is independent of envelope and replay wrappers" do
    id = Ecto.UUID.generate()

    created = %{
      "id" => id,
      "scope_id" => id,
      "seq" => 1,
      "schema_version" => 1,
      "type" => "agent.created",
      "payload" => %{"definition_version" => 1}
    }

    for depth <- [31, 32, 33], mod <- [Core, Reducer] do
      payload = Enum.reduce(1..depth, 0, fn _, child -> %{"x" => child} end)
      selected = %{created | "seq" => 2, "type" => "context.selected", "payload" => payload}

      if depth <= 32 do
        assert {:ok, _} = Codec.encode(payload, :event)
        assert :ok = mod.decode(selected)
        assert {:ok, next} = mod.reduce(%{mod.new(id) | "through_seq" => 1}, selected)
        assert {:ok, ^next} = mod.replay(mod.new(id), [created, selected])
      else
        assert {:error, _} = Codec.encode(payload, :event)
        assert {:error, _} = mod.decode(selected)
        assert {:error, _} = mod.reduce(%{mod.new(id) | "through_seq" => 1}, selected)
        assert {:error, _} = mod.replay(mod.new(id), [created, selected])
      end
    end
  end
end

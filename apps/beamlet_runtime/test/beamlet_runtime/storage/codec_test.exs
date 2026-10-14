defmodule BeamletRuntime.Storage.CodecTest do
  use ExUnit.Case, async: true
  alias Beamlet.{Definition, Token}
  alias BeamletRuntime.Storage.Codec

  test "logical keys resembling codec tags remain ordinary user data" do
    input = %{
      "$atom" => "closed",
      "$struct" => "Elixir.Unknown",
      "$tuple" => [1, nil],
      "$map" => [["key", true]],
      "text" => "中文🙂"
    }

    {:ok, definition} = Definition.new(%{operation: "request.v1", input: input})
    assert {:ok, ^definition} = definition |> Codec.encode() |> Codec.decode()
  end

  test "64-bit generation and tuple identity round-trip without floating point loss" do
    token = %Token{
      collection: "collection",
      intent_id: "intent",
      execution_id: "execution",
      worker: "worker",
      incarnation: "session",
      generation: 9_223_372_036_854_775_807
    }

    identity = {token, "report"}
    assert {:ok, ^identity} = identity |> Codec.encode() |> Codec.decode()
  end

  test "legacy Definitions import strict repeat denial; v3 requires explicit valid acceptance" do
    {:ok, definition} = Definition.new(%{operation: "op", input: nil, policy: :retry_once})
    encoded = Jason.decode!(Codec.encode(definition))
    fields = encoded["value"]["fields"]["$map"]
    legacy = Enum.reject(fields, fn [key, _] -> key == %{"$atom" => "repeat_accepted"} end)
    missing = put_in(encoded, ["value", "fields", "$map"], legacy)

    for version <- [1, 2] do
      assert {:ok, ^definition} =
               Codec.decode(Jason.encode!(Map.put(missing, "version", version)))
    end

    assert {:error, :corrupt_storage_value} = Codec.decode(Jason.encode!(missing))

    altered =
      Enum.map(fields, fn
        [%{"$atom" => "repeat_accepted"} = key, _] -> [key, "yes"]
        pair -> pair
      end)

    assert {:error, :corrupt_storage_value} =
             Codec.decode(Jason.encode!(put_in(encoded, ["value", "fields", "$map"], altered)))
  end

  test "unknown versions, arbitrary modules and unknown atoms cannot be loaded" do
    assert {:error, :unsupported_storage_format} = Codec.decode(~s({"version":99,"value":null}))

    assert {:error, :corrupt_storage_value} =
             Codec.decode(~s({"version":1,"value":{"$atom":"unregistered_storage_atom"}}))

    assert {:error, :corrupt_storage_value} =
             Codec.decode(~s({"version":1,"value":{"$struct":"Elixir.Unregistered","fields":{}}}))

    assert {:error, :corrupt_storage_value} =
             Codec.decode(~s({"version":1,"value":{"$map":[["key",1],["key",2]]}}))
  end
end

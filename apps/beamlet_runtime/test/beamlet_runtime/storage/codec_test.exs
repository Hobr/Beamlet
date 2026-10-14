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

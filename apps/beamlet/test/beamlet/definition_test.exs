defmodule Beamlet.DefinitionTest do
  use ExUnit.Case, async: true

  alias Beamlet.{Definition, Identity, Lease}

  test "initial defaults are expanded before definition comparison" do
    assert {:ok, implicit} = Definition.new(%{operation: "api.request.v1", input: nil})

    assert {:ok, explicit} =
             Definition.new(%{
               operation: "api.request.v1",
               input: nil,
               constraints: %{},
               policy: :stop_on_failure
             })

    assert Definition.equal?(implicit, explicit)
    assert implicit.input == nil
    assert implicit.policy == :stop_on_failure
    assert {:error, :missing_input} = Definition.new(%{operation: "api.request.v1"})
  end

  test "unknown fields, unsupported policy and invalid persistent values are rejected" do
    attrs = %{operation: "api.request.v1", input: %{"prompt" => "hello"}}
    assert {:error, :unknown_definition_field} = Definition.new(Map.put(attrs, :worker, "node-a"))
    assert {:error, :invalid_policy} = Definition.new(Map.put(attrs, :policy, :retry_forever))
    assert {:error, :invalid_type} = Definition.new(Map.put(attrs, :input, fn -> :ok end))
    assert {:error, :invalid_constraints} = Definition.new(Map.put(attrs, :constraints, []))
    assert {:error, :invalid_operation} = Definition.new(%{attrs | operation: ""})
    assert {:error, :invalid_definition} = Definition.new([])
  end

  test "operation, constraints, input and initial policy are immutable identity material" do
    attrs = %{operation: "api.request.v1", input: %{"prompt" => "hello"}}
    {:ok, original} = Definition.new(attrs)

    for changed <- [
          %{attrs | operation: "api.request.v2"},
          %{attrs | input: %{"prompt" => "other"}},
          Map.put(attrs, :constraints, %{"device" => "other"}),
          Map.put(attrs, :policy, :retry_once)
        ] do
      {:ok, definition} = Definition.new(changed)
      refute Definition.equal?(original, definition)
    end
  end

  test "submission identities distinguish missing keys, scopes and exact UTF-8 text" do
    assert {:ok, %Identity{key: nil}} = Identity.new("collection", "namespace")
    assert {:error, :invalid_identity} = Identity.new("collection", "namespace", "")

    assert {:error, :invalid_identity} =
             Identity.new("collection", "namespace", String.duplicate("x", 257))

    assert {:error, :invalid_identity} = Identity.new("collection", "namespace", <<255>>)
    assert {:ok, _} = Identity.new("collection", "namespace", String.duplicate("é", 128))

    assert Identity.new("collection", "namespace", "é") !=
             Identity.new("collection", "namespace", "e\u0301")

    assert Identity.new("a", "namespace", "key") != Identity.new("b", "namespace", "key")
    assert Identity.new("a", "one", "key") != Identity.new("a", "two", "key")
  end

  test "lease counters and expiration never overflow or wrap" do
    max = 9_223_372_036_854_775_807
    assert Lease.next_generation(max - 1) == {:ok, max}
    assert Lease.next_generation(max) == {:error, :generation_exhausted}
    assert Lease.expiry(max - 1, 1) == {:ok, max}
    assert Lease.expiry(max, 1) == {:error, :invalid_ttl}
    assert Lease.expiry(0, 0) == {:error, :invalid_ttl}
    assert Lease.expiry(0, -1) == {:error, :invalid_ttl}
    assert Lease.expiry(0, 1.0) == {:error, :invalid_ttl}
  end
end

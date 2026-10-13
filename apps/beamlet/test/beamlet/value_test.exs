defmodule Beamlet.ValueTest do
  use ExUnit.Case, async: true

  alias Beamlet.Value

  test "canonical v1 preserves types, sorts keys and uses specified escapes" do
    value = %{"z" => [nil, true, false, -12], "é" => "/雪", "a" => "\"\\\n\t\r"}

    assert {:ok, encoded} = Value.canonical(value)
    assert encoded == ~S({"a":"\"\\\u000a\u0009\u000d","z":[null,true,false,-12],"é":"/雪"})
    assert :json.decode(encoded) === %{value | "z" => [:null, true, false, -12]}
  end

  test "all control characters use lowercase four-digit Unicode escapes" do
    for n <- 0..31 do
      hex = n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
      assert Value.canonical(<<n>>) == {:ok, "\"\\u" <> hex <> "\""}
    end
  end

  test "safe integer endpoints are exact and larger integers or floats are rejected" do
    for n <- [-9_007_199_254_740_991, 0, 9_007_199_254_740_991] do
      assert Value.canonical(n) == {:ok, Integer.to_string(n)}
    end

    assert Value.validate(9_007_199_254_740_992) == {:error, :integer_out_of_range}
    assert Value.validate(-9_007_199_254_740_992) == {:error, :integer_out_of_range}
    assert Value.validate(1.0) == {:error, :invalid_type}
  end

  test "runtime objects, structs, atom keys and improper lists are rejected" do
    for value <- [self(), make_ref(), fn -> :ok end, :atom, {1, 2}, %URI{}, [1 | 2]] do
      assert Value.validate(value) == {:error, :invalid_type}
    end

    assert Value.validate(%{key: "value"}) == {:error, :invalid_object_key}
    assert Value.validate(%{"valid" => [%{"nested" => self()}]}) == {:error, :invalid_type}
  end

  test "invalid Unicode including encoded surrogate code points is rejected" do
    for value <- [<<255>>, <<0xED, 0xA0, 0x80>>, <<0xC0, 0x80>>] do
      assert Value.validate(value) == {:error, :invalid_utf8}
      assert Value.validate(%{value => 1}) == {:error, :invalid_utf8}
    end
  end

  test "equality preserves missing/null, type, array order and Unicode distinctions" do
    assert Value.equal?(%{"a" => 1, "b" => nil}, Map.new([{"b", nil}, {"a", 1}]))
    refute Value.equal?(%{"a" => 1}, %{"a" => 1, "b" => nil})
    refute Value.equal?(true, 1)
    refute Value.equal?(1, 1.0)
    refute Value.equal?([1, 2], [2, 1])
    refute Value.equal?("é", "e\u0301")
    refute Value.equal?(self(), self())
  end

  test "byte budgets count canonical bytes including quotes and escaped controls" do
    assert Value.canonical("é", max_bytes: 4) == {:ok, "\"é\""}
    assert Value.validate("é", max_bytes: 3) == {:error, :max_bytes}
    assert Value.validate("\n", max_bytes: 7) == {:error, :max_bytes}
    assert Value.validate("\n", max_bytes: 8) == :ok
    assert Value.validate(%{"a" => 1}, max_bytes: 7) == :ok
    assert Value.validate(%{"a" => 1}, max_bytes: 6) == {:error, :max_bytes}

    assert Value.validate(%{String.duplicate("x", 100) => nil}, max_bytes: 10) ==
             {:error, :max_bytes}
  end

  test "depth counts containers and node budgets exclude object keys" do
    assert Value.validate(1, max_depth: 0) == :ok
    assert Value.validate([], max_depth: 0) == {:error, :max_depth}
    assert Value.validate([%{"a" => 1}], max_depth: 2, max_nodes: 3) == :ok
    assert Value.validate([%{"a" => 1}], max_depth: 1) == {:error, :max_depth}
    assert Value.validate([%{"a" => 1}], max_nodes: 2) == {:error, :max_nodes}
    assert Value.validate(%{"a" => 1, "b" => 2}, max_nodes: 3) == :ok
    assert Value.validate(%{"a" => 1, "b" => 2}, max_nodes: 2) == {:error, :max_nodes}
    assert Value.validate(nil, max_nodes: 0) == {:error, :max_nodes}
  end

  test "default depth and node limits are enforced" do
    nested = Enum.reduce(1..32, nil, fn _, value -> [value] end)
    assert Value.validate(nested) == :ok
    assert Value.validate([nested]) == {:error, :max_depth}
    assert Value.validate(List.duplicate(nil, 9_999)) == :ok
    assert Value.validate(List.duplicate(nil, 10_000)) == {:error, :max_nodes}
  end

  test "invalid or unknown budgets are rejected" do
    for opts <- [[max_bytes: -1], [max_nodes: 1.0], [unknown: 1], [:invalid], %{}] do
      assert Value.validate(nil, opts) == {:error, :invalid_budget}
    end
  end
end

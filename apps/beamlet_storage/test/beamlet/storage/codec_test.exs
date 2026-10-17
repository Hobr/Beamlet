defmodule Beamlet.Storage.CodecTest do
  use ExUnit.Case, async: true
  alias Beamlet.Storage.Codec

  test "sorted UTF-8 JSON digest is stable and retains numeric type" do
    assert {:ok, ~s({"a":[true,null,"世界"],"z":1})} =
             Codec.encode(%{"z" => 1, "a" => [true, nil, "世界"]})

    assert Codec.digest(%{"a" => 1, "b" => 2}) == Codec.digest(%{"b" => 2, "a" => 1})
    refute Codec.digest(1) == Codec.digest(1.0)
    assert {:ok, %{"x" => [1.0]}} = Codec.decode(~s({"x":[1.0]}))
    assert {:error, :invalid_data} = Codec.decode(~s({"x":1,"x":2}))
  end

  test "nested live and secret values never encode or leak in errors" do
    for bad <- [
          self(),
          make_ref(),
          fn -> :ok end,
          {:tuple, 1},
          URI.parse("https://example.test"),
          :atom,
          <<255>>,
          [1 | :bad],
          %{"Credentials" => %{"key" => "not-logged"}},
          %{"api_key" => "not-logged"},
          %{atom_key: "value"}
        ] do
      assert {:error, :invalid_data} = Codec.encode(%{"nested" => [bad]})
    end

    assert {:error, :invalid_data} = Codec.encode(%{<<255>> => "value"})
    assert {:error, :invalid_data} = Codec.decode("1e400")
    # Text is subject to caller policy, not speculative secret recognition.
    assert {:ok, _} =
             Codec.encode(%{
               "text" => "password is arbitrary text",
               "secret_ref" => "profile/key"
             })
  end

  test "exact persisted byte limit and one byte over, not ETF size" do
    n = Codec.limit(:operation)
    assert {:ok, bytes} = Codec.encode(String.duplicate("a", n - 2), :operation)
    assert byte_size(bytes) == n
    assert {:error, :limit} = Codec.encode(String.duplicate("a", n - 1), :operation)
    assert {:error, :limit} = Codec.encode(String.duplicate("\n", div(n, 2)), :operation)
    assert {:error, :limit} = Codec.decode(String.duplicate(" ", n + 1), :operation)
  end

  test "depth, parser recursion and total nodes are bounded" do
    nested = fn n -> Enum.reduce(1..n, nil, fn _, acc -> [acc] end) end
    assert {:ok, _} = Codec.encode(nested.(32))
    assert {:error, :limit} = Codec.encode(nested.(33))

    assert {:error, _} =
             Codec.decode(String.duplicate("[", 100_000) <> "0" <> String.duplicate("]", 100_000))

    assert {:error, :limit} = Codec.encode(List.duplicate(nil, 100_000))
    assert {:ok, _} = Codec.encode(List.duplicate(nil, 99_999))
  end
end

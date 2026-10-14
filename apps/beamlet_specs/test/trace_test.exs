defmodule Beamlet.Specs.TraceTest do
  use ExUnit.Case, async: true
  alias Beamlet.Specs.Trace

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "beamlet-trace-test-#{Base.encode16(:crypto.strong_rand_bytes(12))}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "reads the final namespaced checkpoint sequence and nested ITF integers without rounding" do
    rows = [
      %{
        "op" => "complete",
        "value" => %{"#bigint" => "9223372036854775807"},
        "nested" => [%{"#list" => [%{"#bigint" => "-1"}]}]
      }
    ]

    document = %{"states" => [%{}, %{"oracle0::profile::rows" => rows}]}

    assert Trace.rows!(document) == [
             %{"op" => "complete", "value" => 9_223_372_036_854_775_807, "nested" => [[-1]]}
           ]
  end

  test "rejects absent, ambiguous and empty checkpoints instead of silently passing" do
    for document <- [
          %{"states" => []},
          %{"states" => [%{}]},
          %{"states" => [%{"rows" => [], "other::rows" => []}]},
          %{"states" => [%{"rows" => []}]},
          %{"states" => [%{"rows" => [%{"wrong" => 1}]}]}
        ] do
      assert_raise ArgumentError, fn -> Trace.rows!(document) end
    end
  end

  test "replay threads driver state in checkpoint order", %{dir: dir} do
    rows = [%{"op" => "claim", "generation" => 1}, %{"op" => "replay", "generation" => 1}]

    driver = fn state, op ->
      next = if op == "claim", do: state + 1, else: state
      {next, %{"op" => op, "generation" => next}}
    end

    assert Trace.replay!(dir, "ordered", rows, 0, driver) == 1

    lines =
      Path.join(dir, "ordered.observed.jsonl") |> File.stream!() |> Enum.map(&:json.decode/1)

    assert Enum.map(lines, & &1["index"]) == [0, 1]
    refute File.exists?(Path.join(dir, "ordered.failure.json"))
  end

  test "first mismatch retains both projections and stops before the next effect", %{dir: dir} do
    rows = [%{"op" => "invoke", "calls" => 1}, %{"op" => "never", "calls" => 1}]

    driver = fn state, op ->
      send(self(), {:driver_called, op})
      {state, %{"op" => op, "calls" => 2}}
    end

    assert_raise RuntimeError, ~r/checkpoint 0 \(invoke\)/, fn ->
      Trace.replay!(dir, "mismatch", rows, nil, driver)
    end

    assert_received {:driver_called, "invoke"}
    refute_received {:driver_called, "never"}
    failure = Path.join(dir, "mismatch.failure.json") |> File.read!() |> :json.decode()
    assert failure["index"] == 0
    assert failure["expected"]["calls"] == 1
    assert failure["actual"]["calls"] == 2
  end

  test "unexpected or missing projection fields also fail", %{dir: dir} do
    for actual <- [%{"op" => "stored"}, %{"op" => "stored", "outcomes" => 1, "unexpected" => 1}] do
      assert_raise RuntimeError, ~r/trace mismatch/, fn ->
        Trace.replay!(dir, "fields", [%{"op" => "stored", "outcomes" => 1}], nil, fn state, _ ->
          {state, actual}
        end)
      end
    end
  end

  test "driver exceptions retain the exact failing operation", %{dir: dir} do
    assert_raise ArgumentError, "provider failed", fn ->
      Trace.replay!(dir, "exception", [%{"op" => "query"}], nil, fn _, _ ->
        raise ArgumentError, "provider failed"
      end)
    end

    error = Path.join(dir, "exception.error.json") |> File.read!() |> :json.decode()
    assert error == %{"index" => 0, "op" => "query", "error" => "provider failed"}
  end
end

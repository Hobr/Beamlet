defmodule Beamlet.ActionsTest do
  use ExUnit.Case, async: true
  alias Beamlet.Actions.{Operation, Result}

  test "bounded data is accepted without mutating arguments" do
    payload = %{"x" => [1, true, "hello"]}
    assert {:ok, op} = Operation.new(kind: "echo", payload: payload)
    assert op.payload == payload
  end

  test "executable and sensitive descriptions are rejected" do
    for payload <- [
          self(),
          make_ref(),
          fn -> :ok end,
          %{root: "/etc"},
          %{token: "x"},
          %{workspace_root: "/etc"},
          {1, 2}
        ] do
      assert {:error, :invalid_operation} = Operation.new(kind: "echo", payload: payload)
    end
  end

  test "full envelope, budgets, claims and nesting are bounded" do
    for attrs <- [
          [payload: String.duplicate("x", 262_144)],
          [budget_ms: 0],
          [claims: %{"cpu" => -1}],
          [unknown: 1]
        ] do
      assert {:error, :invalid_operation} = Operation.new([kind: "echo"] ++ attrs)
    end

    nested = Enum.reduce(1..30, 1, fn _, x -> [x] end)
    assert {:error, :invalid_operation} = Operation.new(kind: "echo", payload: nested)
  end

  test "ordinary slash-prefixed text is data while workspace roots remain forbidden" do
    assert {:ok, _} = Operation.new(kind: "echo", payload: "/ is a slash")
    refute Result.valid?(%Result{operation_id: "op", status: :ok, source: :execution})

    refute Result.valid?(%Result{
             operation_id: "op",
             status: :ok,
             source: :coordinator,
             metadata: []
           })
  end

  test "result envelope has an independent bound" do
    assert Result.valid?(%Result{
             operation_id: "op",
             execution_id: "exec",
             status: :ok,
             source: :execution,
             value: "yes"
           })

    refute Result.valid?(%Result{
             status: :ok,
             source: :execution,
             value: String.duplicate("x", 1_048_576)
           })
  end
end

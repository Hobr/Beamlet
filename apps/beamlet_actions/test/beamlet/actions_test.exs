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

  test "dedicated credentials accept JSON secrets without weakening ordinary data" do
    credentials = %{
      "api_key" => "synthetic",
      "session" => [%{"token" => "bearer"}, true, nil, 1.5]
    }

    assert {:ok, op} = Operation.new(kind: "echo", credentials: credentials)
    assert op.credentials == credentials
    refute Beamlet.Actions.bounded?(credentials, 16_384)

    refute Result.valid?(%Result{
             operation_id: "op",
             execution_id: "exec",
             source: :execution,
             status: :ok,
             value: credentials
           })

    assert {:ok, %{credentials: %{}}} = Operation.new(kind: "echo")

    for field <- [:payload, :metadata] do
      assert {:error, :invalid_operation} =
               Operation.new([{:kind, "echo"}, {field, credentials}])
    end
  end

  test "credentials reject non JSON values, roots, malformed text and improper lists" do
    for value <- [
          self(),
          make_ref(),
          fn -> :ok end,
          {1, 2},
          :arbitrary,
          %Operation{},
          [1 | 2],
          <<255>>,
          %{token: "x"},
          %{"root" => "x"},
          [%{"workspace_root" => "x"}]
        ] do
      assert {:error, :invalid_operation} =
               Operation.new(kind: "echo", credentials: %{"token" => value})
    end

    for value <- [
          [],
          %Operation{},
          %{token: "x"},
          %{"" => "x"},
          %{String.duplicate("é", 65) => "x"},
          %{<<255>> => "x"}
        ] do
      assert {:error, :invalid_operation} = Operation.new(kind: "echo", credentials: value)
    end
  end

  for label <- ["root", "Root", "ROOT", "workspace_root", "Workspace_Root", "WORKSPACE_ROOT"],
      location <- [:top, :nested, :list] do
    @tag :credential_root_policy
    test "credentials reject #{label} at #{location}" do
      root = %{unquote(label) => "synthetic-root-secret"}

      credentials =
        case unquote(location) do
          :top -> root
          :nested -> %{"session" => %{"credentials" => root}}
          :list -> %{"session" => [true, %{"credentials" => [root]}]}
        end

      refute Beamlet.Actions.credentials?(credentials)

      assert {:error, :invalid_operation} =
               Operation.new(kind: "echo", credentials: credentials)

      assert {:error, :invalid_operation} =
               Operation.validate(%Operation{kind: "echo", credentials: credentials})
    end
  end

  @tag :credential_root_policy
  test "non root credential labels remain valid at every nesting location" do
    for label <- [
          "api_key",
          "TOKEN",
          "Credentials",
          "password",
          "authorization",
          "root_token",
          "workspace_root_id",
          "rooted"
        ] do
      object = %{label => "synthetic-credential"}

      for credentials <- [
            object,
            %{"session" => %{"credentials" => object}},
            %{"session" => [true, %{"credentials" => [object]}]}
          ] do
        assert Beamlet.Actions.credentials?(credentials)
        assert {:ok, op} = Operation.new(kind: "echo", credentials: credentials)
        assert op.credentials == credentials
        assert :ok = Operation.validate(op)
      end
    end
  end

  test "credential count, UTF8 names, depth and exact serialized JSON limits" do
    fields = Map.new(1..32, &{Integer.to_string(&1), true})
    assert {:ok, _} = Operation.new(kind: "echo", credentials: fields)

    assert {:error, :invalid_operation} =
             Operation.new(kind: "echo", credentials: Map.put(fields, "33", true))

    assert {:ok, _} = Operation.new(kind: "echo", credentials: %{String.duplicate("é", 64) => 1})
    at_depth = Enum.reduce(1..23, 1, fn _, item -> [item] end)
    assert {:ok, _} = Operation.new(kind: "echo", credentials: %{"x" => at_depth})

    assert {:error, :invalid_operation} =
             Operation.new(kind: "echo", credentials: %{"x" => [at_depth]})

    for {char, count} <- [{"x", 16_376}, {"\n", 8188}] do
      credentials = %{"x" => String.duplicate(char, count)}
      assert IO.iodata_length(:json.encode(credentials)) == 16_384
      assert {:ok, _} = Operation.new(kind: "echo", credentials: credentials)

      assert {:error, :invalid_operation} =
               Operation.new(
                 kind: "echo",
                 credentials: Map.update!(credentials, "x", &(&1 <> char))
               )
    end
  end

  test "full protocol envelope includes credentials at the exact byte boundary" do
    base = %Operation{kind: "echo", credentials: %{"token" => "synthetic"}, payload: ""}
    op = %{base | payload: String.duplicate("x", 262_144 - :erlang.external_size(base))}
    assert :erlang.external_size(op) == 262_144
    assert :ok = Operation.validate(op)
    assert {:error, :invalid_operation} = Operation.validate(%{op | payload: op.payload <> "x"})
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

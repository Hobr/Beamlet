defmodule Beamlet.HarnessTest do
  use ExUnit.Case, async: true
  alias Beamlet.Harness.{Arguments, Catalogue, Context}
  alias Beamlet.Harness.Models.{Deterministic, OpenAICompatible}
  alias Beamlet.Harness.Tools.WorkspaceRead

  def call(id, path \\ "a"),
    do: %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => "workspace_read", "arguments" => Jason.encode!(%{"path" => path})}
    }

  def reply(message, finish \\ "stop"),
    do: %{
      "choices" => [
        %{"finish_reason" => finish, "message" => Map.put(message, "role", "assistant")}
      ]
    }

  test "catalogue rejects unsupported schemas and malformed siblings atomically" do
    descriptor = WorkspaceRead.descriptor()
    assert {:ok, catalogue} = Catalogue.new([descriptor])
    assert {:error, :invalid_catalogue} = Catalogue.new([descriptor, descriptor])

    assert {:error, :invalid_catalogue} =
             Catalogue.new([put_in(descriptor, ["parameters", "oneOf"], [])])

    assert {:ok, [%{id: "b"}, %{id: "a"}]} = Catalogue.batch([call("b"), call("a")], catalogue)

    for calls <- [
          [call("a"), call("a")],
          [call("ok"), %{}],
          List.duplicate(call("a"), 9),
          [put_in(call("a"), ["function", "arguments"], "{}")]
        ] do
      assert {:error, :invalid_tool_batch} = Catalogue.batch(calls, catalogue)
    end

    assert {:error, :invalid_arguments} =
             Arguments.validate(%{"path" => "a", "root" => "/"}, descriptor["parameters"])
  end

  test "complete replies reject refusals, incomplete and unsupported actions" do
    {:ok, catalogue} = Catalogue.new([WorkspaceRead.descriptor()])
    message = %{"content" => nil, "tool_calls" => [call("original")]}
    message_with_role = Map.put(message, "role", "assistant")

    assert {:ok, %{calls: [%{id: "original"}], assistant: ^message_with_role}} =
             normalize_bind(message, catalogue)

    for bad <- [
          reply(message, "length"),
          reply(message, "content_filter"),
          reply(Map.put(message, "refusal", "no"), "tool_calls"),
          reply(Map.put(message, "function_call", %{}), "tool_calls"),
          reply(message),
          Map.put(reply(message, "tool_calls"), "actions", []),
          put_in(reply(message, "tool_calls"), ["choices", Access.at(0), "function_call"], %{})
        ] do
      assert {:error, _} = OpenAICompatible.normalize(bad, catalogue)
    end
  end

  defp normalize_bind(message, catalogue) do
    OpenAICompatible.normalize(reply(message, "tool_calls"), catalogue)
  end

  test "context preserves pairs, rejects growth and neutral cancellation works" do
    assert {:error, :context_limit} = Context.append([], List.duplicate(%{}, 129))

    assert {:error, :context_limit} =
             Context.append([], [%{"content" => String.duplicate("a", 1_048_576)}])

    request = %{messages: [%{"role" => "user", "content" => "hi"}], catalogue: %{}}

    assert {:error, :cancelled} =
             Deterministic.complete(request, %{reply: reply(%{"content" => "ok"})}, %Context{
               cancelled?: fn -> true end
             })

    parent = self()

    assert {:ok, %{content: "ok"}} =
             Deterministic.complete(request, %{reply: reply(%{"content" => "ok"})}, %Context{
               progress: &send(parent, &1)
             })

    assert_received %{phase: "complete"}
  end

  test "primitive schema bounds and unsupported nested/array schemas fail explicitly" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "s" => %{"type" => "string", "enum" => ["ok"], "minLength" => 2, "maxLength" => 2},
        "n" => %{"type" => "integer", "minimum" => 1, "maximum" => 3},
        "b" => %{"type" => "boolean"}
      },
      "required" => ["s", "n", "b"],
      "additionalProperties" => false
    }

    valid = %{"s" => "ok", "n" => 2, "b" => true}
    assert :ok = Arguments.validate(valid, schema)

    for bad <- [
          Map.put(valid, "n", 0),
          Map.put(valid, "n", 4),
          Map.put(valid, "n", 1.5),
          Map.put(valid, "s", "no"),
          Map.put(valid, "b", "true"),
          Map.delete(valid, "s")
        ] do
      assert {:error, :invalid_arguments} = Arguments.validate(bad, schema)
    end

    for spec <- [
          %{"type" => "array"},
          %{"type" => "object"},
          %{"type" => "string", "pattern" => ".*"},
          %{"type" => "number", "enum" => ["bad"]}
        ] do
      refute Arguments.schema?(put_in(schema, ["properties", "n"], spec))
    end
  end

  test "deterministic Tool obeys the native contract and limit" do
    alias Beamlet.Harness.Tools.Deterministic, as: Echo
    assert {:ok, %{text: "hello"}} = Echo.invoke(%{"text" => "hello"}, %{})

    assert {:error, :invalid_arguments} =
             Echo.invoke(%{"text" => String.duplicate("x", 1025)}, %{})

    assert {:error, :invalid_arguments} =
             Echo.invoke(%{"text" => "a" <> String.duplicate("\u0301", 1024)}, %{})

    assert {:error, :cancelled} =
             Echo.invoke(%{"text" => "hello"}, %{}, %Context{cancelled?: fn -> true end})
  end

  test "public validators reject malformed native values and mismatched catalogue keys" do
    {:ok, catalogue} = Catalogue.new([WorkspaceRead.descriptor()])
    mismatched = %{"other" => catalogue["workspace_read"]}

    for bad <- [nil, [], %{"workspace_read" => nil}, mismatched] do
      assert {:error, :invalid_catalogue} = Catalogue.validate(bad)
      assert {:error, :invalid_tool_batch} = Catalogue.batch([call("opaque")], bad)

      assert {:error, :invalid_catalogue} =
               OpenAICompatible.normalize(reply(%{"content" => "ok"}), bad)
    end

    assert {:error, :context_limit} = Context.append(nil, [])
    assert {:error, :invalid_reply} = OpenAICompatible.normalize(%{"choices" => self()}, %{})

    assert {:error, :progress_limit} =
             Context.emit(%Context{progress: fn _ -> flunk("invalid event") end}, %{pid: self()})

    schema = %{"type" => "object", "properties" => %{}, "additionalProperties" => true}
    assert {:error, :invalid_arguments} = Arguments.validate(%{atom: 1}, schema)
  end

  test "deterministic provider enforces the same complete history and request contract" do
    settings = %{reply: reply(%{"content" => "ok"})}
    {:ok, catalogue} = Catalogue.new([WorkspaceRead.descriptor()])
    base = %{messages: [%{"role" => "user", "content" => "hi"}], catalogue: catalogue}
    assistant = %{"role" => "assistant", "content" => nil, "tool_calls" => [call("one")]}

    for {request, error} <- [
          {%{}, :invalid_request},
          {Map.put(base, :actions, []), :invalid_request},
          {%{base | messages: [assistant]}, :invalid_messages},
          {%{base | catalogue: %{"wrong" => WorkspaceRead.descriptor()}}, :invalid_catalogue},
          {%{base | messages: nil}, :context_limit}
        ] do
      assert {:error, ^error} = OpenAICompatible.validate_request(request)
      assert {:error, ^error} = Deterministic.complete(request, settings, %Context{})
    end

    assert {:error, :invalid_profile} = Deterministic.complete(base, %{}, %Context{})
  end

  test "complete native request envelope is bounded, including catalogue and history together" do
    descriptors =
      for n <- 1..64,
          do: %{
            WorkspaceRead.descriptor()
            | "name" => "read_#{n}",
              "description" => String.duplicate("x", 4096)
          }

    {:ok, catalogue} = Catalogue.new(descriptors)

    request = %{
      messages: [%{"role" => "user", "content" => String.duplicate("x", 900_000)}],
      catalogue: catalogue
    }

    assert {:error, :request_limit} = OpenAICompatible.validate_request(request)

    assert {:error, :request_limit} =
             Deterministic.complete(request, %{reply: reply(%{"content" => "ok"})}, %Context{})
  end
end

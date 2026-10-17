defmodule Beamlet.Harness.ModelTest do
  use ExUnit.Case, async: true
  alias Beamlet.Harness.{Catalogue, Context, Model}
  alias Beamlet.Harness.Models.{Deterministic, OpenAICompatible}
  alias Beamlet.Harness.Tools.WorkspaceRead

  # Different configuration/authentication and a tuple internal protocol. No OpenAI codecs.
  defmodule Alternative do
    @behaviour Beamlet.Harness.Model
    @impl true
    def validate_invocation(invocation) do
      with :ok <- Model.validate_invocation(invocation),
           %{
             config: %{"variant" => "local"} = config,
             credentials: %{"session" => %{"bearer" => "alternative-secret"}} = credentials
           } <- invocation,
           true <- map_size(config) == 1 and map_size(credentials) == 1 do
        :ok
      else
        _ -> {:error, :invalid_alternative}
      end
    end

    @impl true
    def complete(request, invocation, %Context{}) do
      with :ok <- validate_invocation(invocation), :ok <- Model.validate_request(request) do
        internal =
          if List.last(request.messages)["role"] == "tool",
            do: {:say, "finished"},
            else: {:invoke, "first", "workspace_read", %{"path" => "a"}}

        reply =
          case internal do
            {:say, text} ->
              %{kind: :text, content: text, calls: []}

            {:invoke, id, name, args} ->
              %{
                kind: :tool_calls,
                content: "reading",
                calls: [%{id: id, name: name, arguments: args}]
              }
          end

        with :ok <- Model.validate_reply(reply, request.catalogue), do: {:ok, reply}
      end
    end
  end

  test "independent protocol completes neutral tool history and text with different auth" do
    {:ok, catalogue} = Catalogue.new([WorkspaceRead.descriptor()])
    request = %{messages: [%{"role" => "user", "content" => "read"}], catalogue: catalogue}

    invocation = %{
      config: %{"variant" => "local"},
      credentials: %{"session" => %{"bearer" => "alternative-secret"}}
    }

    assert :ok = Model.validate_registry(%{"alternative" => Alternative})
    assert {:ok, reply} = Alternative.complete(request, invocation, %Context{})

    assert reply == %{
             kind: :tool_calls,
             content: "reading",
             calls: [%{id: "first", name: "workspace_read", arguments: %{"path" => "a"}}]
           }

    messages =
      request.messages ++
        [
          Model.assistant_message(reply),
          %{"role" => "tool", "call_id" => "first", "content" => "observation"}
        ]

    assert {:ok, %{kind: :text, content: "finished", calls: []} = final} =
             Alternative.complete(%{request | messages: messages}, invocation, %Context{})

    refute inspect({messages, reply, final}) =~ "alternative-secret"

    assert {:error, :invalid_alternative} =
             Alternative.complete(request, %{invocation | credentials: %{}}, %Context{})
  end

  test "common invocation and trusted registries enforce JSON, counts, depth and byte caps" do
    assert :ok = Model.validate_registry(Model.default_providers())

    for bad <- [
          %{"bad.id" => Alternative},
          %{"alternative" => String},
          %{1 => Alternative},
          Map.new(1..33, &{"p#{&1}", Alternative})
        ] do
      assert {:error, :invalid_model_providers} = Model.validate_registry(bad)
    end

    base = %{config: %{}, credentials: %{"nested" => [%{"token" => "ok"}, 1, true, nil]}}
    assert :ok = Model.validate_invocation(base)

    assert {:error, :invalid_invocation} =
             Model.validate_invocation(%{base | credentials: %{"x" => [1 | 2]}})

    assert {:error, :context_limit} = Context.append([], [%{} | :invalid])
    deep = Enum.reduce(1..25, "x", fn _, value -> [value] end)

    for credentials <- [
          %{atom: "x"},
          %{"x" => self()},
          %{"x" => :executable},
          %{"x" => deep},
          %{"x" => String.duplicate("x", 16_384)},
          %{"root" => "/"},
          Map.new(1..33, &{"k#{&1}", "x"}),
          %{String.duplicate("x", 129) => "v"}
        ] do
      assert {:error, :invalid_invocation} =
               Model.validate_invocation(%{base | credentials: credentials})
    end

    for config <- [%{"token" => "secret"}, %{atom: "x"}, %{"x" => String.duplicate("x", 16_384)}] do
      assert {:error, :invalid_invocation} = Model.validate_invocation(%{base | config: config})
    end
  end

  test "OpenAI invocation requires explicit exact config and credentials without fallback" do
    base = %{
      config: %{"model" => "m", "base_url" => "https://example.test/v1"},
      credentials: %{"api_key" => "fixture"}
    }

    assert :ok = OpenAICompatible.validate_invocation(base)

    for credentials <- [
          %{},
          %{"api_key" => ""},
          %{"api_key" => <<255>>},
          %{"api_key" => "a\nb"},
          %{"api_key" => String.duplicate("x", 4097)},
          Map.put(base.credentials, "token", "extra")
        ] do
      invocation = %{base | credentials: credentials}
      assert {:error, :invalid_profile} = OpenAICompatible.validate_invocation(invocation)
      assert {:error, :invalid_profile} = OpenAICompatible.complete(%{}, invocation)
    end

    for config <- [
          Map.put(base.config, "key_env", "HARNESS_FIXTURE_KEY"),
          Map.put(base.config, "timeout_ms", 60_001),
          Map.put(base.config, "temperature", 0.5)
        ] do
      assert {:error, :invalid_profile} =
               OpenAICompatible.validate_invocation(%{base | config: config})
    end

    assert {:error, :invalid_profile} =
             OpenAICompatible.complete(%{}, %{
               base_url: "https://example.test",
               model: "m",
               key_env: "HARNESS_FIXTURE_KEY"
             })
  end

  test "direct neutral replies reject improper call lists and nested unsupported data" do
    {:ok, catalogue} = Catalogue.new([WorkspaceRead.descriptor()])
    call = %{id: "one", name: "workspace_read", arguments: %{"path" => "a"}}
    reply = %{kind: :tool_calls, content: nil, calls: [call]}

    for calls <- [
          [1 | 2],
          [call | :tail],
          [%{call | arguments: %{"path" => [1 | 2]}}],
          [%{call | arguments: %{"path" => [%{"nested" => [1 | 2]}]}}]
        ] do
      assert {:error, :invalid_reply} = Model.validate_reply(%{reply | calls: calls}, catalogue)
    end

    assert :ok = Model.validate_reply(reply, catalogue)
  end

  test "direct OpenAI normalization rejects improper envelopes and nested unsupported data" do
    wire = %{
      "choices" => [
        %{"finish_reason" => "stop", "message" => %{"role" => "assistant", "content" => "ok"}}
      ]
    }

    for malformed <- [
          [1 | 2],
          %{"choices" => [1 | 2]},
          put_in(wire, ["choices", Access.at(0), "message", "tool_calls"], [1 | 2]),
          Map.put(wire, "usage", %{"nested" => [%{"value" => [1 | 2]}]})
        ] do
      assert {:error, :invalid_reply} = OpenAICompatible.normalize(malformed, %{})
    end

    assert {:ok, %{kind: :text, content: "ok", calls: []}} =
             OpenAICompatible.normalize(wire, %{})
  end

  test "improper schema lists retain catalogue errors at direct reply and request boundaries" do
    descriptor = WorkspaceRead.descriptor()

    for schema <- [
          Map.put(descriptor["parameters"], "required", ["path" | :tail]),
          put_in(descriptor["parameters"], ["properties", "path", "enum"], ["a" | :tail])
        ] do
      descriptor = %{descriptor | "parameters" => schema}
      catalogue = %{"workspace_read" => descriptor}
      assert {:error, :invalid_catalogue} = Catalogue.new([descriptor])
      assert {:error, :invalid_catalogue} = Catalogue.validate(catalogue)

      assert {:error, :invalid_catalogue} =
               Model.validate_reply(%{kind: :text, content: "ok", calls: []}, catalogue)

      assert {:error, :invalid_catalogue} = OpenAICompatible.normalize(%{}, catalogue)

      assert {:error, :invalid_catalogue} =
               Model.validate_request(%{messages: [], catalogue: catalogue})
    end
  end

  test "direct reply limits count complete neutral and OpenAI envelopes at one MiB" do
    neutral = %{kind: :text, content: "", calls: []}

    wire = %{
      "choices" => [
        %{"finish_reason" => "stop", "message" => %{"role" => "assistant", "content" => ""}}
      ]
    }

    neutral_text = String.duplicate("x", 1_048_576 - byte_size(Jason.encode!(neutral)))
    wire_text = String.duplicate("x", 1_048_576 - byte_size(Jason.encode!(wire)))
    neutral = %{neutral | content: neutral_text}
    wire = put_in(wire, ["choices", Access.at(0), "message", "content"], wire_text)
    assert byte_size(Jason.encode!(neutral)) == 1_048_576
    assert byte_size(Jason.encode!(wire)) == 1_048_576
    assert :ok = Model.validate_reply(neutral, %{})
    assert {:ok, %{content: ^wire_text}} = OpenAICompatible.normalize(wire, %{})

    assert {:error, :response_limit} =
             Model.validate_reply(%{neutral | content: neutral_text <> "x"}, %{})

    assert {:error, :response_limit} =
             OpenAICompatible.normalize(
               put_in(wire, ["choices", Access.at(0), "message", "content"], wire_text <> "x"),
               %{}
             )
  end

  test "neutral replies reject wire envelopes and unsupported or oversized fields" do
    {:ok, catalogue} = Catalogue.new([WorkspaceRead.descriptor()])

    reply = %{
      kind: :tool_calls,
      content: nil,
      calls: [%{id: "one", name: "workspace_read", arguments: %{"path" => "a"}}]
    }

    assert :ok = Model.validate_reply(reply, catalogue)

    for bad <- [
          Map.put(reply, :assistant, %{}),
          %{reply | calls: []},
          %{reply | calls: reply.calls ++ reply.calls},
          %{reply | content: <<255>>},
          %{reply | calls: [%{hd(reply.calls) | id: ""}]},
          %{"choices" => []}
        ] do
      assert {:error, :invalid_reply} = Model.validate_reply(bad, catalogue)
    end

    assert {:error, :response_limit} =
             Model.validate_reply(
               %{kind: :text, content: String.duplicate("x", 1_048_576), calls: []},
               %{}
             )

    assert {:error, :invalid_messages} =
             Model.validate_request(%{
               messages: [%{"role" => "assistant", "content" => nil, "tool_calls" => []}],
               catalogue: catalogue
             })

    assert {:error, :invalid_tool_batch} =
             Catalogue.batch([%{"id" => "x", "type" => "function", "function" => %{}}], catalogue)

    assert {:error, :invalid_profile} =
             Deterministic.complete(%{}, %{
               config: %{"reply" => %{"choices" => []}},
               credentials: %{}
             })
  end
end

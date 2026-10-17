defmodule Beamlet.Agent.DisplayProjectionTest do
  use ExUnit.Case, async: true
  alias Beamlet.Agent.{Display, Ref}

  defp state do
    %{
      ref: %Ref{authority: node(), id: "projection", incarnation: make_ref(), pid: self()},
      sequence: 0,
      turn: make_ref(),
      status: :running,
      messages: [],
      display_entries: [],
      display_metadata: %{},
      owners: %{},
      pending: %{},
      assistant: nil,
      children: %{},
      results: %{}
    }
  end

  defp base(s),
    do: %{
      ref: s.ref,
      status: s.status,
      turn: s.turn,
      terminal_turn: nil,
      final: nil,
      progress: nil,
      steps: 0
    }

  test "exact 8192-byte content and all UTF-8 split widths are bounded without source mutation" do
    for char <- ["é", "界", "😀"], suffix <- 0..(byte_size(char) - 1) do
      text = String.duplicate("a", 8192 - suffix) <> char
      s = Display.annotate(state(), [%{"role" => "user", "content" => text}])
      snapshot = Display.project(base(s), s)
      [entry] = snapshot.display.entries
      assert entry.truncated
      assert byte_size(entry.content) == 8192 - suffix
      assert String.valid?(entry.content)
      assert s.messages == [%{"role" => "user", "content" => text}]
    end

    for size <- [8191, 8192, 8193] do
      text = String.duplicate("x", size)
      s = Display.annotate(state(), [%{"role" => "assistant", "content" => text}])
      [entry] = Display.project(base(s), s).display.entries
      assert byte_size(entry.content) == min(size, 8192)
      assert entry.truncated == size > 8192
    end
  end

  test "recent-entry and aggregate target omissions count every omitted source entry" do
    messages = for i <- 1..128, do: %{"role" => "user", "content" => "message#{i}"}
    s = Display.annotate(state(), messages)
    display = Display.project(base(s), s).display
    assert length(display.entries) == 32
    assert hd(display.entries).content == "message97"
    assert display.omitted == %{entries: 96, activities: 0}
    assert display.reasons == [:entry_limit]
    assert length(s.display_entries) == 128

    large = Enum.map(messages, &Map.put(&1, "content", String.duplicate("界", 3000)))
    s = %{s | messages: large}
    snapshot = Display.project(base(s), s)
    display = snapshot.display
    assert :erlang.external_size(display) <= 131_072
    assert :erlang.external_size({:beamlet_agent, s.ref, 1, {:snapshot, snapshot}}) <= 1_048_000
    assert length(display.entries) + display.omitted.entries == 128
    assert length(display.entries) < 32

    one_more = %{
      display
      | entries: [hd(display.entries) | display.entries],
        omitted: %{display.omitted | entries: display.omitted.entries - 1}
    }

    assert :erlang.external_size(one_more) > 131_072
    assert :snapshot_budget in display.reasons
    assert :field_limit in display.reasons
    assert :entry_limit in display.reasons
    assert length(s.messages) == 128
  end

  test "activities and complete argument/result JSON text have independent exact field bounds" do
    s = state()

    calls =
      for i <- 1..24,
          do: %{
            "id" => "call#{i}",
            "name" => "echo",
            "arguments" => %{"x" => String.duplicate("a", 8200)}
          }

    results =
      Map.new(calls, &{&1["id"], %{"role" => "tool", "content" => String.duplicate("😀", 3000)}})

    s = %{s | assistant: %{"calls" => calls}, results: results}
    display = Display.project(base(s), s).display
    assert display.omitted.activities + length(display.activities) == 24
    assert length(display.activities) <= 16
    assert :activity_limit in display.reasons
    assert display.truncated

    assert Enum.all?(display.activities, fn activity ->
             activity.truncated and byte_size(activity.arguments) == 8192 and
               byte_size(activity.result) == 8192 and String.valid?(activity.result) and
               activity.status == :completed and activity.placement == :unknown
           end)

    assert :erlang.external_size(display) <= 131_072

    for size <- [8192, 8193] do
      # JSON encoding the complete argument object adds eight bytes.
      arguments = %{"x" => String.duplicate("x", size - 8)}
      assert byte_size(Jason.encode!(arguments)) == size

      s = state()

      s = %{
        s
        | assistant: %{"calls" => [%{"id" => "a", "name" => "echo", "arguments" => arguments}]},
          owners: %{make_ref() => %{key: "a", turn: s.turn}}
      }

      [activity] = Display.project(base(s), s).display.activities
      assert byte_size(activity.arguments) == 8192
      assert activity.truncated == size > 8192
    end
  end

  test "prepared calls become activities only when an owner, operation or result exists" do
    s = state()

    calls =
      for id <- ["started", "prepared"],
          do: %{"id" => id, "name" => "echo", "arguments" => %{}}

    s = %{s | assistant: %{"calls" => calls}}
    assert Display.project(base(s), s).display.activities == []

    token = make_ref()
    owner = %{key: "started", turn: s.turn}
    s = %{s | owners: %{token => owner}}
    assert [%{id: "started", status: :admitting}] = Display.project(base(s), s).display.activities

    s = %{s | owners: %{token => %{owner | turn: make_ref()}}}
    assert Display.project(base(s), s).display.activities == []
  end

  test "safe existing non-JSON child terminal errors are explicitly omitted, never inspected or raised" do
    s = state()

    result = %{
      child: s.ref,
      turn: make_ref(),
      result: {:error, %{type: :dispatch_failed, reason: {:error, :executable_input_limit}}}
    }

    s = %{s | status: :waiting, results: %{0 => result}}
    display = Display.project(base(s), s).display

    assert [%{kind: :child, result: nil, truncated: true, result_omitted: :unsupported_content}] =
             display.activities

    assert display.reasons == [:unsupported_content]
    assert display.truncated
    assert s.results[0] == result
  end

  test "full snapshot pressure never changes base final/progress or causes a new snapshot error" do
    s = Display.annotate(state(), [%{"role" => "user", "content" => String.duplicate("a", 8192)}])
    original = base(s)
    # Exercise exact whole-envelope cutoffs, not a rough payload estimate.
    for desired <- [1_040_000, 1_047_800, 1_047_999, 1_048_000] do
      seed = %{original | final: "", progress: %{value: "unchanged"}}
      overhead = :erlang.external_size({:beamlet_agent, s.ref, 1, {:snapshot, seed}})
      base = %{seed | final: String.duplicate("f", desired - overhead)}
      assert :erlang.external_size({:beamlet_agent, s.ref, 1, {:snapshot, base}}) == desired
      projected = Display.project(base, s)
      assert Map.drop(projected, [:display]) == base

      assert :erlang.external_size({:beamlet_agent, s.ref, 1, {:snapshot, projected}}) <=
               1_048_000

      assert projected.status == :running
      if Map.has_key?(projected, :display), do: assert(projected.display.truncated)
    end

    # Old publication checks just the snapshot map. Even an old map exactly at
    # that ceiling must still succeed unchanged when no display marker can fit.
    overhead = :erlang.external_size(%{original | final: ""})
    base = %{original | final: String.duplicate("f", 1_048_000 - overhead)}
    assert :erlang.external_size(base) == 1_048_000
    assert Display.project(base, s) == base
  end
end

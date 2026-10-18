defmodule Beamlet.Agent.ContextReadOrderRepo do
  @moduledoc false
  def get(_, _, _) do
    count_read()
    Process.get(:operation)
  end

  def one(%{select: nil}, _) do
    count_read()
    nil
  end

  def one(query, _) do
    count_read()
    [{scope, _}, {seq, _}] = hd(query.wheres).params
    Process.put(:context_reads, Process.get(:context_reads, []) ++ [{scope, seq}])

    Map.get(Process.get(:context_events), {scope, seq})
    |> case do
      nil -> nil
      event -> %{event: event}
    end
  end

  defp count_read, do: Process.put(:all_context_reads, Process.get(:all_context_reads, 0) + 1)
end

defmodule Beamlet.Agent.ContextReadOrderTest do
  use ExUnit.Case, async: true
  alias Beamlet.Agent.ContextBuilder
  alias Beamlet.Agent.ContextReadOrderRepo
  alias Beamlet.Agent.Reducer
  alias Beamlet.Agent.Storage.Codec
  @id "12345678-1234-1234-1234-123456789abc"
  @op "12345678-1234-1234-1234-123456789abd"

  test "overflow stops before missing or corrupt suffix with the baseline read count" do
    payload = %{"text" => String.duplicate("x", 65_536)}
    {:ok, digest} = Codec.digest(payload, :event)
    event = %{"id" => @id, "type" => "input.accepted", "payload" => payload}
    source = %{"type" => "input", "event_id" => @id, "seq" => 2, "digest" => digest}

    for suffix <- [nil, %{event | "payload" => %{"text" => "corrupt"}}, event],
        method <- [:build, :materialize] do
      Process.put(:context_reads, [])
      Process.put(:all_context_reads, 0)
      Process.put(:context_events, %{{@id, 2} => event, {@id, 999} => suffix})

      control = %{
        Reducer.new(@id)
        | "timeline" => List.duplicate(source, 127) ++ [Map.put(source, "seq", 999)]
      }

      assert {:error, :context_limit} = invoke(method, control)
      assert Process.get(:context_reads) == List.duplicate({@id, 2}, 16)
      assert Process.get(:all_context_reads) == 16
    end
  end

  test "historical invalid model reply stops before missing suffix" do
    description = %{"payload" => %{"request" => %{"catalogue" => %{}}}}

    result = %{
      "status" => "ok",
      "value" => %{"kind" => "unsupported", "content" => "bad", "calls" => []}
    }

    {:ok, description_digest} = Codec.digest(description, :operation)
    {:ok, accepted_digest} = Codec.digest(result, :result)

    ref = %{
      "operation_id" => @op,
      "accepted_digest" => accepted_digest,
      "consumption_kind" => "model_result"
    }

    source = %{
      "type" => "inherited_result",
      "source_agent_id" => @id,
      "description_digest" => description_digest,
      "reference" => ref,
      "resolution" => nil
    }

    Process.put(:operation, %{
      "id" => @op,
      "role" => "model",
      "description_digest" => description_digest,
      "description" => description,
      "accepted_result" => result
    })

    Process.put(:context_events, %{
      {@op, 1} => %{
        "type" => "operation.prepared",
        "schema_version" => 1,
        "payload" => %{"description_digest" => description_digest}
      },
      {@op, 2} => %{
        "type" => "operation.result_accepted",
        "schema_version" => 1,
        "payload" => %{"accepted_digest" => accepted_digest}
      }
    })

    missing = %{"type" => "input", "event_id" => @id, "seq" => 999, "digest" => accepted_digest}
    control = %{Reducer.new(@id) | "timeline" => [source, missing]}

    for method <- [:build, :materialize] do
      Process.put(:context_reads, [])
      Process.put(:all_context_reads, 0)
      assert {:error, :invalid_reply} = invoke(method, control)
      assert Process.get(:context_reads) == [{@op, 1}, {@op, 2}]
      assert Process.get(:all_context_reads) == 4
    end
  end

  defp invoke(:build, control), do: ContextBuilder.build(ContextReadOrderRepo, control, %{})

  defp invoke(:materialize, control),
    do: ContextBuilder.materialize(ContextReadOrderRepo, control)
end

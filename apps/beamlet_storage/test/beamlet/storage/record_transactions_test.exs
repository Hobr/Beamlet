defmodule Beamlet.Storage.RecordTransactionsTest do
  use ExUnit.Case, async: false

  alias Beamlet.Storage.{
    Codec,
    ContractFixture,
    Dataset,
    ExecutorJournal,
    ExecutorJournalRepo,
    TerminalArtifacts
  }

  @journal ExecutorJournalRepo

  setup do
    fixture = ContractFixture.open(:sqlite)

    opts = [
      database: fixture.opts[:peer_database],
      peer_database: fixture.opts[:database],
      dataset_id: Ecto.UUID.generate()
    ]

    {:ok, _} = Dataset.initialize(@journal, opts)

    on_exit(fn ->
      try do
        @journal.stop()
      catch
        :exit, _ -> :ok
      end

      ContractFixture.close(fixture)
    end)

    %{authority_id: fixture.authority_id}
  end

  defp start(authority_id) do
    %{
      id: Ecto.UUID.generate(),
      authority_id: authority_id,
      operation_id: Ecto.UUID.generate(),
      attempt_id: Ecto.UUID.generate(),
      executor_id: Ecto.UUID.generate(),
      executor_boot_id: Ecto.UUID.generate(),
      description_digest: Codec.hash("{}")
    }
  end

  defp container(items \\ %{}), do: %{"version" => 1, "items" => items}

  defp item(bytes),
    do: %{
      "digest" => Codec.hash(bytes),
      "media_type" => "application/octet-stream",
      "size_bytes" => byte_size(bytes),
      "content_base64" => Base.encode64(bytes)
    }

  defp terminal(attrs) do
    receipt = %{"receipt_id" => Ecto.UUID.generate(), "kind" => "terminal"}
    {:ok, digest} = Codec.digest(receipt, :event)

    %{
      authority_id: attrs.authority_id,
      attempt_id: attrs.attempt_id,
      expected_version: 0,
      termination: %{"origin" => "execution", "status" => "ok"},
      terminal_result: %{"status" => "success", "output" => %{"stdout" => "done"}},
      terminal_artifacts: container(),
      receipt_id: receipt["receipt_id"],
      receipt_digest: digest,
      receipt: receipt
    }
  end

  test "insert once and restart unknown never restarts or becomes terminal", %{
    authority_id: authority_id
  } do
    attrs = start(authority_id)

    assert {:ok, %{"state" => "start_intent"} = stored} =
             ExecutorJournal.claim_start(@journal, attrs)

    assert {:ok, ^stored} = ExecutorJournal.claim_start(@journal, attrs)

    assert {:error, :conflict} =
             ExecutorJournal.claim_start(@journal, %{
               attrs
               | description_digest: Codec.hash("other")
             })

    assert {:error, :conflict} =
             ExecutorJournal.claim_start(@journal, %{
               attrs
               | executor_boot_id: Ecto.UUID.generate()
             })

    assert {:ok, %{"marked" => 1}} =
             ExecutorJournal.mark_unknown_after_restart(@journal, %{
               authority_id: authority_id,
               executor_id: attrs.executor_id,
               keep_executor_boot_id: Ecto.UUID.generate()
             })

    assert {:ok, %{"state" => "unknown_after_restart"}} =
             ExecutorJournal.claim_start(@journal, attrs)

    assert {:error, :conflict} =
             ExecutorJournal.record_terminal(@journal, %{terminal(attrs) | expected_version: 1})

    assert {:ok, %{"state" => "unknown_after_restart"}} =
             ExecutorJournal.fetch(@journal, authority_id, attrs.attempt_id)
  end

  test "first stop survives competing triggers", %{authority_id: authority_id} do
    attrs = start(authority_id)
    {:ok, _} = ExecutorJournal.claim_start(@journal, attrs)

    stop = %{
      authority_id: authority_id,
      attempt_id: attrs.attempt_id,
      expected_version: 0,
      stop_reason: "deadline"
    }

    assert {:ok, %{"stop_reason" => "deadline", "lock_version" => 1}} =
             ExecutorJournal.record_stop(@journal, stop)

    assert {:ok, %{"stop_reason" => "deadline"}} =
             ExecutorJournal.record_stop(@journal, %{
               stop
               | stop_reason: "cancelled",
                 expected_version: 1
             })

    assert {:ok, %{"stop_reason" => "deadline", "lock_version" => 1}} =
             ExecutorJournal.fetch(@journal, authority_id, attrs.attempt_id)
  end

  test "terminal attachments and receipt commit once with idempotent acknowledgement", %{
    authority_id: authority_id
  } do
    attrs = start(authority_id)
    {:ok, _} = ExecutorJournal.claim_start(@journal, attrs)
    bytes = :crypto.strong_rand_bytes(48)
    id = Ecto.UUID.generate()
    terminal = %{terminal(attrs) | terminal_artifacts: container(%{id => item(bytes)})}

    assert {:ok, %{"state" => "terminal", "lock_version" => 1} = response} =
             ExecutorJournal.record_terminal(@journal, terminal)

    assert {:ok, ^response} = ExecutorJournal.record_terminal(@journal, terminal)

    assert {:error, :conflict} =
             ExecutorJournal.record_terminal(@journal, %{
               terminal
               | terminal_artifacts: container()
             })

    ack = %{authority_id: authority_id, attempt_id: attrs.attempt_id, expected_version: 1}
    assert {:ok, %{"acknowledged" => true}} = ExecutorJournal.acknowledge(@journal, ack)
    assert {:ok, %{"acknowledged" => true}} = ExecutorJournal.acknowledge(@journal, ack)
    assert {:ok, stored} = ExecutorJournal.fetch(@journal, authority_id, attrs.attempt_id)
    assert stored["state"] == "terminal"
    assert stored["terminal_result"]["status"] == "success"
    assert {:ok, ^bytes} = TerminalArtifacts.content(stored["terminal_artifacts"], id)
  end

  test "malformed attachments reject and do not consume terminal transition", %{
    authority_id: authority_id
  } do
    attrs = start(authority_id)
    {:ok, _} = ExecutorJournal.claim_start(@journal, attrs)
    bytes = <<0, 255, 1>>

    for bad <- [
          container(%{
            Ecto.UUID.generate() => %{item(bytes) | "content_base64" => "not base64!"}
          }),
          container(%{
            Ecto.UUID.generate() => %{item(bytes) | "digest" => String.duplicate("0", 64)}
          }),
          container(%{Ecto.UUID.generate() => %{item(bytes) | "size_bytes" => 99}}),
          container(%{"not-a-uuid" => item(bytes)}),
          container(Map.new(1..65, fn i -> {Ecto.UUID.generate(), item(<<i>>)} end))
        ] do
      assert {:error, reason} =
               ExecutorJournal.record_terminal(@journal, %{
                 terminal(attrs)
                 | terminal_artifacts: bad
               })

      assert reason in [:invalid_data, :limit]
    end

    assert {:ok, _} =
             ExecutorJournal.record_terminal(@journal, %{
               terminal(attrs)
               | terminal_artifacts: container(%{Ecto.UUID.generate() => item(bytes)})
             })

    huge = String.duplicate("x", 4_100_000)
    receipt = %{"receipt_id" => Ecto.UUID.generate(), "detail" => huge}
    {:ok, digest} = Codec.digest(receipt, :event)

    over = %{
      terminal(attrs)
      | attempt_id: Ecto.UUID.generate(),
        termination: %{"origin" => "execution", "detail" => huge},
        terminal_result: %{"status" => "success", "output" => %{"stdout" => huge}},
        terminal_artifacts:
          container(%{Ecto.UUID.generate() => item(:binary.copy(<<1>>, 16_000_000))}),
        receipt_id: receipt["receipt_id"],
        receipt: receipt,
        receipt_digest: digest
    }

    assert {:error, :limit} = ExecutorJournal.record_terminal(@journal, over)
  end

  test "attachment protocol raw and encoded limits", _ do
    assert {:ok, _} = TerminalArtifacts.encode(container())
    id = Ecto.UUID.generate()
    bytes = :crypto.strong_rand_bytes(1024)
    good = container(%{id => item(bytes)})
    assert {:ok, _} = TerminalArtifacts.encode(good)
    assert {:ok, ^bytes} = TerminalArtifacts.content(good, id)
    assert {:error, :artifact_missing} = TerminalArtifacts.content(good, Ecto.UUID.generate())

    for bad <- [
          %{"version" => 2, "items" => %{}},
          container(%{id => %{}}),
          %{"version" => 1},
          container(%{id => Map.put(item(bytes), "extra", true)})
        ] do
      assert {:error, :invalid_data} = TerminalArtifacts.encode(bad)
    end

    chunk = :binary.copy(<<7>>, 9_000_000)

    assert {:error, :limit} =
             TerminalArtifacts.encode(
               container(%{id => item(chunk), Ecto.UUID.generate() => item(chunk)})
             )

    assert {:error, :limit} =
             TerminalArtifacts.encode(container(%{id => item(:binary.copy(<<7>>, 16_777_217))}))

    assert {:ok, size} =
             TerminalArtifacts.encoded_size(
               container(%{id => item(:binary.copy(<<3>>, 16_000_000))})
             )

    assert size <= Codec.limit(:journal_artifacts)
    assert {:ok, _} = TerminalArtifacts.encode(container(%{id => item(<<0, 255, 254, 1>>)}))
  end
end

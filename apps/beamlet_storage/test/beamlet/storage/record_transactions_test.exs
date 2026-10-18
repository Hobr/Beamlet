defmodule Beamlet.Storage.RecordTestSupport do
  @moduledoc false
  alias Beamlet.Storage.{Codec, Dataset, ExecutorJournalRepo, SQLiteAuthorityRepo}

  def start_datasets do
    dir = Path.join(System.tmp_dir!(), "beamlet-records-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    authority = [
      database: Path.join(dir, "authority.db"),
      peer_database: Path.join(dir, "journal.db"),
      dataset_id: Ecto.UUID.generate()
    ]

    journal =
      [
        database: authority[:peer_database],
        peer_database: authority[:database],
        dataset_id: Ecto.UUID.generate()
      ]

    {:ok, _} = Dataset.initialize(SQLiteAuthorityRepo, authority)
    {:ok, _} = Dataset.initialize(ExecutorJournalRepo, journal)

    %{dir: dir, authority: authority, journal: journal, authority_id: authority[:dataset_id]}
  end

  def stop_datasets(%{dir: dir}) do
    for repo <- [ExecutorJournalRepo, SQLiteAuthorityRepo] do
      try do
        repo.stop()
      catch
        _, _ -> :ok
      end
    end

    File.rm_rf!(dir)
  end

  def command(params, scope_id \\ nil) do
    %{
      scope_id: scope_id || Ecto.UUID.generate(),
      command_id: Ecto.UUID.generate(),
      params: params
    }
  end

  def create_attrs(authority_id, overrides \\ %{}) do
    agent_id = Ecto.UUID.generate()

    Map.merge(
      %{
        command: command(%{"op" => "create_agent", "agent_id" => agent_id}, agent_id),
        id: agent_id,
        authority_id: authority_id,
        definition: %{"provider" => "native", "profile" => "default"},
        generation: 0,
        checkpoint: %{
          id: Ecto.UUID.generate(),
          data: %{"messages" => [], "continuation" => "await_input"},
          safe_to_fork: true
        },
        event: %{id: Ecto.UUID.generate(), type: "agent.created", payload: %{"alias" => nil}}
      },
      overrides
    )
  end

  def input_attrs(agent_id, turn_id, version, overrides \\ %{}) do
    Map.merge(
      %{
        command: command(%{"op" => "accept_input", "turn_id" => turn_id}),
        agent_id: agent_id,
        expected_version: version,
        expected_generation: 0,
        turn_id: turn_id,
        checkpoint: %{
          id: Ecto.UUID.generate(),
          data: %{"messages" => [%{"role" => "user", "content" => "hi"}], "turn_id" => turn_id},
          continuation: "model_prepared",
          safe_to_fork: false
        },
        event: %{
          id: Ecto.UUID.generate(),
          type: "input.accepted",
          payload: %{"text" => "hi"}
        }
      },
      overrides
    )
  end

  def operation_attrs(id, overrides \\ %{}) do
    Map.merge(
      %{
        operation: %{
          id: id,
          description: %{
            "kind" => "tool_call",
            "protocol_version" => 1,
            "payload" => %{"tool" => "echo", "arguments" => %{"text" => "hi"}}
          }
        }
      },
      overrides
    )
  end

  def attempt_attrs do
    %{
      attempt_id: Ecto.UUID.generate(),
      executor_id: Ecto.UUID.generate(),
      executor_boot_id: Ecto.UUID.generate(),
      budget: %{"milliseconds" => 5000}
    }
  end

  def event(type, payload \\ %{}) do
    %{id: Ecto.UUID.generate(), type: type, payload: payload}
  end

  def artifact_item(bytes) do
    %{
      "digest" => Codec.hash(bytes),
      "media_type" => "application/octet-stream",
      "size_bytes" => byte_size(bytes),
      "content_base64" => Base.encode64(bytes)
    }
  end

  def container(items \\ %{}) do
    %{"version" => 1, "items" => items}
  end

  def journal_start(authority_id, overrides \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        authority_id: authority_id,
        operation_id: Ecto.UUID.generate(),
        attempt_id: Ecto.UUID.generate(),
        description_digest: Codec.hash("{}"),
        executor_id: Ecto.UUID.generate(),
        executor_boot_id: Ecto.UUID.generate()
      },
      overrides
    )
  end

  def terminal_attrs(authority_id, attempt_id, version, overrides \\ %{}) do
    receipt = %{"receipt_id" => Ecto.UUID.generate(), "kind" => "terminal"}

    base = %{
      authority_id: authority_id,
      attempt_id: attempt_id,
      expected_version: version,
      termination: %{"origin" => "execution", "status" => "ok"},
      terminal_result: %{"status" => "success", "output" => %{"stdout" => "done"}},
      terminal_artifacts: container(),
      receipt_id: receipt["receipt_id"],
      receipt: receipt
    }

    {:ok, digest} = Codec.digest(receipt, :event)
    Map.merge(Map.put(base, :receipt_digest, digest), overrides)
  end
end

defmodule Beamlet.Storage.RecordTransactionsTest do
  use ExUnit.Case, async: false

  import Beamlet.Storage.RecordTestSupport

  alias Beamlet.Storage.{
    AgentRecords,
    Artifacts,
    Codec,
    ExecutorJournal,
    ExecutorJournalRepo,
    OperationRecords,
    SQLiteAuthorityRepo,
    TerminalArtifacts,
    Transaction
  }

  alias Ecto.Adapters.SQL

  @repo SQLiteAuthorityRepo
  @journal ExecutorJournalRepo

  setup do
    context = start_datasets()
    on_exit(fn -> stop_datasets(context) end)
    context
  end

  defp agent!(context, overrides \\ %{}) do
    attrs = create_attrs(context.authority_id, overrides)
    {:ok, response} = AgentRecords.create_agent(@repo, attrs)
    {response, attrs}
  end

  defp input!(agent_id, turn_id, version) do
    attrs = input_attrs(agent_id, turn_id, version)
    {:ok, response} = AgentRecords.accept_input(@repo, attrs)
    {response, attrs}
  end

  defp owned_operation!(agent_id, turn_id, version, ordinal) do
    operation_id = Ecto.UUID.generate()

    attrs =
      operation_attrs(operation_id, %{
        operation: %{
          id: operation_id,
          description: %{
            "kind" => "tool_call",
            "protocol_version" => 1,
            "payload" => %{"tool" => "echo", "ordinal" => ordinal}
          },
          owner_agent_id: agent_id,
          turn_id: turn_id,
          tool_call_id: "call-#{ordinal}",
          ordinal: ordinal
        },
        event: event("operation.prepared", %{"ordinal" => ordinal}),
        agent: %{expected_version: version, expected_generation: 0}
      })

    {:ok, response} = OperationRecords.prepare(@repo, attrs)
    {response, attrs}
  end

  ## Agent creation

  test "create_agent commits checkpoint, history and command once", %{authority_id: authority_id} do
    attrs = create_attrs(authority_id)

    assert {:ok, %{"agent_id" => id, "history_seq" => 1, "lock_version" => 0} = response} =
             AgentRecords.create_agent(@repo, attrs)

    assert {:ok, ^response} = AgentRecords.create_agent(@repo, attrs)

    assert {:ok, fetched} = AgentRecords.fetch(@repo, id)
    assert fetched["agent"]["head_checkpoint_id"] == attrs.checkpoint.id
    assert fetched["head_checkpoint"]["continuation"] == "await_input"
    assert fetched["head_checkpoint"]["safe_to_fork"] == true

    assert fetched["head_checkpoint"]["digest"] ==
             elem(Codec.digest(attrs.checkpoint.data, :checkpoint), 1)

    assert [[1]] == count("SELECT COUNT(*) FROM events")
    assert [[1]] == count("SELECT COUNT(*) FROM commands")

    # Same command identity with different parameters is a conflict, not a replay.
    changed = put_in(attrs, [:command, :params], %{"op" => "create_agent", "other" => true})
    assert {:error, :conflict} = AgentRecords.create_agent(@repo, changed)
  end

  test "create_agent rolls back every table when the checkpoint collides", %{
    authority_id: authority_id
  } do
    {first, first_attrs} = agent!(%{authority_id: authority_id})

    duplicate =
      create_attrs(authority_id, %{checkpoint: first_attrs.checkpoint})

    assert {:error, :conflict} = AgentRecords.create_agent(@repo, duplicate)
    assert {:error, :conflict} = AgentRecords.fetch(@repo, duplicate.id)
    assert [[0]] == count("SELECT COUNT(*) FROM events WHERE scope_id = '#{duplicate.id}'")
    assert [[1]] == count("SELECT COUNT(*) FROM agents")
    assert {:ok, _} = AgentRecords.fetch(@repo, first["agent_id"])
  end

  ## Input acceptance

  test "accept_input CASes version and generation and dedupes the command", %{
    authority_id: authority_id
  } do
    {agent, _} = agent!(%{authority_id: authority_id})
    turn_id = Ecto.UUID.generate()
    attrs = input_attrs(agent["agent_id"], turn_id, 0)

    assert {:ok, %{"history_seq" => 2, "lock_version" => 1} = response} =
             AgentRecords.accept_input(@repo, attrs)

    assert {:ok, ^response} = AgentRecords.accept_input(@repo, attrs)

    assert {:error, :stale_generation} =
             AgentRecords.accept_input(
               @repo,
               input_attrs(agent["agent_id"], Ecto.UUID.generate(), 0)
               |> Map.put(:expected_generation, 1)
             )

    assert {:error, :conflict} =
             AgentRecords.accept_input(
               @repo,
               input_attrs(agent["agent_id"], Ecto.UUID.generate(), 0)
             )

    assert {:error, :conflict} =
             AgentRecords.accept_input(
               @repo,
               input_attrs(agent["agent_id"], turn_id, 1)
             )

    assert {:error, :conflict} =
             AgentRecords.accept_input(
               @repo,
               input_attrs(Ecto.UUID.generate(), Ecto.UUID.generate(), 0)
             )

    assert {:ok, fetched} = AgentRecords.fetch(@repo, agent["agent_id"])
    assert fetched["agent"]["lock_version"] == 1
    assert fetched["head_checkpoint"]["turn_id"] == turn_id
    assert [[2]] == count("SELECT COUNT(*) FROM events")
  end

  ## Consumption

  test "consume_result orders joins by ordinal, dedupes once and rejects foreign owners", %{
    authority_id: authority_id
  } do
    {agent, _} = agent!(%{authority_id: authority_id})
    turn_id = Ecto.UUID.generate()
    {%{"lock_version" => 1} = _input_response, _attrs} = input!(agent["agent_id"], turn_id, 0)

    {high, _} = owned_operation!(agent["agent_id"], turn_id, 1, 2)
    {low, _} = owned_operation!(agent["agent_id"], turn_id, 2, 1)

    # Accept the later ordinal first: history order is not arrival order.
    {:ok, _} =
      OperationRecords.accept_result(@repo, %{
        operation_id: high["operation_id"],
        expected_version: 0,
        result: %{"status" => "success", "output" => %{"tool" => "echo"}},
        event: event("result.accepted", %{"operation_id" => high["operation_id"]}),
        agent: %{expected_version: 3, expected_generation: 0}
      })

    {:ok, _} =
      OperationRecords.accept_result(@repo, %{
        operation_id: low["operation_id"],
        expected_version: 0,
        result: %{"status" => "success", "output" => %{"tool" => "echo"}},
        event: event("result.accepted", %{"operation_id" => low["operation_id"]}),
        agent: %{expected_version: 4, expected_generation: 0}
      })

    consume = %{
      agent_id: agent["agent_id"],
      expected_version: 5,
      expected_generation: 0,
      turn_id: turn_id,
      operations: [
        %{operation_id: high["operation_id"], consumption_kind: "tool_result"},
        %{operation_id: low["operation_id"], consumption_kind: "tool_result"}
      ],
      checkpoint: %{
        id: Ecto.UUID.generate(),
        data: %{"messages" => [%{"role" => "tool", "content" => "echo"}], "turn_id" => turn_id},
        continuation: "results_to_consume",
        safe_to_fork: false
      }
    }

    assert {:ok, %{"consumed" => consumed, "history_seq" => 8, "lock_version" => 6}} =
             AgentRecords.consume_result(@repo, consume)

    assert Enum.map(consumed, & &1["operation_id"]) == [low["operation_id"], high["operation_id"]]
    assert Enum.map(consumed, & &1["seq"]) == [7, 8]

    {:ok, page} = AgentRecords.history_page(@repo, agent["agent_id"])
    joins = Enum.filter(page["events"], &(&1["type"] == "result.consumed"))
    assert Enum.map(joins, & &1["seq"]) == [7, 8]

    assert Enum.map(joins, & &1["payload"]["operation_id"]) == [
             low["operation_id"],
             high["operation_id"]
           ]

    assert Enum.map(joins, & &1["payload"]["ordinal"]) == [1, 2]

    # Exactly-once: the same batch with a stale version replays stored events.
    assert {:ok, replay} = AgentRecords.consume_result(@repo, consume)
    assert replay["consumed"] == consumed
    assert [[2]] == count("SELECT COUNT(*) FROM events WHERE type = 'result.consumed'")

    # A different Agent cannot consume the source Agent's Operation.
    {other, _} = agent!(%{authority_id: authority_id})
    other_turn = Ecto.UUID.generate()
    input!(other["agent_id"], other_turn, 0)

    assert {:error, :conflict} =
             AgentRecords.consume_result(@repo, %{
               consume
               | agent_id: other["agent_id"],
                 turn_id: other_turn,
                 expected_version: 1
             })

    assert {:ok, other_fetched} = AgentRecords.fetch(@repo, other["agent_id"])
    assert other_fetched["agent"]["lock_version"] == 1
    assert other_fetched["agent"]["history_seq"] == 2
  end

  test "consume_result rejects unaccepted and foreign-turn Operations", %{
    authority_id: authority_id
  } do
    {agent, _} = agent!(%{authority_id: authority_id})
    turn_id = Ecto.UUID.generate()
    input!(agent["agent_id"], turn_id, 0)
    {operation, _} = owned_operation!(agent["agent_id"], turn_id, 1, 1)

    consume = %{
      agent_id: agent["agent_id"],
      expected_version: 2,
      expected_generation: 0,
      turn_id: turn_id,
      operations: [%{operation_id: operation["operation_id"], consumption_kind: "tool_result"}],
      checkpoint: %{
        id: Ecto.UUID.generate(),
        data: %{"messages" => []},
        continuation: "results_to_consume",
        safe_to_fork: false
      }
    }

    assert {:error, :conflict} = AgentRecords.consume_result(@repo, consume)

    consume = %{
      consume
      | turn_id: Ecto.UUID.generate(),
        operations: [%{operation_id: Ecto.UUID.generate(), consumption_kind: "tool_result"}]
    }

    assert {:error, :conflict} = AgentRecords.consume_result(@repo, consume)
    assert [[0]] == count("SELECT COUNT(*) FROM events WHERE type = 'result.consumed'")
  end

  ## Pagination

  test "history_page bounds pages and cursors", %{authority_id: authority_id} do
    {agent, _} = agent!(%{authority_id: authority_id})
    input!(agent["agent_id"], Ecto.UUID.generate(), 0)

    assert {:ok, %{"events" => [first], "next_cursor" => 1}} =
             AgentRecords.history_page(@repo, agent["agent_id"], limit: 1)

    assert first["seq"] == 1

    assert {:ok, %{"events" => [second], "next_cursor" => 2}} =
             AgentRecords.history_page(@repo, agent["agent_id"], after_seq: 1, limit: 1)

    assert second["seq"] == 2

    assert {:ok, %{"events" => [], "next_cursor" => nil}} =
             AgentRecords.history_page(@repo, agent["agent_id"], after_seq: 2)

    assert {:error, :invalid_data} = AgentRecords.history_page(@repo, agent["agent_id"], limit: 0)
    assert {:error, :limit} = AgentRecords.history_page(@repo, agent["agent_id"], limit: 501)
    assert {:error, :invalid_data} = AgentRecords.history_page(@repo, agent["agent_id"], bogus: 1)
    assert {:error, :invalid_data} = AgentRecords.history_page(@repo, "not-a-uuid")
    assert {:error, :invalid_data} = AgentRecords.history_page(@repo, agent["agent_id"], "nope")
  end

  ## Preparation and dispatch

  test "prepare is idempotent per Operation identity and creates at most one attempt", %{
    authority_id: _authority_id
  } do
    operation_id = Ecto.UUID.generate()
    attempt = attempt_attrs()

    attrs =
      operation_attrs(operation_id, %{attempt: attempt, event: event("operation.prepared")})

    assert {:ok, %{"attempt_id" => attempt_id, "dispatch_state" => "prepared"} = response} =
             OperationRecords.prepare(@repo, attrs)

    assert attempt_id == attempt.attempt_id
    assert {:ok, ^response} = OperationRecords.prepare(@repo, attrs)

    changed =
      operation_attrs(operation_id, %{
        operation: %{
          id: operation_id,
          description: %{"kind" => "other", "protocol_version" => 1, "payload" => %{}}
        },
        attempt: attempt,
        event: event("operation.prepared")
      })

    assert {:error, :conflict} = OperationRecords.prepare(@repo, changed)

    second_attempt =
      operation_attrs(operation_id, %{
        attempt: attempt_attrs(),
        event: event("operation.prepared")
      })

    assert {:error, :conflict} = OperationRecords.prepare(@repo, second_attempt)

    assert {:ok, fetched} = OperationRecords.fetch(@repo, operation_id)
    assert fetched["operation"]["history_seq"] == 1
    assert fetched["attempt"]["attempt_id"] == attempt.attempt_id
    assert [[1]] == count("SELECT COUNT(*) FROM executions")
  end

  test "prepare rejects credential structs and unknown description fields", %{
    authority_id: _authority_id
  } do
    base = %{
      attempt: attempt_attrs(),
      event: event("operation.prepared")
    }

    for description <- [
          %{
            "kind" => "x",
            "protocol_version" => 1,
            "payload" => %{},
            "credentials" => %{"k" => "v"}
          },
          %{"kind" => "x", "protocol_version" => 0, "payload" => %{}},
          %{"kind" => "x", "protocol_version" => 1},
          %{"kind" => "x", "protocol_version" => 1, "payload" => %{"live" => self()}}
        ] do
      assert {:error, _} =
               OperationRecords.prepare(
                 @repo,
                 Map.merge(
                   base,
                   operation_attrs(Ecto.UUID.generate(), %{description: description})
                 )
               )
    end

    assert [[0]] == count("SELECT COUNT(*) FROM operations")
  end

  test "claim_dispatch CASes prepared to send_claimed and refuses a second claim", %{
    authority_id: _authority_id
  } do
    attempt = attempt_attrs()

    {:ok, prepared} =
      OperationRecords.prepare(
        @repo,
        operation_attrs(Ecto.UUID.generate(), %{
          attempt: attempt,
          event: event("operation.prepared")
        })
      )

    claim = %{
      operation_id: prepared["operation_id"],
      attempt_id: attempt.attempt_id,
      expected_version: 0
    }

    assert {:ok, %{"dispatch_state" => "send_claimed", "lock_version" => 1} = claimed} =
             OperationRecords.claim_dispatch(@repo, claim)

    assert claimed["executor_id"] == attempt.executor_id
    assert {:error, :conflict} = OperationRecords.claim_dispatch(@repo, claim)

    assert {:error, :invalid_data} =
             OperationRecords.claim_dispatch(@repo, %{
               claim
               | operation_id: Ecto.UUID.generate(),
                 expected_version: 1
             })

    assert [[1]] == count("SELECT COUNT(*) FROM executions WHERE dispatch_state = 'send_claimed'")
  end

  test "claim_dispatch has exactly one winner under real connection competition", %{
    authority: authority
  } do
    attempt = attempt_attrs()

    {:ok, prepared} =
      OperationRecords.prepare(
        @repo,
        operation_attrs(Ecto.UUID.generate(), %{
          attempt: attempt,
          event: event("operation.prepared")
        })
      )

    claim = %{
      operation_id: prepared["operation_id"],
      attempt_id: attempt.attempt_id,
      expected_version: 0
    }

    {:ok, competitor} =
      SQLiteAuthorityRepo.start_link(authority ++ [name: :records_competitor, log: false])

    on_exit(fn ->
      try do
        SQLiteAuthorityRepo.stop(:records_competitor)
      catch
        _, _ -> :ok
      end
    end)

    tasks =
      for repo <- [:records_competitor, @repo] do
        Task.async(fn ->
          if repo != @repo, do: SQLiteAuthorityRepo.put_dynamic_repo(repo)
          OperationRecords.claim_dispatch(@repo, claim)
        end)
      end

    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :conflict}, &1)) == 1
    assert Process.alive?(competitor)

    {:ok, fetched} = OperationRecords.fetch(@repo, prepared["operation_id"])
    assert fetched["attempt"]["dispatch_state"] == "send_claimed"
    assert fetched["attempt"]["lock_version"] == 1
  end

  ## Evidence and acceptance

  test "record_evidence dedupes receipts and keeps the original digest on conflict", %{
    authority_id: _authority_id
  } do
    attempt = attempt_attrs()

    {:ok, prepared} =
      OperationRecords.prepare(
        @repo,
        operation_attrs(Ecto.UUID.generate(), %{
          attempt: attempt,
          event: event("operation.prepared")
        })
      )

    evidence = %{
      id: Ecto.UUID.generate(),
      operation_id: prepared["operation_id"],
      attempt_id: attempt.attempt_id,
      executor_id: attempt.executor_id,
      evidence_id: Ecto.UUID.generate(),
      content: %{"status" => "success", "output" => %{"stdout" => "done"}}
    }

    assert {:ok, %{"evidence_id" => id} = first} =
             OperationRecords.record_evidence(@repo, evidence)

    assert id == evidence.evidence_id
    assert {:ok, ^first} = OperationRecords.record_evidence(@repo, evidence)

    conflicting = %{evidence | content: %{"status" => "failed"}}
    assert {:error, :conflict} = OperationRecords.record_evidence(@repo, conflicting)

    assert [["success"]] ==
             SQL.query!(
               @repo,
               "SELECT json_extract(content, '$.status') FROM execution_evidence",
               [],
               log: false
             ).rows

    assert [[1]] == count("SELECT COUNT(*) FROM execution_evidence")

    assert {:error, :invalid_data} =
             OperationRecords.record_evidence(@repo, %{
               evidence
               | executor_id: Ecto.UUID.generate()
             })
  end

  test "accept_result is NULL to accepted only and resolves reference integrity", %{
    authority_id: _authority_id
  } do
    attempt = attempt_attrs()

    {:ok, prepared} =
      OperationRecords.prepare(
        @repo,
        operation_attrs(Ecto.UUID.generate(), %{
          attempt: attempt,
          event: event("operation.prepared")
        })
      )

    bytes = :crypto.strong_rand_bytes(64)

    artifact = %{
      id: Ecto.UUID.generate(),
      content: bytes,
      digest: Codec.hash(bytes),
      size: byte_size(bytes),
      media_type: "application/octet-stream",
      recorded_at: DateTime.utc_now()
    }

    assert {:error, :invalid_data} = Artifacts.put(@repo, artifact)

    attrs = %{
      operation_id: prepared["operation_id"],
      expected_version: 0,
      result: %{"status" => "success", "output" => %{"stdout" => "done"}},
      event: event("result.accepted", %{"operation_id" => prepared["operation_id"]})
    }

    assert {:error, :artifact_missing} =
             OperationRecords.accept_result(@repo, Map.put(attrs, :artifact_ids, [artifact.id]))

    assert {:ok, fetched} = OperationRecords.fetch(@repo, prepared["operation_id"])
    assert fetched["operation"]["accepted_result"] == nil
    assert [[0]] == count("SELECT COUNT(*) FROM events WHERE type = 'result.accepted'")

    assert {:ok, _} = Transaction.write(@repo, fn -> Artifacts.put(@repo, artifact) end)

    assert {:ok, accepted} =
             OperationRecords.accept_result(@repo, Map.put(attrs, :artifact_ids, [artifact.id]))

    assert accepted["accepted_result"] == attrs.result

    assert {:ok, ^accepted} =
             OperationRecords.accept_result(@repo, Map.put(attrs, :artifact_ids, [artifact.id]))

    late = %{attrs | result: %{"status" => "uncertain"}}
    assert {:error, :conflict} = OperationRecords.accept_result(@repo, late)

    {:ok, fetched} = OperationRecords.fetch(@repo, prepared["operation_id"])
    assert fetched["operation"]["accepted_result"] == attrs.result
    assert fetched["operation"]["history_seq"] == 2
  end

  test "accept_result rejects a dangling evidence reference and keeps the Result empty", %{
    authority_id: _authority_id
  } do
    attempt = attempt_attrs()

    {:ok, prepared} =
      OperationRecords.prepare(
        @repo,
        operation_attrs(Ecto.UUID.generate(), %{
          attempt: attempt,
          event: event("operation.prepared")
        })
      )

    assert {:error, :conflict} =
             OperationRecords.accept_result(@repo, %{
               operation_id: prepared["operation_id"],
               expected_version: 0,
               result: %{"status" => "success"},
               evidence_id: Ecto.UUID.generate(),
               event: event("result.accepted")
             })

    assert {:ok, fetched} = OperationRecords.fetch(@repo, prepared["operation_id"])
    assert fetched["operation"]["accepted_result"] == nil
  end

  ## Journal

  test "claim_start is insert-once and restart-unknown is terminal-unknown, not absent", %{
    authority_id: authority_id
  } do
    attrs = journal_start(authority_id)

    assert {:ok, %{"state" => "start_intent", "record_id" => record_id}} =
             ExecutorJournal.claim_start(@journal, attrs)

    assert {:ok, %{"state" => "start_intent", "record_id" => ^record_id}} =
             ExecutorJournal.claim_start(@journal, attrs)

    assert {:error, :conflict} =
             ExecutorJournal.claim_start(
               @journal,
               %{attrs | description_digest: Codec.hash("{\"other\":1}")}
             )

    assert {:error, :conflict} =
             ExecutorJournal.claim_start(
               @journal,
               %{attrs | executor_boot_id: Ecto.UUID.generate()}
             )

    assert {:ok, %{"marked" => 1}} =
             ExecutorJournal.mark_unknown_after_restart(@journal, %{
               authority_id: authority_id,
               executor_id: attrs.executor_id,
               keep_executor_boot_id: Ecto.UUID.generate()
             })

    assert {:ok, %{"state" => "unknown_after_restart", "record_id" => ^record_id}} =
             ExecutorJournal.claim_start(@journal, attrs)

    assert {:error, :conflict} =
             ExecutorJournal.record_terminal(
               @journal,
               terminal_attrs(authority_id, attrs.attempt_id, 1)
             )

    assert {:ok, %{"state" => "unknown_after_restart"}} =
             ExecutorJournal.fetch(
               @journal,
               authority_id,
               attrs.attempt_id
             )
  end

  test "first recorded stop cause survives competing triggers", %{authority_id: authority_id} do
    attrs = journal_start(authority_id)
    {:ok, _} = ExecutorJournal.claim_start(@journal, attrs)

    stop = %{
      authority_id: authority_id,
      attempt_id: attrs.attempt_id,
      stop_reason: "deadline",
      expected_version: 0
    }

    assert {:ok, %{"stop_reason" => "deadline", "lock_version" => 1}} =
             ExecutorJournal.record_stop(@journal, stop)

    competing = %{stop | stop_reason: "cancelled", expected_version: 1}

    assert {:ok, %{"stop_reason" => "deadline"}} =
             ExecutorJournal.record_stop(@journal, competing)

    assert {:ok, stored} =
             ExecutorJournal.fetch(
               @journal,
               authority_id,
               attrs.attempt_id
             )

    assert stored["stop_reason"] == "deadline"
    assert stored["lock_version"] == 1
  end

  test "record_terminal and acknowledge commit receipt facts once", %{
    authority_id: authority_id
  } do
    attrs = journal_start(authority_id)
    {:ok, _} = ExecutorJournal.claim_start(@journal, attrs)

    terminal = terminal_attrs(authority_id, attrs.attempt_id, 0)
    bytes = :crypto.strong_rand_bytes(48)

    terminal = %{
      terminal
      | terminal_artifacts: container(%{Ecto.UUID.generate() => artifact_item(bytes)})
    }

    assert {:ok, %{"state" => "terminal", "lock_version" => 1} = response} =
             ExecutorJournal.record_terminal(@journal, terminal)

    assert {:ok, ^response} =
             ExecutorJournal.record_terminal(@journal, terminal)

    conflicting =
      terminal_attrs(authority_id, attrs.attempt_id, 1, %{
        terminal_artifacts: container(%{Ecto.UUID.generate() => artifact_item(bytes)})
      })

    assert {:error, :conflict} =
             ExecutorJournal.record_terminal(@journal, conflicting)

    ack = %{authority_id: authority_id, attempt_id: attrs.attempt_id, expected_version: 1}

    assert {:ok, %{"acknowledged" => true}} =
             ExecutorJournal.acknowledge(@journal, ack)

    assert {:ok, %{"acknowledged" => true}} =
             ExecutorJournal.acknowledge(@journal, ack)

    assert {:ok, stored} =
             ExecutorJournal.fetch(
               @journal,
               authority_id,
               attrs.attempt_id
             )

    assert stored["state"] == "terminal"
    assert stored["terminal_result"]["status"] == "success"
    assert stored["acknowledged"] == true

    assert {:ok, content} =
             TerminalArtifacts.content(
               stored["terminal_artifacts"],
               hd(Map.keys(stored["terminal_artifacts"]["items"]))
             )

    assert content == bytes
  end

  test "record_terminal rejects invalid attachment data and the stored transaction budget", %{
    authority_id: authority_id
  } do
    attrs = journal_start(authority_id)
    {:ok, _} = ExecutorJournal.claim_start(@journal, attrs)
    bytes = <<0, 255, 1>>

    good = %{Ecto.UUID.generate() => artifact_item(bytes)}

    bad_base64 =
      container(%{
        Ecto.UUID.generate() => %{artifact_item(bytes) | "content_base64" => "not base64!"}
      })

    bad_digest =
      container(%{
        Ecto.UUID.generate() => %{artifact_item(bytes) | "digest" => String.duplicate("0", 64)}
      })

    bad_size =
      container(%{Ecto.UUID.generate() => %{artifact_item(bytes) | "size_bytes" => 99}})

    bad_key = container(%{"not-a-uuid" => artifact_item(bytes)})

    too_many = container(Map.new(1..65, fn i -> {Ecto.UUID.generate(), artifact_item(<<i>>)} end))

    for artifacts <- [bad_base64, bad_digest, bad_size, bad_key, too_many] do
      assert {:error, reason} =
               ExecutorJournal.record_terminal(
                 @journal,
                 terminal_attrs(authority_id, attrs.attempt_id, 0, %{
                   terminal_artifacts: artifacts
                 })
               )

      assert reason in [:invalid_data, :limit]
    end

    # Empty explicit container and binary content round trip.
    assert {:ok, _} =
             ExecutorJournal.record_terminal(
               @journal,
               terminal_attrs(authority_id, attrs.attempt_id, 0, %{
                 terminal_artifacts: container(good)
               })
             )

    # 33 MiB of stored logical data exceeds the 32 MiB transaction budget.
    huge = String.duplicate("x", 4_100_000)

    over_receipt = %{"receipt_id" => Ecto.UUID.generate(), "detail" => huge}
    {:ok, over_digest} = Codec.digest(over_receipt, :event)

    over_budget = %{
      authority_id: authority_id,
      attempt_id: Ecto.UUID.generate(),
      expected_version: 0,
      termination: %{"origin" => "execution", "detail" => huge},
      terminal_result: %{"status" => "success", "output" => %{"stdout" => huge}},
      terminal_artifacts:
        container(%{Ecto.UUID.generate() => artifact_item(:binary.copy(<<1>>, 16_000_000))}),
      receipt_id: over_receipt["receipt_id"],
      receipt: over_receipt,
      receipt_digest: over_digest
    }

    assert {:error, :limit} =
             ExecutorJournal.record_terminal(@journal, over_budget)
  end

  test "terminal attachment codec covers raw and encoded boundaries", %{
    authority_id: _authority_id
  } do
    assert {:ok, _} = TerminalArtifacts.encode(container())

    bytes = :crypto.strong_rand_bytes(1024)
    id = Ecto.UUID.generate()
    container = container(%{id => artifact_item(bytes)})

    assert {:ok, _} = TerminalArtifacts.encode(container)
    assert {:ok, ^bytes} = TerminalArtifacts.content(container, id)

    assert {:error, :artifact_missing} =
             TerminalArtifacts.content(container, Ecto.UUID.generate())

    assert {:error, :invalid_data} = TerminalArtifacts.encode(%{"version" => 2, "items" => %{}})
    assert {:error, :invalid_data} = TerminalArtifacts.encode(container(%{id => %{}}))
    assert {:error, :invalid_data} = TerminalArtifacts.encode(%{"version" => 1})

    assert {:error, :invalid_data} =
             TerminalArtifacts.encode(
               container(%{id => Map.put(artifact_item(bytes), "extra", true)})
             )

    # Aggregated decoded content above 16 MiB is rejected, per-item likewise.
    chunk = :binary.copy(<<7>>, 9_000_000)

    two_big =
      container(%{
        Ecto.UUID.generate() => artifact_item(chunk),
        Ecto.UUID.generate() => artifact_item(chunk)
      })

    assert {:error, :limit} = TerminalArtifacts.encode(two_big)

    single_big =
      container(%{Ecto.UUID.generate() => artifact_item(:binary.copy(<<7>>, 16_777_217))})

    assert {:error, :limit} = TerminalArtifacts.encode(single_big)

    # The stored encoded representation stays inside the 24 MiB column bound.
    max_ok = :binary.copy(<<3>>, 16_000_000)

    assert {:ok, encoded_bytes} =
             TerminalArtifacts.encoded_size(container(%{id => artifact_item(max_ok)}))

    assert encoded_bytes <= Codec.limit(:journal_artifacts)

    assert {:ok, _} =
             TerminalArtifacts.encode(container(%{id => artifact_item(<<0, 255, 254, 1>>)}))
  end

  defp count(sql) do
    SQL.query!(@repo, sql, [], log: false).rows
  end
end

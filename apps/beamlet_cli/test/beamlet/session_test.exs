defmodule Beamlet.CLI.SessionTest do
  use ExUnit.Case
  alias Beamlet.CLI.{Command, Renderer, Runner, Session}

  test "bounded grammar preserves input and rejects invalid bytes and limits" do
    assert {:ok, {:input, "a", "hello  world"}} = Command.parse("input a hello  world")

    for line <- [<<255>>, String.duplicate("x", 65_537), "eval 1", "watch a 60001 1"] do
      assert {:error, :invalid_command} = Command.parse(line)
    end

    assert {:ok, {:watch, "a", [timeout: 1, events: 256]}} = Command.parse("watch a 1 256")
    refute Renderer.render({:error, {:secret, "sentinel"}}) =~ "sentinel"
  end

  test "Owl tables retain disambiguating identities and explicit partial counts" do
    authority = String.to_atom(String.duplicate("a", 200) <> "@host")
    id = String.duplicate("i", 128)
    rows = Enum.map(1..9, &%{authority: authority, id: id <> "#{&1}", pid: self()})

    text =
      Renderer.render({:ok, %{agents: rows, failures: %{authority => :timeout}, complete: false}})

    assert text =~ "complete=false"
    assert text =~ "Showing 8 identities"
    assert text =~ Atom.to_string(authority)
    assert text =~ "id64:"
    assert text =~ "error: timeout"
    assert String.length(text) < 16_384
    assert Renderer.render(:help) =~ "trusted executable"
  end

  test "host is opt-in and only interaction can be enabled" do
    assert {:ok, [enabled: false, allowed_nodes: []]} = Beamlet.CLI.configuration([])
    assert Process.whereis(Beamlet.Node) == nil

    assert {:error, :invalid_configuration} =
             Beamlet.CLI.configuration(node: [roles: [:authority]])

    assert {:error, :invalid_configuration} =
             Beamlet.CLI.configuration(enabled: true, enabled: false)

    {:ok, pid} =
      Supervisor.start_link([{Beamlet.Node, roles: [:interaction]}], strategy: :one_for_one)

    assert Process.whereis(Beamlet.Agent.Registry) == nil
    assert Process.whereis(Beamlet.Runtime.ExecutorGateway) == nil
    Supervisor.stop(pid)
  end

  test "attach observes real identity without input; quit EOF detach retain Agent and aliases never rebind" do
    start_supervised!({Beamlet.Node, roles: [:authority]})

    {:ok, ref} =
      Beamlet.Agent.start(node(),
        id: "same",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
        }
      )

    s = %{Session.new() | aliases: %{"a" => ref}}
    output = fn _ -> :ok end
    assert {:continue, ^s} = Session.execute(s, "attach untrusted@host same a", output)
    assert {:continue, detached} = Session.execute(s, "detach a", output)
    assert detached.aliases == %{}
    assert Process.alive?(ref.pid)
    assert {:quit, _} = Session.execute(s, "quit", output)
    assert :ok = Runner.run(s, read: fn -> :eof end, output: output, exit: fn 0 -> :ok end)
    assert Process.alive?(ref.pid)
    assert :ok = Beamlet.Agent.close(ref)

    {:ok, replacement} =
      Beamlet.Agent.start(node(),
        id: "same",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
        }
      )

    assert ref.pid != replacement.pid
    assert {:continue, ^s} = Session.execute(s, "status a", output)
    assert {:continue, ^s} = Session.execute(s, "close a", output)
    assert Process.alive?(replacement.pid)
  end

  test "aliases are bounded and close clears only on success" do
    start_supervised!({Beamlet.Node, roles: [:authority]})

    {:ok, ref} =
      Beamlet.Agent.start(node(),
        id: "close",
        model: %{
          provider: "deterministic",
          config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
        }
      )

    s = %{Session.new() | aliases: %{"a" => ref, "b" => ref}}
    assert {:continue, %{aliases: empty}} = Session.execute(s, "close a", fn _ -> :ok end)
    assert empty == %{}
  end

  test "128 aliases reject admission before lookup, without disclosing command paths" do
    s = %{Session.new() | aliases: Map.new(1..128, &{"a#{&1}", nil})}
    owner = self()
    assert {:continue, ^s} = Session.execute(s, "attach missing@host id fresh", &send(owner, &1))
    assert_receive "error: alias_limit"

    assert {:continue, ^s} =
             Session.execute(s, "create missing@host /secret/path", &send(owner, &1))

    assert_receive "error: invalid_authority"
    assert {:continue, ^s} = Session.execute(s, "attach missing@host id a1", &send(owner, &1))
    assert_receive "error: alias_exists"
  end

  test "runner rejects whole overlong line and injectable quit exits once" do
    {:ok, io} = StringIO.open(String.duplicate("x", 65_537) <> "\nquit\n")
    assert {:error, :line_limit} = Runner.read_line(io)

    assert :ok =
             Runner.run(Session.new(),
               read: fn -> "quit" end,
               output: fn _ -> flunk("quit output") end,
               exit: fn 0 -> :ok end
             )
  end

  test "Unicode reader preserves complete codepoints and byte bounds" do
    for text <- ["ASCII  ", "café", "中国", "é😀", String.duplicate("é", 32_768)] do
      {:ok, io} = StringIO.open(text <> "\n")
      assert Runner.read_line(io) == text
      assert Runner.read_line(io) == :eof
    end

    {:ok, io} = StringIO.open(String.duplicate("é", 32_768) <> "x\n")
    assert Runner.read_line(io) == {:error, :line_limit}

    assert Runner.run(Session.new(),
             read: fn -> {:error, :input} end,
             output: fn _ -> :ok end,
             exit: fn code -> code end
           ) == 1
  end

  test "encoded identity tokens roundtrip every shared ID character without eval" do
    for id <- [
          "simple",
          "two words",
          "quotes\"\\",
          "中国é😀",
          "line\n\t\e",
          String.duplicate("é", 64)
        ] do
      token = "id64:" <> Base.url_encode64(id, padding: false)

      assert Command.parse("attach host@local #{token} a") ==
               {:ok, {:attach, "host@local", id, "a"}}
    end

    assert Command.parse("attach host@local id64:! a") == {:error, :invalid_command}
  end

  test "snapshot pages traverse nine distinct IDs without querying again" do
    rows = Enum.map(1..9, &%{authority: node(), id: "unique-#{&1}", pid: self()})
    snapshot = %{agents: rows, failures: %{}, complete: true}
    session = Map.put(Session.new(), :discovery, snapshot)
    owner = self()
    assert {:continue, _} = Session.execute(session, "agents-page 2", &send(owner, &1))
    assert_receive text
    assert text =~ "id64:" <> Base.url_encode64("unique-9", padding: false)
    assert text =~ "page=2/2"
    assert text =~ "complete=true"
  end

  test "Owl compiled Unicode columns use installed Ucwidth and preserve display bounds" do
    assert Code.ensure_loaded?(Ucwidth)
    assert Owl.Data.length("中国") == 4
    assert Owl.Data.length("😀") == 2
    assert Owl.Data.length("é") == 1

    for text <- ["中国", "😀", "é"] do
      value = Owl.Data.truncate(String.duplicate(text, 20), 8)
      assert Owl.Data.length(value) <= 8
    end
  end

  test "reader handles partial EOF and invalid native UTF-8 honestly" do
    {:ok, io} = StringIO.open("café")
    assert Runner.read_line(io) == "café"
    assert Runner.read_line(io) == :eof
    {:ok, invalid} = StringIO.open(<<255>>)
    assert {:error, :input} = Runner.read_line(invalid)
  end
end

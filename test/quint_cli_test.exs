defmodule Beamlet.QuintCliTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "beamlet-cli-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    calls = Path.join(dir, "calls.txt")
    executable = Path.join(dir, "quint")

    # A process-boundary fixture records CLI arguments. It does not validate models.
    File.write!(executable, """
    #!/bin/sh
    if [ "$1" = "--version" ]; then
      echo '0.32.0-fixture'
      exit 0
    fi
    printf '%s\\n' "$*" >> '#{calls}'
    if [ -f '#{dir}/fail' ]; then
      echo 'Runtime error'
      exit 2
    fi
    previous=''
    for argument in "$@"; do
      if [ "$previous" = '--out-itf' ]; then
        printf '{"states":[{},{}]}\\n' > "$argument"
        echo 'Invariant violated'
        exit 1
      fi
      previous="$argument"
    done
    exit 0
    """)

    File.chmod!(executable, 0o755)
    original_path = System.get_env("PATH")
    System.put_env("PATH", dir <> ":" <> original_path)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      File.rm_rf!(dir)
    end)

    %{dir: dir, calls: calls, logs: Path.join(dir, "logs")}
  end

  test "mix quint dispatches each positional phase through the registered task", %{
    calls: calls,
    logs: logs
  } do
    for {phase, expected_commands} <- [
          {"typecheck", ~w(typecheck)},
          {"test", ~w(test)},
          {"simulate", ~w(run)},
          {"mutations", ~w(run test)},
          {"all", ~w(run test typecheck)}
        ] do
      File.rm(calls)
      phase_logs = Path.join(logs, phase)
      Mix.Task.reenable("quint")

      capture_io(fn ->
        Mix.Task.run("quint", [
          phase,
          "--samples",
          "1",
          "--directed-samples",
          "1",
          "--log-dir",
          phase_logs
        ])
      end)

      assert read_commands(calls) |> Enum.map(&hd/1) |> Enum.uniq() |> Enum.sort() ==
               expected_commands

      assert File.read!(Path.join(phase_logs, "run-info.txt")) =~ "phase=#{phase}\n"
    end
  end

  test "explicit thread budget is forwarded to every Rust simulation", %{calls: calls, logs: logs} do
    capture_io(fn ->
      Mix.Tasks.Quint.run([
        "simulate",
        "--samples",
        "2",
        "--directed-samples",
        "3",
        "--jobs",
        "2",
        "--threads",
        "4",
        "--log-dir",
        logs
      ])
    end)

    commands = read_commands(calls)

    for command <- commands do
      assert hd(command) == "run"
      assert_option(command, "--backend", "rust")
      assert_option(command, "--n-threads", "4")
      assert_option(command, "--max-steps", "100")
      assert_option(command, "--seed", "42")
    end

    {core, directed} =
      Enum.split_with(commands, fn command ->
        Enum.at(command, 1) in ~w(model/quint/beamletCore.qnt model/quint/beamletExecution.qnt) or
          (Enum.at(command, 1) == "model/quint/beamletMultiIntent.qnt" and
             Enum.member?(Enum.chunk_every(command, 2, 1, :discard), ["--init", "independentInit"])) or
          (Enum.at(command, 1) == "model/quint/beamletContinuation.qnt" and
             Enum.member?(Enum.chunk_every(command, 2, 1, :discard), ["--init", "init"]))
      end)

    for {group, samples} <- [{core, "2"}, {directed, "3"}] do
      assert group != []
      for command <- group, do: assert_option(command, "--max-samples", samples)
    end
  end

  test "logs describe the effective run configuration and elapsed wall times", %{logs: logs} do
    capture_io(fn ->
      Mix.Tasks.Quint.run([
        "typecheck",
        "--jobs",
        "2",
        "--threads",
        "4",
        "--log-dir",
        logs
      ])
    end)

    info = File.read!(Path.join(logs, "run-info.txt"))
    assert info =~ "quint_version=0.32.0-fixture"
    assert info =~ "jobs=2"
    assert info =~ "threads=4"
    assert info =~ "mutation_threads=1"
    assert info =~ "seed=42"
    assert info =~ "max_steps=100"

    [header | rows] = File.read!(Path.join(logs, "timings.tsv")) |> String.split("\n", trim: true)
    assert header == "scope\tphase\tname\tstatus\telapsed_ms"

    assert rows |> Enum.map(&(String.split(&1, "\t") |> hd())) |> Enum.uniq() |> Enum.sort() ==
             ~w(job phase run)

    for row <- rows do
      [scope, phase, _name, status, elapsed] = String.split(row, "\t")
      assert scope in ["job", "phase", "run"]
      assert phase == "typecheck"
      assert status == "passed"
      assert String.to_integer(elapsed) >= 0
    end

    # Reusing the directory must start a fresh report, not accumulate old timings.
    capture_io(fn ->
      Mix.Tasks.Quint.run(["typecheck", "--log-dir", logs])
    end)

    [^header | fresh_rows] =
      File.read!(Path.join(logs, "timings.tsv")) |> String.split("\n", trim: true)

    # Ignore durations and concurrent job ordering; each run must report the same work once.
    without_elapsed = fn entries ->
      entries |> Enum.map(&(String.split(&1, "\t") |> Enum.take(4))) |> Enum.sort()
    end

    assert without_elapsed.(fresh_rows) == without_elapsed.(rows)
  end

  test "default threads share the online scheduler budget between jobs", %{
    calls: calls,
    logs: logs
  } do
    capture_io(fn ->
      Mix.Tasks.Quint.run([
        "simulate",
        "--samples",
        "1",
        "--directed-samples",
        "1",
        "--jobs",
        "2",
        "--log-dir",
        logs
      ])
    end)

    expected = max(div(System.schedulers_online(), 2), 1)

    for command <- read_commands(calls) do
      assert_option(command, "--n-threads", to_string(expected))
    end
  end

  test "typecheck and tests never receive thread flags, and mutations use one thread", %{
    calls: calls,
    logs: logs
  } do
    capture_io(fn ->
      Mix.Tasks.Quint.run([
        "--samples",
        "2",
        "--directed-samples",
        "2",
        "--jobs",
        "2",
        "--threads",
        "3",
        "--log-dir",
        logs
      ])
    end)

    assert File.read!(Path.join(logs, "run-info.txt")) =~ "phase=all\n"
    commands = read_commands(calls)
    checks = Enum.filter(commands, &(hd(&1) == "typecheck"))
    tests = Enum.filter(commands, &(hd(&1) == "test"))
    mutants = Enum.filter(commands, &("--out-itf" in &1))

    for group <- [checks, tests, mutants], do: assert(group != [])

    for file <-
          ~w(beamletContinuation beamletContinuation_test beamletContinuation_mutations_test) do
      assert Enum.any?(checks, &(Enum.at(&1, 1) == "model/quint/#{file}.qnt"))
    end

    assert Enum.any?(tests, &("--main" in &1 and "continuationTests" in &1))

    assert Enum.count(
             mutants,
             &(Enum.at(&1, 1) == "model/quint/beamletContinuation_mutations_test.qnt")
           ) == 6

    for command <- checks ++ tests, do: refute("--n-threads" in command)
    for command <- checks, do: refute("--backend" in command)
    for command <- tests, do: assert_option(command, "--backend", "rust")

    for command <- mutants do
      assert_option(command, "--n-threads", "1")
      assert_option(command, "--max-samples", "1")
    end
  end

  test "failed work is recorded as failed rather than a successful timing", %{
    dir: dir,
    logs: logs
  } do
    File.write!(Path.join(dir, "fail"), "")

    capture_io(fn ->
      assert_raise Mix.Error, ~r/Quint failed \(exit 2\)/, fn ->
        Mix.Tasks.Quint.run(["simulate", "--jobs", "1", "--log-dir", logs])
      end
    end)

    [_header | rows] =
      File.read!(Path.join(logs, "timings.tsv")) |> String.split("\n", trim: true)

    assert Enum.map(rows, &(String.split(&1, "\t") |> hd())) == ["job", "phase", "run"]

    for row <- rows do
      assert Enum.at(String.split(row, "\t"), 3) == "failed"
    end
  end

  defp read_commands(path) do
    commands = File.read!(path) |> String.split("\n", trim: true) |> Enum.map(&String.split/1)
    assert commands != []
    commands
  end

  defp assert_option(command, flag, value) do
    assert [flag, value] in Enum.chunk_every(command, 2, 1, :discard)
  end
end

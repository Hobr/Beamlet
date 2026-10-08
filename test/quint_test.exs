defmodule Beamlet.QuintTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @repo Path.expand("..", __DIR__)
  @env ~w(PATH CORE_LOG_DIR CORE_VERIFY_TIMEOUT CORE_SERVER_PORT QUINT_LOG_DIR QUINT_VERIFY_TIMEOUT QUINT_FIXTURE_RECORD QUINT_FIXTURE_MISSING QUINT_FIXTURE_ZERO QUINT_FIXTURE_FAIL QUINT_FIXTURE_HANG QUINT_FIXTURE_PIDS QUINT_FIXTURE_UNICODE)

  setup do
    root =
      Path.join("/tmp", "beamlet mix fixture #{System.unique_integer([:positive])} ;$literal")

    # 只复制套件依赖，不读取或复制历史 evidence。
    patterns =
      ~w(mix.exs spec/quint/*.qnt spec/quint/core/*.qnt spec/quint/check.exs spec/quint/core/verify.py)

    for pattern <- patterns, source <- Path.wildcard(Path.join(@repo, pattern)) do
      target = Path.join(root, Path.relative_to(source, @repo))
      File.mkdir_p!(Path.dirname(target))
      File.cp!(source, target)
    end

    bin = Path.join(root, "tool bin")
    File.mkdir!(bin)
    File.cp!(Path.join(@repo, "test/fixtures/quint.py"), Path.join(bin, "quint"))
    File.chmod!(Path.join(bin, "quint"), 0o755)
    previous = Map.new(@env, &{&1, System.get_env(&1)})
    for key <- @env -- ["PATH"], do: System.delete_env(key)
    System.put_env("PATH", bin <> ":" <> previous["PATH"])
    record = Path.join(root, "argv.jsonl")
    System.put_env("QUINT_FIXTURE_RECORD", record)

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      File.rm_rf!(root)
    end)

    %{root: root, record: record}
  end

  defp run(root, args, suite \\ "CORE") do
    log = Path.join(root, "logs #{System.unique_integer([:positive])} ;$literal")
    System.put_env(suite <> "_LOG_DIR", log)
    capture_io(fn -> send(self(), {:result, Beamlet.Quint.main(args, root)}) end)
    assert_receive {:result, code}
    {code, log}
  end

  defp records(path) do
    # JSON decoding uses the fixture's Python, keeping the Mix project dependency-free.
    {text, 0} =
      System.cmd("python3", [
        "-c",
        "import json,sys; [print(repr(json.loads(s)['argv'])) for s in open(sys.argv[1])]",
        path
      ])

    text
  end

  test "core quick routes exact test arguments, paths and accounting", ctx do
    assert {0, log} = run(ctx.root, ["quick"])
    text = records(ctx.record)
    assert text =~ "['typecheck', 'spec/quint/core/model.qnt']"
    assert text =~ "'--match', '.*Test', '--backend', 'typescript', '--seed', '20261014'"
    assert text =~ Path.join(log, "combined_{test}_{seq}.itf.json")
    refute text =~ "'run'"
    refute text =~ "'verify'"
    assert length(File.ls!(log) |> Enum.filter(&String.ends_with?(&1, ".exit"))) == 10

    for exit <- Path.wildcard(Path.join(log, "*.exit")) do
      assert File.read!(exit) == "0\n"
      assert File.regular?(String.replace_suffix(exit, ".exit", ".log"))
      assert {_, "\n"} = Float.parse(File.read!(String.replace_suffix(exit, ".exit", ".time")))
    end

    assert File.read!(Path.join(log, ".runner-owner")) == System.pid() <> "\n"
    assert File.read!(Path.join(log, "environment.txt")) =~ "Elixir=#{System.version()}"
    assert File.read!(Path.join(log, "environment.txt")) =~ inspect(System.get_env("ERL_FLAGS"))
  end

  test "supplemental quick and simulation use their own modules, actions and seeds", ctx do
    assert {0, _log} = run(ctx.root, ["simulate", "--suite", "supplemental"], "QUINT")
    text = records(ctx.record)
    assert text =~ "'spec/quint/architecture_test.qnt'"
    assert text =~ "'--main', 'architectureAnalysis'"
    assert text =~ "'--max-samples', '10000', '--max-steps', '100', '--seed', '20261007'"
    assert text =~ "'--init', 'recoveryInit'"
    assert text =~ "'--init', 'progressInit', '--step', 'progressStep'"
    assert text =~ "'--max-steps', '40', '--seed', '20261009'"
    refute text =~ "'spec/quint/core/"
  end

  test "nonzero command and missing executable remain attributable and continue checks", ctx do
    System.put_env("QUINT_FIXTURE_FAIL", "typecheck")
    assert {1, log} = run(ctx.root, ["quick"])
    assert File.read!(Path.join(log, "typecheck-model.exit")) == "7\n"
    assert File.read!(Path.join(log, "typecheck-model.log")) =~ "deliberate failure"
    assert File.read!(Path.join(log, "tests.exit")) == "0\n"
    System.delete_env("QUINT_FIXTURE_FAIL")
    File.rm!(Path.join(ctx.root, "tool bin/quint"))
    # Remove the real Quint directory as well, so missing-tool behavior is genuine.
    path =
      System.get_env("PATH")
      |> String.split(":")
      |> Enum.reject(&File.exists?(Path.join(&1, "quint")))
      |> Enum.join(":")

    System.put_env("PATH", path)
    assert {1, missing} = run(ctx.root, ["quick"])
    assert File.read!(Path.join(missing, "version.exit")) == "127\n"
    assert File.read!(Path.join(missing, "version.log")) =~ "quint"
  end

  test "all ten requested witnesses reject missing and zero output through aggregation", ctx do
    assert {0, positive} = run(ctx.root, ["simulate"])

    {text, 0} =
      System.cmd("python3", [
        "-c",
        "import json,sys; a=next(json.loads(s)['argv'] for s in open(sys.argv[1]) if json.loads(s)['argv'][0]=='run'); i=a.index('--witnesses')+1; print(' '.join(a[i:a.index('--max-samples')]))",
        ctx.record
      ])

    witnesses = String.split(text)
    assert length(witnesses) == 10
    assert File.read!(Path.join(positive, "witnesses.log")) =~ "All 10"

    for witness <- witnesses, kind <- ~w(MISSING ZERO) do
      System.put_env("QUINT_FIXTURE_" <> kind, witness)
      assert {1, log} = run(ctx.root, ["simulate"])
      assert File.read!(Path.join(log, "sampling.exit")) == "0\n"
      assert File.read!(Path.join(log, "witnesses.exit")) == "1\n"
      assert File.read!(Path.join(log, "witnesses.log")) =~ witness
      System.delete_env("QUINT_FIXTURE_" <> kind)
    end
  end

  test "supplemental conditional-progress missing witness is a failure", ctx do
    System.put_env("QUINT_FIXTURE_MISSING", "recoveryConsumedWitness")
    assert {1, log} = run(ctx.root, ["simulate", "--suite", "supplemental"], "QUINT")
    assert File.read!(Path.join(log, "conditional-progress-witnesses.exit")) == "1\n"
  end

  test "invalid mode, suite, budget and nonempty log directory fail with useful logs", ctx do
    for args <- [["bad"], ["quick", "extra"], ["--unknown"], ["--suite", "bad"]] do
      assert {2, log} = run(ctx.root, args)
      assert File.read!(Path.join(log, "configuration.log")) =~ "usage:"
    end

    System.put_env("CORE_VERIFY_TIMEOUT", "oops")
    assert {2, log} = run(ctx.root, ["verify"])
    assert File.read!(Path.join(log, "configuration.log")) =~ "CORE_VERIFY_TIMEOUT"
    refute File.exists?(ctx.record)
    System.delete_env("CORE_VERIFY_TIMEOUT")
    assert {0, log} = run(ctx.root, ["quick"])
    original = File.read!(Path.join(log, "results.txt"))

    capture_io(:stderr, fn ->
      capture_io(fn -> assert Beamlet.Quint.main(["quick"], ctx.root) == 2 end)
    end)

    assert File.read!(Path.join(log, "results.txt")) == original
  end

  test "verify preserves Unicode stdout, stderr and backend exit codes in both suites", ctx do
    System.put_env("QUINT_FIXTURE_UNICODE", "1")

    for failure <- [nil, "verify"] do
      if failure,
        do: System.put_env("QUINT_FIXTURE_FAIL", failure),
        else: System.delete_env("QUINT_FIXTURE_FAIL")

      expected = if failure, do: 1, else: 0
      backend_exit = if failure, do: "7\n", else: "0\n"

      for {args, suite, labels} <- [
            {["verify"], "CORE", ["depth10"]},
            {["verify", "--suite", "supplemental"], "QUINT",
             ["composed-depth10", "conditional-depth8"]}
          ] do
        assert {^expected, log} = run(ctx.root, args, suite)

        for label <- labels do
          output = File.read!(Path.join(log, label <> ".log"))
          assert output =~ "10月 下午 λ stdout\n警告: 后端 stderr\n"
          assert File.read!(Path.join(log, label <> ".exit")) == backend_exit
          refute output =~ "no_translation"
        end
      end
    end
  end

  test "core verify timeout cleans owned child and leaves unrelated process alive", ctx do
    pids = Path.join(ctx.root, "pids")
    System.put_env("QUINT_FIXTURE_PIDS", pids)
    System.put_env("QUINT_FIXTURE_HANG", "1")
    System.put_env("CORE_VERIFY_TIMEOUT", "1")
    System.put_env("CORE_SERVER_PORT", "18842")

    sentinel =
      Port.open({:spawn_executable, System.find_executable("python3")}, [
        :binary,
        args: ["-c", "import time; time.sleep(60)"]
      ])

    {:os_pid, sentinel_pid} = Port.info(sentinel, :os_pid)

    try do
      assert {1, log} = run(ctx.root, ["verify"])
      assert File.read!(Path.join(log, "depth10.exit")) == "124\n"
      assert File.read!(Path.join(log, "depth10.log")) =~ "INCONCLUSIVE"
      assert records(ctx.record) =~ "'--server-endpoint', 'localhost:18842'"
      work = Path.join(log, "depth10.work")

      assert File.read!(Path.join(work, "_apalache-out/server/fixture/detailed.log")) =~
               "fixture-local"

      assert File.read!(Path.join(log, "commands.txt")) =~ inspect(work)
      refute File.exists?(Path.join(ctx.root, "_apalache-out"))

      assert File.read!(Path.join(work, "spec/quint/core/verify.py")) ==
               File.read!(Path.join(ctx.root, "spec/quint/core/verify.py"))

      for pid <- String.split(File.read!(pids)) do
        {_, code} =
          System.cmd("python3", [
            "-c",
            "import pathlib,sys; p=pathlib.Path('/proc')/sys.argv[1]/'stat'; sys.exit(1 if p.exists() and p.read_text().split()[2]!='Z' else 0)",
            pid
          ])

        assert code == 0
      end

      {_, 0} = System.cmd("kill", ["-0", Integer.to_string(sentinel_pid)])
    after
      System.cmd("kill", ["-TERM", Integer.to_string(sentinel_pid)])
      if Port.info(sentinel), do: Port.close(sentinel)
    end
  end

  test "supplemental verify skips quick and checkpoints only isolated command output", ctx do
    foreign = Path.join(ctx.root, "_apalache-out/server/foreign/detailed.log")
    File.mkdir_p!(Path.dirname(foreign))
    File.write!(foreign, "FOREIGN EVIDENCE MUST NOT APPEAR")
    System.put_env("QUINT_VERIFY_TIMEOUT", "2s")
    assert {0, log} = run(ctx.root, ["verify", "--suite", "supplemental"], "QUINT")
    text = records(ctx.record)
    refute text =~ "'typecheck'"

    assert text =~
             "'--main', 'architectureBounded', '--invariant', 'modelCheckSafety', '--max-steps', '10'"

    assert text =~
             "'--init', 'progressInit', '--step', 'progressStep', '--invariant', 'conditionalSafety', '--max-steps', '8'"

    for label <- ~w(composed-depth10 conditional-depth8) do
      checkpoint = File.read!(Path.join(log, label <> ".backend.log"))
      assert checkpoint =~ "fixture-local"
      refute checkpoint =~ "FOREIGN"
      assert checkpoint =~ label <> ".work"
    end
  end

  test "Mix aliases and direct script CLI route modes and propagate failure", ctx do
    for {task, args, expected} <- [
          {"quint.quick", [], 0},
          {"quint.simulate", [], 0},
          {"quint.verify", [], 0},
          {"quint", [], 0},
          {"quint.supplemental", ["quick"], 0},
          {"quint", ["invalid"], 1}
        ] do
      log = Path.join(ctx.root, "cli-#{task}-#{System.unique_integer([:positive])}")
      env = [{"CORE_LOG_DIR", log}, {"QUINT_LOG_DIR", log}]

      {output, code} =
        System.cmd("mix", [task | args], cd: ctx.root, env: env, stderr_to_stdout: true)

      assert code == expected, output
      assert output =~ "evidence:"
    end

    System.put_env("QUINT_FIXTURE_FAIL", "test")

    {output, 1} =
      System.cmd("mix", ["quint.quick"],
        cd: ctx.root,
        env: [{"CORE_LOG_DIR", Path.join(ctx.root, "cli-fail")}],
        stderr_to_stdout: true
      )

    assert output =~ "Quint checks failed"

    {output, 2} =
      System.cmd("elixir", [Path.join(ctx.root, "spec/quint/check.exs"), "bad"],
        cd: ctx.root,
        env: [{"CORE_LOG_DIR", Path.join(ctx.root, "direct-invalid")}],
        stderr_to_stdout: true
      )

    assert output =~ "configuration: exit=2"
  end
end

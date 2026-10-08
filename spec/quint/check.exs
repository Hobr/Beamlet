# 单一验证执行器；Mix 别名和直接 Elixir CLI 共用同一入口。
defmodule Beamlet.Quint do
  @root Path.expand("../..", __DIR__)
  # 请求与校验共用目标列表，防止漏检；每个目标都必须在本次抽样中出现且计数为正。
  @core_witnesses ~w(intentWitness entryWitness unknownWitness recoveryWitness consumedWitness recoveryConsumedWitness branchWorkWitness inconclusiveWitness failedUnknownWitness failedReplyWitness)
  @supplemental_witnesses ~w(inputWitness commitWitness admissionWitness entryWitness unknownWitness observationWitness repeatWitness settlementWitness consumptionWitness recoveryConsumedWitness branchNewWorkWitness forkWitness finishedWitness failedWitness disposalWitness evaluateWitness precheckWitness completeWitness auditWitness suspendWitness resumeWitness takeoverWitness controllerWitness controllerReadyWitness ownerDeathWitness disconnectWitness reconnectWitness providerWitness providerFaultWitness retryWitness rejectWitness lostAckWitness staleWitness lostProposalWitness writesWitness uiWitness authWitness permissionWitness)

  def main(args, root \\ @root) do
    {suite, mode} = parse(args)
    prefix = if suite == "supplemental", do: "QUINT", else: "CORE"
    log = evidence_dir(System.get_env(prefix <> "_LOG_DIR"), root, suite)
    # 独占标记防止两个并发运行共用同一空目录。
    File.open!(Path.join(log, ".runner-owner"), [:write, :exclusive], fn io ->
      IO.write(io, "#{System.pid()}\n")
    end)

    IO.puts("Quint #{suite} evidence: #{log}")
    context = %{root: root, log: log, failed: false}

    try do
      unless suite in ~w(core supplemental) and mode in ~w(quick simulate verify all) do
        raise ArgumentError,
              "usage: mix quint [quick|simulate|verify|all] [--suite core|supplemental]"
      end

      timeout =
        System.get_env(prefix <> "_VERIFY_TIMEOUT") || if(suite == "core", do: "240", else: "600")

      port = System.get_env("CORE_SERVER_PORT") || "8842"

      if mode in ~w(verify all) do
        if suite == "core" do
          positive_integer!(timeout, prefix <> "_VERIFY_TIMEOUT")
          positive_integer!(port, "CORE_SERVER_PORT")

          if String.to_integer(port) > 65_535,
            do: raise(ArgumentError, "CORE_SERVER_PORT must be <= 65535")
        else
          unless Regex.match?(~r/^(?:\d+(?:\.\d+)?|\.\d+)[smhd]?$/, timeout) and
                   elem(Float.parse(timeout), 0) > 0 do
            raise ArgumentError, "QUINT_VERIFY_TIMEOUT must be a positive GNU timeout duration"
          end
        end
      end

      File.write!(Path.join(log, "domain.txt"), domain(suite, mode, timeout, port))

      File.write!(
        Path.join(log, "environment.txt"),
        "Elixir=#{System.version()} OTP=#{:erlang.system_info(:otp_release)} ERL_FLAGS=#{inspect(System.get_env("ERL_FLAGS"))} ERL_AFLAGS=#{inspect(System.get_env("ERL_AFLAGS"))}\n"
      )

      context = command(context, "version", "quint", ["--version"])

      # 核心各模式先 quick；simulate 加抽样，verify 加有界检查，all 依次各执行一次。
      # simulate/verify 函数只负责各自阶段，因此 all 不会重复 quick；补充 verify 保留跳过 quick 的旧行为。
      context = quick(context, suite, mode)
      context = if mode in ~w(simulate all), do: simulate(context, suite), else: context

      context =
        if mode in ~w(verify all), do: verify(context, suite, timeout, port), else: context

      if context.failed, do: 1, else: 0
    rescue
      error ->
        local_check(context, "configuration", fn -> {Exception.message(error) <> "\n", 2} end)
        2
    end
  rescue
    error ->
      # 配置目录不可用时，仍保存可归属的失败证据，避免污染指定的旧目录。
      log = fresh_dir("configuration")
      context = %{root: root, log: log, failed: false}
      IO.puts(:stderr, "Quint configuration evidence: #{log}")
      local_check(context, "configuration", fn -> {Exception.message(error) <> "\n", 2} end)
      2
  end

  defp parse(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: [suite: :string])
    suite = Keyword.get(options, :suite, "core")

    mode =
      case positional do
        [] -> "all"
        [mode] -> mode
        _ -> "invalid"
      end

    {suite, if(invalid == [], do: mode, else: "invalid")}
  end

  defp positive_integer!(value, name) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> :ok
      _ -> raise ArgumentError, "#{name} must be a positive integer, got #{inspect(value)}"
    end
  end

  defp fresh_dir(suite) do
    path =
      Path.join(
        "/tmp",
        "beamlet-quint-#{suite}-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(path)
    path
  end

  defp evidence_dir(nil, _root, suite), do: fresh_dir(suite)

  # 空目录避免覆盖旧证据；realpath 后再次检查允许树，防止符号链接指向树外。
  defp evidence_dir(path, root, _suite) do
    path = Path.expand(path, root)
    allowed_dir!(path, root)
    File.mkdir_p!(path)
    {physical, 0} = System.cmd("realpath", [path])
    path = String.trim(physical)
    allowed_dir!(path, root)

    unless File.ls!(path) == [],
      do: raise(ArgumentError, "evidence directory must be empty: #{path}")

    path
  end

  defp allowed_dir!(path, root) do
    allowed = [
      "/tmp",
      Path.join(root, "spec/quint/evidence"),
      Path.join(root, "spec/quint/core/evidence")
    ]

    unless Enum.any?(allowed, &String.starts_with?(path, &1 <> "/")),
      do: raise(ArgumentError, "evidence must be under /tmp or an ignored evidence tree: #{path}")
  end

  defp command(context, label, executable, argv, cwd \\ nil) do
    File.write!(
      Path.join(context.log, "commands.txt"),
      inspect({label, executable, argv, cwd || context.root}, limit: :infinity) <> "\n",
      [:append]
    )

    started = System.monotonic_time(:millisecond)
    path = Path.join(context.log, label <> ".log")

    code =
      try do
        File.open!(path, [:write], fn io ->
          # 独立 argv 保留空格和特殊字符原义；stderr 同入该项日志，便于归属失败。
          # 按原始字节捕获，避免默认 latin1 文件设备转换 Unicode 输出失败。
          {_output, code} =
            System.cmd(executable, argv,
              cd: cwd || context.root,
              stderr_to_stdout: true,
              into: IO.binstream(io, :line)
            )

          code
        end)
      rescue
        error ->
          File.write!(path, "#{executable}: #{Exception.message(error)}\n", [:append])
          127
      end

    record(context, label, code, started)
  end

  defp local_check(context, label, fun) do
    started = System.monotonic_time(:millisecond)
    {text, code} = fun.()
    File.write!(Path.join(context.log, label <> ".log"), text)
    record(context, label, code, started)
  end

  defp record(context, label, code, started) do
    seconds = (System.monotonic_time(:millisecond) - started) / 1000
    File.write!(Path.join(context.log, label <> ".exit"), "#{code}\n")
    File.write!(Path.join(context.log, label <> ".time"), "#{seconds}\n")
    result = "#{label}: exit=#{code} seconds=#{seconds}\n"
    File.write!(Path.join(context.log, "results.txt"), result, [:append])
    IO.write(result)

    # 累积失败但继续后续检查，最终由 main 统一返回非零；不让后续成功覆盖早先错误。
    %{context | failed: context.failed or code != 0}
  end

  # quick 检查类型并执行恢复/竞态/负控回归；只确认这些断言路径，不替代组合安全检查。
  defp quick(context, "core", _mode) do
    context =
      Enum.reduce(
        ~w(model small composition core_test recovery recovery_test),
        context,
        fn source, ctx ->
          command(ctx, "typecheck-#{source}", "quint", [
            "typecheck",
            "spec/quint/core/#{source}.qnt"
          ])
        end
      )

    context =
      command(context, "recovery-tests", "quint", [
        "test",
        "spec/quint/core/recovery_test.qnt",
        "--main",
        "recovery_test",
        "--backend",
        "typescript",
        "--seed",
        "20261014"
      ])

    context =
      command(context, "combined", "quint", [
        "test",
        "spec/quint/core/core_test.qnt",
        "--main",
        "core_test",
        "--match",
        "combinedTest",
        "--backend",
        "typescript",
        "--seed",
        "20261014",
        "--out-itf",
        Path.join(context.log, "combined_{test}_{seq}.itf.json")
      ])

    command(context, "tests", "quint", [
      "test",
      "spec/quint/core/core_test.qnt",
      "--main",
      "core_test",
      "--match",
      ".*Test",
      "--backend",
      "typescript",
      "--seed",
      "20261014"
    ])
  end

  defp quick(context, "supplemental", "verify"), do: context

  defp quick(context, "supplemental", _mode) do
    context =
      Enum.reduce(Path.wildcard(Path.join(context.root, "spec/quint/*.qnt")), context, fn path,
                                                                                          ctx ->
        command(ctx, "typecheck-#{Path.basename(path, ".qnt")}", "quint", [
          "typecheck",
          Path.relative_to(path, context.root)
        ])
      end)

    Enum.reduce(
      [
        {"scenarios", "architecture_test", "20261007"},
        {"command-protocol", "protocol_test", "20261010"},
        {"negative-controls", "negative_controls_test", "20261007"},
        {"formal-contracts", "formal_test", "20261012"},
        {"envelope-progress", "progress_test", "20261012"},
        {"independent-review", "review_test", "20261011"}
      ],
      context,
      fn {label, main, seed}, ctx ->
        command(ctx, label, "quint", [
          "test",
          "spec/quint/#{main}.qnt",
          "--main",
          main,
          "--match",
          ".*Test",
          "--backend",
          "typescript",
          "--seed",
          seed
        ])
      end
    )
  end

  defp simulate(context, "core") do
    sampling(
      context,
      "sampling",
      "spec/quint/core/composition.qnt",
      "composition",
      "safety",
      @core_witnesses,
      "60",
      "20261014",
      []
    )
  end

  defp simulate(context, "supplemental") do
    context =
      sampling(
        context,
        "composed-simulation",
        "spec/quint/architecture.qnt",
        "architectureAnalysis",
        "architectureSafety",
        @supplemental_witnesses,
        "100",
        "20261007",
        []
      )

    context =
      sampling(
        context,
        "recovery-simulation",
        "spec/quint/architecture.qnt",
        "architectureRecoveryAnalysis",
        "architectureSafety",
        ~w(recoveryConsumedWitness branchNewWorkWitness),
        "100",
        "20261008",
        ["--init", "recoveryInit"]
      )

    sampling(
      context,
      "conditional-progress",
      "spec/quint/architecture.qnt",
      "architectureProgressAnalysis",
      "conditionalSafety",
      ~w(recoveryConsumedWitness),
      "40",
      "20261009",
      ["--init", "progressInit", "--step", "progressStep"]
    )
  end

  # 固定种子便于同源同工具配置复现；深度给跨阶段路径留空间，10000 条仍是有限抽样。
  # 正 witness 表示目标可达；未发现 invariant 反例不构成证明，也不保证必然进展。
  defp sampling(context, label, source, main, invariant, witnesses, depth, seed, actions) do
    context =
      command(
        context,
        label,
        "quint",
        ["run", source, "--main", main] ++
          actions ++
          ["--invariant", invariant, "--witnesses"] ++
          witnesses ++
          ["--max-samples", "10000", "--max-steps", depth, "--seed", seed, "--verbosity", "1"]
      )

    validator = if label == "sampling", do: "witnesses", else: label <> "-witnesses"

    local_check(context, validator, fn ->
      validate_witnesses(File.read!(Path.join(context.log, label <> ".log")), witnesses)
    end)
  end

  def validate_witnesses(text, witnesses) do
    missing =
      Enum.filter(witnesses, fn name ->
        case Regex.run(~r/(?:^|\n)#{Regex.escape(name)} was witnessed in (\d+) trace/, text) do
          [_, count] -> String.to_integer(count) == 0
          _ -> true
        end
      end)

    if missing == [],
      do: {"All #{length(witnesses)} required witnesses reached.\n", 0},
      else: {"Missing or zero witnesses: #{Enum.join(missing, ", ")}\n", 1}
  end

  # 正式 Apalache 检查组合到 depth10；完成仅支持该模型域/界限，超时仍无结论。
  # Python 专管既有 POSIX 进程组和截止清理；Mix/Elixir 负责上层编排，保留已验证的清理职责。
  defp verify(context, "core", timeout, port) do
    work = backend_workdir(context, "depth10")
    command(context, "depth10", "python3", ["spec/quint/core/verify.py", timeout, port], work)
  end

  defp verify(context, "supplemental", timeout, _port) do
    Enum.reduce(
      [
        {"composed-depth10",
         ["--main", "architectureBounded", "--invariant", "modelCheckSafety", "--max-steps", "10"]},
        {"conditional-depth8",
         [
           "--main",
           "architectureProgressAnalysis",
           "--init",
           "progressInit",
           "--step",
           "progressStep",
           "--invariant",
           "conditionalSafety",
           "--max-steps",
           "8"
         ]}
      ],
      context,
      fn {label, flags}, ctx ->
        # 历史 timeout 不保证清理独立会话后代；独立 cwd 只隔离产物/检查点。
        work = backend_workdir(ctx, label)

        ctx =
          command(
            ctx,
            label,
            "timeout",
            [timeout, "quint", "verify", "spec/quint/architecture.qnt"] ++
              flags ++ ["--backend", "apalache", "--verbosity", "1"],
            work
          )

        local_check(ctx, label <> ".backend", fn -> checkpoint(work) end)
      end
    )
  end

  # 在本次本地证据目录隔离 backend 产物；源码链接保留相对 argv，不把 _apalache-out 写回仓库。
  defp backend_workdir(context, label) do
    work = Path.join(context.log, label <> ".work")
    File.mkdir_p!(Path.join(work, "spec"))
    File.ln_s!(Path.join(context.root, "spec/quint"), Path.join(work, "spec/quint"))
    work
  end

  defp checkpoint(work) do
    logs = Path.wildcard(Path.join(work, "_apalache-out/server/*/detailed.log"))

    case Enum.sort_by(logs, &File.stat!(&1).mtime) |> List.last() do
      nil ->
        {"No backend log attributable to this invocation; no completed bound.\n", 0}

      source ->
        tail = File.read!(source) |> String.split("\n") |> Enum.take(-80) |> Enum.join("\n")

        {"Backend source: #{source}\nCheckpoint only; progress does not establish a completed bound.\n#{tail}\n",
         0}
    end
  end

  # domain 记录可选阶段的复现配置；实际执行了哪些阶段，以 commands/results 为准。
  defp domain("core", mode, timeout, port) do
    "suite=core mode=#{mode}\ncomposition: Runs0/1, one Effect per Run, Attempts0/1 per Effect, owner incarnations0/1, FIFO6\nmain=composition init=init step=step invariant=safety samples=10000 depth=60 seed=20261014 backend=rust\nrecovery: Run0, FIFO4, restricted recovery.step; init=init; rankDecreases and core safety; 14 transitions under explicit premises\nBMC main=composition init=init step=step safety random-transitions=false depth=10 timeout=#{timeout} port=#{port} backend=apalache\nOnly the selected mode is executed; sampling is not proof; timeout is inconclusive.\n"
  end

  defp domain("supplemental", mode, timeout, _port) do
    "suite=supplemental mode=#{mode}\narchitectureAnalysis: Runs2 Effects2 Attempts3 owners3 FIFO12 init=init step=step architectureSafety samples=10000 depth=100 seed=20261007 backend=rust\narchitectureRecoveryAnalysis: same expanded domain init=recoveryInit step=step architectureSafety samples=10000 depth=100 seed=20261008\narchitectureProgressAnalysis: expanded domain init=progressInit step=progressStep conditionalSafety samples=10000 depth=40 seed=20261009\nBMC architectureBounded: Runs2 Effects1 Attempts2 owners3 FIFO4 init=init step=step modelCheckSafety depth=10\nBMC architectureProgressAnalysis: init=progressInit step=progressStep conditionalSafety depth=8\nBMC random-transitions=false backend=apalache timeout=#{timeout}; GNU timeout historical semantics, no owned-server descendant-cleanup guarantee. Checkpoints isolated per command and are progress only.\nOnly the selected mode is executed; supplemental results do not clear an inconclusive core bound.\n"
  end
end

# require_file 在 Mix 项目内只加载模块；直接 elixir 执行则返回执行器退出码。
unless Process.whereis(Mix.ProjectStack) != nil and Mix.Project.get() != nil do
  System.halt(Beamlet.Quint.main(System.argv()))
end

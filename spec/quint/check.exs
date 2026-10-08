defmodule Beamlet.Quint do
  @root Path.expand("../..", __DIR__)
  @usage """
  usage: mix quint [quick|simulate|verify|all(Default)] [options]
    --suite core|supplemental   验证套件(默认 core)
    --cores N                   Z3 SMT 线程数(默认 8)
    --timeout SECONDS           每次后端检查的截止秒数(默认 0, 不限时)

    --max-samples N             测试与模拟的抽样次数(默认测试 1, 模拟 10000)
    --max-steps N               模拟与有界检查的探索深度(非负整数)
                                默认: 模拟 60, 后端 10; 补充: 模拟 100/100/40, 后端 10/8

    --seed N                    测试与模拟的 seed(随机非负整数)

    --verbosity N               输出级别(0-5, 模拟至少 1, 默认测试 2, 模拟 1, 后端 2)
    --n-threads N               Rust 模拟线程数(正整数, 默认 16)

    --match REGEX               确定性测试名称筛选(默认 .*Test)
                                核心 recovery_test 使用 Quint 默认筛选: 名称以 Test 结尾
    --server-endpoint HOST:PORT Apalache 服务地址(默认 localhost:8822)
  """
  @command_options %{
    "test" => [:max_samples, :seed, :verbosity, :match],
    "run" => [:max_samples, :max_steps, :seed, :verbosity, :n_threads],
    "verify" => [:max_steps, :verbosity, :server_endpoint]
  }
  @core_witnesses ~w(intentWitness entryWitness unknownWitness recoveryWitness consumedWitness recoveryConsumedWitness branchWorkWitness inconclusiveWitness failedUnknownWitness failedReplyWitness)
  @supplemental_witnesses ~w(inputWitness commitWitness admissionWitness entryWitness unknownWitness observationWitness repeatWitness settlementWitness consumptionWitness recoveryConsumedWitness branchNewWorkWitness forkWitness finishedWitness failedWitness disposalWitness evaluateWitness precheckWitness completeWitness auditWitness suspendWitness resumeWitness takeoverWitness controllerWitness controllerReadyWitness ownerDeathWitness disconnectWitness reconnectWitness providerWitness providerFaultWitness retryWitness rejectWitness lostAckWitness staleWitness lostProposalWitness writesWitness uiWitness authWitness permissionWitness)

  def main(args, root \\ @root) do
    {mode, options} = parse(args)

    if options[:help] do
      IO.puts(@usage)
      0
    else
      Enum.reduce_while(commands(mode, options, root), 0, fn argv, _ ->
        case execute(argv, options, root) do
          0 -> {:cont, 0}
          code -> {:halt, code}
        end
      end)
    end
  rescue
    error ->
      IO.puts(:stderr, Exception.message(error))
      2
  end

  def parse(args) do
    {options, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          suite: :string,
          cores: :integer,
          timeout: :integer,
          max_samples: :integer,
          max_steps: :integer,
          seed: :integer,
          verbosity: :integer,
          n_threads: :integer,
          match: :string,
          server_endpoint: :string,
          help: :boolean
        ]
      )

    options = Keyword.merge([suite: "core", cores: 8, timeout: 0], options)
    mode = if positional == [], do: "all", else: List.first(positional)

    unless invalid == [] and length(positional) <= 1 and mode in ~w(quick simulate verify all) and
             options[:suite] in ~w(core supplemental),
           do: raise(ArgumentError, @usage)

    unless options[:cores] > 0, do: raise(ArgumentError, "--cores must be a positive integer")

    unless options[:timeout] >= 0,
      do: raise(ArgumentError, "--timeout must be seconds >= 0 (0 disables the deadline)")

    for key <- [:max_samples, :n_threads], Keyword.has_key?(options, key) do
      unless options[key] > 0,
        do: raise(ArgumentError, "--#{flag_name(key)} must be a positive integer")
    end

    for key <- [:max_steps, :seed], Keyword.has_key?(options, key) do
      unless options[key] >= 0,
        do: raise(ArgumentError, "--#{flag_name(key)} must be a non-negative integer")
    end

    if Keyword.has_key?(options, :verbosity) do
      unless options[:verbosity] in 0..5,
        do: raise(ArgumentError, "--verbosity must be between 0 and 5")

      if mode in ~w(simulate all) and options[:verbosity] == 0,
        do:
          raise(ArgumentError, "--verbosity must be at least 1 to validate simulation witnesses")
    end

    if Keyword.has_key?(options, :server_endpoint) do
      case Regex.run(~r/^[a-zA-Z0-9.]+:([0-9]+)$/, options[:server_endpoint]) do
        [_, port] ->
          unless String.to_integer(port) in 1..65535,
            do: raise(ArgumentError, "--server-endpoint port must be between 1 and 65535")

        _ ->
          raise(
            ArgumentError,
            "--server-endpoint must be HOST:PORT with a port between 1 and 65535"
          )
      end
    end

    {mode, options}
  end

  @doc "生成带有用户参数覆盖值的 Quint argv 列表, 不启动工具。"
  def commands(mode, options, root \\ @root) do
    suite = options[:suite]

    commands =
      if(suite == "supplemental" and mode == "verify", do: [], else: quick(root, suite)) ++
        if(mode in ~w(simulate all), do: simulations(suite), else: []) ++
        if(mode in ~w(verify all), do: bounds(suite), else: [])

    Enum.map(commands, fn [command | _] = argv ->
      Enum.reduce(Map.get(@command_options, command, []), argv, fn key, argv ->
        if Keyword.has_key?(options, key) do
          flag = "--#{flag_name(key)}"
          value = to_string(options[key])

          case Enum.find_index(argv, &(&1 == flag)) do
            nil -> argv ++ [flag, value]
            index -> List.replace_at(argv, index + 1, value)
          end
        else
          argv
        end
      end)
    end)
  end

  defp flag_name(key), do: key |> Atom.to_string() |> String.replace("_", "-")

  defp quick(_root, "core") do
    Enum.map(~w(model small composition core_test recovery recovery_test), fn name ->
      ["typecheck", "spec/quint/core/#{name}.qnt"]
    end) ++
      [
        test("spec/quint/core/recovery_test.qnt", "20261014"),
        test("spec/quint/core/core_test.qnt", "20261014") ++ ["--match", ".*Test"]
      ]
  end

  defp quick(root, "supplemental") do
    Enum.map(Path.wildcard(Path.join(root, "spec/quint/*.qnt")), fn path ->
      ["typecheck", Path.relative_to(path, root)]
    end) ++
      Enum.map(
        [
          {"architecture_test", "20261007"},
          {"protocol_test", "20261010"},
          {"negative_controls_test", "20261007"},
          {"formal_test", "20261012"},
          {"progress_test", "20261012"},
          {"review_test", "20261011"}
        ],
        fn {name, seed} ->
          test("spec/quint/#{name}.qnt", seed) ++ ["--match", ".*Test"]
        end
      )
  end

  defp test(source, seed) do
    [
      "test",
      source,
      "--main",
      Path.basename(source, ".qnt"),
      "--backend",
      "typescript",
      "--seed",
      seed
    ]
  end

  defp simulations("core") do
    [
      sample(
        "spec/quint/core/composition.qnt",
        "composition",
        "safety",
        @core_witnesses,
        "60",
        "20261014"
      )
    ]
  end

  defp simulations("supplemental") do
    [
      sample(
        "spec/quint/architecture.qnt",
        "architectureAnalysis",
        "architectureSafety",
        @supplemental_witnesses,
        "100",
        "20261007"
      ),
      sample(
        "spec/quint/architecture.qnt",
        "architectureRecoveryAnalysis",
        "architectureSafety",
        ~w(recoveryConsumedWitness branchNewWorkWitness),
        "100",
        "20261008"
      ) ++ ["--init", "recoveryInit"],
      sample(
        "spec/quint/architecture.qnt",
        "architectureProgressAnalysis",
        "conditionalSafety",
        ~w(recoveryConsumedWitness),
        "40",
        "20261009"
      ) ++ ["--init", "progressInit", "--step", "progressStep"]
    ]
  end

  defp sample(source, main, invariant, witnesses, depth, seed) do
    ["run", source, "--main", main, "--invariant", invariant, "--witnesses"] ++
      witnesses ++
      ["--max-samples", "10000", "--max-steps", depth, "--seed", seed, "--verbosity", "1"]
  end

  defp bounds(suite) do
    Enum.map(bound_models(suite), fn argv ->
      argv ++ ["--random-transitions=false", "--backend", "apalache", "--verbosity", "2"]
    end)
  end

  defp bound_models("core") do
    [
      [
        "verify",
        "spec/quint/core/composition.qnt",
        "--main",
        "composition",
        "--init",
        "init",
        "--step",
        "step",
        "--invariant",
        "safety",
        "--max-steps",
        "10"
      ]
    ]
  end

  defp bound_models("supplemental") do
    [
      [
        "verify",
        "spec/quint/architecture.qnt",
        "--main",
        "architectureBounded",
        "--invariant",
        "modelCheckSafety",
        "--max-steps",
        "10"
      ],
      [
        "verify",
        "spec/quint/architecture.qnt",
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
      ]
    ]
  end

  defp execute(["verify" | _] = argv, options, root) do
    config =
      Path.join(
        System.tmp_dir!(),
        "beamlet-quint-#{System.pid()}-#{System.unique_integer([:positive])}.json"
      )

    File.write!(config, ~s({"checker":{"tuning":{"z3.smt.threads":"#{options[:cores]}"}}}\n))

    try do
      argv = argv ++ ["--apalache-config", config]

      IO.puts("$ quint #{Enum.join(argv, " ")}")

      {_, code} =
        System.cmd("timeout", ["--kill-after=5s", "#{options[:timeout]}s", "quint" | argv],
          cd: root,
          stderr_to_stdout: true,
          into: IO.binstream(:stdio, :line)
        )

      if code == 124,
        do: IO.puts(:stderr, "INCONCLUSIVE: --timeout elapsed; requested bound was not completed")

      code
    after
      File.rm!(config)
    end
  end

  defp execute(["run" | _] = argv, _options, root) do
    IO.puts("$ quint #{Enum.join(argv, " ")}")
    {output, code} = System.cmd("quint", argv, cd: root, stderr_to_stdout: true)
    IO.binwrite(output)

    witnesses =
      argv
      |> Enum.drop_while(&(&1 != "--witnesses"))
      |> Enum.drop(1)
      |> Enum.take_while(&(not String.starts_with?(&1, "--")))

    {message, coverage_code} = validate_witnesses(output, witnesses)
    if code == 0, do: IO.write(message)
    if code == 0, do: coverage_code, else: code
  end

  defp execute(argv, _options, root) do
    IO.puts("$ quint #{Enum.join(argv, " ")}")

    {_, code} =
      System.cmd("quint", argv,
        cd: root,
        stderr_to_stdout: true,
        into: IO.binstream(:stdio, :line)
      )

    code
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
end

unless Process.whereis(Mix.ProjectStack) != nil and Mix.Project.get() != nil do
  System.halt(Beamlet.Quint.main(System.argv()))
end

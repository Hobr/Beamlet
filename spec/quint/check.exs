# Mix 别名与直接 Elixir CLI 共用的薄命令入口。
defmodule Beamlet.Quint do
  @root Path.expand("../..", __DIR__)
  @usage "usage: mix quint [quick|simulate|verify|all] [--suite core|supplemental] [--cores N] [--timeout SECONDS]"
  @core_witnesses ~w(intentWitness entryWitness unknownWitness recoveryWitness consumedWitness recoveryConsumedWitness branchWorkWitness inconclusiveWitness failedUnknownWitness failedReplyWitness)
  @supplemental_witnesses ~w(inputWitness commitWitness admissionWitness entryWitness unknownWitness observationWitness repeatWitness settlementWitness consumptionWitness recoveryConsumedWitness branchNewWorkWitness forkWitness finishedWitness failedWitness disposalWitness evaluateWitness precheckWitness completeWitness auditWitness suspendWitness resumeWitness takeoverWitness controllerWitness controllerReadyWitness ownerDeathWitness disconnectWitness reconnectWitness providerWitness providerFaultWitness retryWitness rejectWitness lostAckWitness staleWitness lostProposalWitness writesWitness uiWitness authWitness permissionWitness)

  def main(args, root \\ @root) do
    {mode, options} = parse(args)
    suite = options[:suite]

    commands =
      if(suite == "supplemental" and mode == "verify", do: [], else: quick(root, suite)) ++
        if(mode in ~w(simulate all), do: simulations(suite), else: []) ++
        if(mode in ~w(verify all), do: bounds(suite), else: [])

    Enum.reduce_while(commands, 0, fn argv, _ ->
      case execute(argv, options, root) do
        0 -> {:cont, 0}
        code -> {:halt, code}
      end
    end)
  rescue
    error ->
      IO.puts(:stderr, Exception.message(error))
      2
  end

  def parse(args) do
    {options, positional, invalid} =
      OptionParser.parse(args, strict: [suite: :string, cores: :integer, timeout: :integer])

    options = Keyword.merge([suite: "core", cores: 8, timeout: 0], options)
    mode = if positional == [], do: "all", else: List.first(positional)

    unless invalid == [] and length(positional) <= 1 and mode in ~w(quick simulate verify all) and
             options[:suite] in ~w(core supplemental),
           do: raise(ArgumentError, @usage)

    unless options[:cores] > 0, do: raise(ArgumentError, "--cores must be a positive integer")

    unless options[:timeout] >= 0,
      do: raise(ArgumentError, "--timeout must be seconds >= 0 (0 disables the deadline)")

    {mode, options}
  end

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

  defp bounds("core") do
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

  defp bounds("supplemental") do
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
      argv =
        argv ++
          [
            "--random-transitions=false",
            "--backend",
            "apalache",
            "--apalache-config",
            config,
            "--verbosity",
            "2"
          ]

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

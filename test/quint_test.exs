defmodule Beamlet.QuintTest do
  use ExUnit.Case, async: true

  test "CLI options default to eight threads without a deadline" do
    assert {"all", options} = Beamlet.Quint.parse([])
    assert options[:suite] == "core"
    assert options[:cores] == 8
    assert options[:timeout] == 0

    assert {"verify", options} =
             Beamlet.Quint.parse(["verify", "--cores", "16", "--timeout", "900"])

    assert options[:cores] == 16
    assert options[:timeout] == 900

    assert {"verify", options} =
             Beamlet.Quint.parse(["--suite", "supplemental", "verify", "--timeout", "0"])

    assert options[:suite] == "supplemental"
    assert options[:timeout] == 0
  end

  test "suite defaults keep their original seeds, sample counts and depths" do
    for suite <- ~w(core supplemental) do
      {mode, options} = Beamlet.Quint.parse(["all", "--suite", suite])
      commands = Beamlet.Quint.commands(mode, options)
      tests = Enum.filter(commands, &(hd(&1) == "test"))
      runs = Enum.filter(commands, &(hd(&1) == "run"))
      verifies = Enum.filter(commands, &(hd(&1) == "verify"))

      assert Enum.all?(
               tests,
               &(["--backend", "typescript"] in Enum.chunk_every(&1, 2, 1, :discard))
             )

      assert Enum.all?(tests, &("--max-samples" not in &1))

      assert Enum.all?(
               runs,
               &(["--max-samples", "10000"] in Enum.chunk_every(&1, 2, 1, :discard))
             )

      assert Enum.all?(runs, &(["--verbosity", "1"] in Enum.chunk_every(&1, 2, 1, :discard)))
      assert Enum.all?(verifies, &(["--verbosity", "2"] in Enum.chunk_every(&1, 2, 1, :discard)))

      if suite == "core" do
        assert Enum.all?(tests, &(["--seed", "20261014"] in Enum.chunk_every(&1, 2, 1, :discard)))
        assert [run] = runs
        assert ["--max-steps", "60"] in Enum.chunk_every(run, 2, 1, :discard)
        assert [verify] = verifies
        assert ["--max-steps", "10"] in Enum.chunk_every(verify, 2, 1, :discard)
      else
        assert Enum.map(runs, &option_value(&1, "--seed")) == ~w(20261007 20261008 20261009)
        assert Enum.map(runs, &option_value(&1, "--max-steps")) == ~w(100 100 40)
        assert Enum.map(verifies, &option_value(&1, "--max-steps")) == ~w(10 8)
      end
    end
  end

  test "manual options replace defaults once and only reach supported commands" do
    for suite <- ~w(core supplemental) do
      {mode, options} =
        Beamlet.Quint.parse([
          "all",
          "--suite",
          suite,
          "--max-samples",
          "25",
          "--max-steps",
          "3",
          "--seed",
          "42",
          "--verbosity",
          "3",
          "--n-threads",
          "2",
          "--match",
          "recovery.*Test",
          "--server-endpoint",
          "localhost:8823"
        ])

      for [command | _] = argv <- Beamlet.Quint.commands(mode, options) do
        expected =
          case command do
            "typecheck" ->
              []

            "test" ->
              [max_samples: "25", seed: "42", verbosity: "3", match: "recovery.*Test"]

            "run" ->
              [max_samples: "25", max_steps: "3", seed: "42", verbosity: "3", n_threads: "2"]

            "verify" ->
              [max_steps: "3", verbosity: "3", server_endpoint: "localhost:8823"]
          end

        for key <- [
              :max_samples,
              :max_steps,
              :seed,
              :verbosity,
              :n_threads,
              :match,
              :server_endpoint
            ] do
          flag = "--" <> String.replace(Atom.to_string(key), "_", "-")

          if Keyword.has_key?(expected, key) do
            assert Enum.count(argv, &(&1 == flag)) == 1
            assert option_value(argv, flag) == expected[key]
          else
            refute flag in argv
          end
        end
      end
    end
  end

  test "zero depth and seed are allowed and quiet output is limited to modes without sampling" do
    assert {"verify", options} =
             Beamlet.Quint.parse([
               "verify",
               "--max-steps",
               "0",
               "--seed",
               "0",
               "--verbosity",
               "0"
             ])

    assert options[:max_steps] == 0
    assert options[:seed] == 0
    assert options[:verbosity] == 0
    assert {"quick", _} = Beamlet.Quint.parse(["quick", "--verbosity", "0"])
  end

  test "help lists manual options without launching tools" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert Beamlet.Quint.main(["--help"], "/does/not/exist") == 0
      end)

    assert output =~ "--max-samples"
    assert output =~ "--max-steps"
    assert output =~ "--n-threads"
    refute output =~ "$ quint"
  end

  test "invalid modes and numeric options are rejected before launching tools" do
    for args <- [
          ["bad"],
          ["quick", "extra"],
          ["--suite", "bad"],
          ["--unknown"],
          ["--cores", "0"],
          ["--cores", "-1"],
          ["--cores", "1.5"],
          ["--cores"],
          ["--timeout", "-1"],
          ["--timeout", "1.5"],
          ["--timeout", "oops"],
          ["--timeout"],
          ["--max-samples", "0"],
          ["--max-samples", "-1"],
          ["--max-samples", "1.5"],
          ["--max-samples"],
          ["--max-steps", "-1"],
          ["--max-steps", "oops"],
          ["--max-steps"],
          ["--seed", "-1"],
          ["--seed", "oops"],
          ["--seed"],
          ["--verbosity", "-1"],
          ["--verbosity", "6"],
          ["--verbosity", "1.5"],
          ["--verbosity"],
          ["simulate", "--verbosity", "0"],
          ["all", "--verbosity", "0"],
          ["--n-threads", "0"],
          ["--n-threads", "-1"],
          ["--n-threads", "oops"],
          ["--n-threads"],
          ["--match"],
          ["--server-endpoint"],
          ["--server-endpoint", "localhost"],
          ["--server-endpoint", "localhost:0"],
          ["--server-endpoint", "localhost:65536"],
          ["--server-endpoint", ":8822"]
        ] do
      assert_raise ArgumentError, fn -> Beamlet.Quint.parse(args) end
    end
  end

  test "sampling requires every requested witness to have a positive count" do
    output = "first was witnessed in 3 trace(s)\nsecond was witnessed in 1 trace(s)\n"
    assert {_, 0} = Beamlet.Quint.validate_witnesses(output, ~w(first second))
    assert {_, 1} = Beamlet.Quint.validate_witnesses(output, ~w(first missing))

    assert {_, 1} =
             Beamlet.Quint.validate_witnesses("first was witnessed in 0 trace(s)\n", ["first"])
  end

  defp option_value(argv, flag) do
    argv |> Enum.drop_while(&(&1 != flag)) |> Enum.at(1)
  end
end

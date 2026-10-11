defmodule Mix.Tasks.Beamlet.Check do
  use Mix.Task

  @shortdoc "Check Beamlet's Quint specifications"
  @moduledoc """
  Runs Quint directly, without a shell.

      mix beamlet.check
      mix beamlet.check --phase test
      mix beamlet.check --samples 5000 --directed-samples 1000 --jobs 4 --log-dir /tmp/beamlet-checks

  Phases: all (default), typecheck, test, simulate, mutations.
  Defaults: 5,000 core samples, 1,000 directed samples, at most 100 steps,
  input seed 42, and four independent Quint processes.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          samples: :integer,
          directed_samples: :integer,
          jobs: :integer,
          log_dir: :string,
          phase: :string
        ]
      )

    if rest != [] or invalid != [],
      do: Mix.raise("Invalid arguments: #{inspect(rest ++ invalid)}")

    config = %{
      samples: Keyword.get(opts, :samples, 5000),
      directed_samples: Keyword.get(opts, :directed_samples, 1000),
      jobs: Keyword.get(opts, :jobs, 4),
      log_dir: Keyword.get(opts, :log_dir),
      phase: Keyword.get(opts, :phase, "all")
    }

    for key <- [:samples, :directed_samples, :jobs] do
      if config[key] < 1, do: Mix.raise("--#{key} must be positive")
    end

    unless config.phase in ~w(all typecheck test simulate mutations),
      do: Mix.raise("Unknown phase: #{config.phase}")

    Beamlet.QuintChecks.run(config)
  end
end

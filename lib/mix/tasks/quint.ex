defmodule Mix.Tasks.Quint do
  use Mix.Task

  @shortdoc "Check Beamlet's Quint specifications"
  @moduledoc """
  Runs Quint directly, without a shell.

      mix quint
      mix quint typecheck
      mix quint test
      mix quint simulate --samples 5000 --directed-samples 1000 --jobs 4 --threads 4 --log-dir /tmp/beamlet-checks
      mix quint mutations
      mix quint all

  Usage: mix quint [phase] [options].
  Phases: all (default), typecheck, test, simulate, mutations.
  Defaults: 5,000 core samples, 1,000 directed samples, at most 100 steps,
  input seed 42, and four independent Quint processes. Rust simulation threads
  default to max(div(online schedulers, jobs), 1); --threads overrides this.
  Single-sample mutation counterexamples always use one simulation thread.
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
          threads: :integer,
          log_dir: :string
        ]
      )

    if length(rest) > 1 or invalid != [],
      do: Mix.raise("Invalid arguments: #{inspect(rest ++ invalid)}")

    phase = List.first(rest) || "all"

    unless phase in ~w(all typecheck test simulate mutations),
      do: Mix.raise("Unknown phase: #{phase}. Usage: mix quint [phase] [options]")

    jobs = Keyword.get(opts, :jobs, 4)
    default_threads = max(div(System.schedulers_online(), max(jobs, 1)), 1)

    config = %{
      samples: Keyword.get(opts, :samples, 5000),
      directed_samples: Keyword.get(opts, :directed_samples, 1000),
      jobs: jobs,
      threads: Keyword.get(opts, :threads, default_threads),
      log_dir: Keyword.get(opts, :log_dir),
      phase: phase
    }

    for key <- [:samples, :directed_samples, :jobs, :threads] do
      if config[key] < 1, do: Mix.raise("--#{key} must be positive")
    end

    Mix.QuintChecks.run(config)
  end
end

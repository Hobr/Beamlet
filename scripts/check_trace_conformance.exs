# Run at the repository root: mix run scripts/check_trace_conformance.exs
# --suite all (default), traces, worker, caller, or oracles; --seed 42
Code.require_file("conformance/driver.exs", __DIR__)

defmodule Beamlet.TraceConformance do
  alias Beamlet.Specs.Trace
  @root Path.expand("..", __DIR__)

  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [suite: :string, seed: :integer])
    suite = Keyword.get(opts, :suite, "all")
    seed = Keyword.get(opts, :seed, 42)

    unless rest == [] and invalid == [] and suite in ~w(all traces worker caller oracles) and
             seed >= 0,
           do:
             raise(
               ArgumentError,
               "usage: --suite all|traces|worker|caller|oracles --seed NONNEGATIVE_INTEGER"
             )

    if suite in ~w(all traces worker), do: replay("worker", Enum.to_list(0..3), seed)
    if suite in ~w(all traces caller), do: replay("caller", Enum.to_list(0..2), seed)
    if suite in ~w(all oracles), do: oracles()
  end

  defp replay(profile, variants, seed) do
    directory = Trace.prepare(@root, profile, variants)

    count =
      Enum.reduce(variants, 0, fn variant, count ->
        {stem, rows} = Trace.plan!(directory, variant, seed)
        state = Beamlet.TraceDriver.start(directory, stem, profile)

        try do
          Trace.replay!(directory, stem, rows, state, &Beamlet.TraceDriver.drive/2)
        after
          Beamlet.TraceDriver.close_observer()
          Beamlet.TraceDriver.close(state)
        end

        count + length(rows)
      end)

    IO.puts(
      "#{profile} trace conformance: #{length(variants)} histories, #{count} checkpoints passed; seed=#{seed}; artifacts: #{directory}"
    )
  end

  defp oracles do
    for {script, cwd} <- [
          {"check_domain_conformance.exs", "apps/beamlet"},
          {"check_reconciliation_conformance.exs", "apps/beamlet"},
          {"check_resource_conformance.exs", "."}
        ] do
      path = Path.join(@root, "scripts/#{script}")

      {output, status} =
        System.cmd("mix", ["run", path], cd: Path.join(@root, cwd), stderr_to_stdout: true)

      IO.write(output)
      if status != 0, do: raise("#{script} failed with exit #{status}")
    end
  end
end

Beamlet.TraceConformance.run(System.argv())

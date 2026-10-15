# Example benchmark to verify the Benchee setup, not a Beamlet performance baseline.
# Run from the umbrella root with `mix bench`.
Benchee.run(
  %{
    "Enum.map" => fn input -> Enum.map(input, &(&1 * 2)) end,
    "comprehension" => fn input -> for value <- input, do: value * 2 end
  },
  inputs: %{
    "small" => Enum.to_list(1..100),
    "large" => Enum.to_list(1..10_000)
  },
  warmup: 1,
  time: 2,
  memory_time: 1
)

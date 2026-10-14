defmodule Beamlet.Specs.Trace do
  @moduledoc """
  Finite Quint trace replay with retained, independently generated expectations.
  Profiles record observable checkpoints; drivers return the complete projection
  for each checkpoint. Equality is exact: missing and unexpected fields fail.
  """

  def prepare(root, profile, variants) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "beamlet-traces-#{Base.encode16(:crypto.strong_rand_bytes(12))}"
      )

    File.mkdir_p!(directory)
    File.cp_r!(Path.join(root, "model/quint"), Path.join(directory, "model"))
    profile_path = Path.join(root, "scripts/conformance/#{profile}.qnt")
    File.cp!(profile_path, Path.join(directory, "profile.qnt"))

    source =
      Enum.map_join(variants, "\n", fn variant ->
        "module oracle#{variant} { import #{profile}Trace(VARIANT=#{variant}).* from \"./profile\" }"
      end)

    File.write!(Path.join(directory, "oracle.qnt"), source)
    invoke!(directory, ["typecheck", Path.join(directory, "oracle.qnt")], "typecheck")

    hashes =
      Path.wildcard(Path.join(directory, "model/**/*.qnt"))
      |> Map.new(fn path -> {Path.relative_to(path, directory), digest(File.read!(path))} end)

    {version, 0} = System.cmd("quint", ["--version"])

    write_json!(Path.join(directory, "manifest.json"), %{
      "profile" => profile,
      "variants" => variants,
      "quint" => String.trim(version),
      "profile_sha256" => digest(File.read!(profile_path)),
      "models_sha256" => hashes
    })

    directory
  end

  def plan!(directory, variant, seed) do
    stem = "variant-#{variant}-seed-#{seed}"
    path = Path.join(directory, stem <> ".itf.json")

    invoke!(
      directory,
      [
        "run",
        Path.join(directory, "oracle.qnt"),
        "--main",
        "oracle#{variant}",
        "--init",
        "traceInit",
        "--step",
        "traceStep",
        "--max-samples",
        "1",
        "--max-steps",
        "0",
        "--backend",
        "rust",
        "--n-threads",
        "1",
        "--seed",
        to_string(seed),
        "--out-itf",
        path
      ],
      stem
    )

    write_json!(Path.join(directory, stem <> ".run.json"), %{
      "seed" => seed,
      "variant" => variant,
      "main" => "oracle#{variant}",
      "backend" => "rust",
      "max_samples" => 1,
      "max_steps" => 0,
      "threads" => 1
    })

    rows = path |> File.read!() |> :json.decode() |> rows!()
    write_json!(Path.join(directory, stem <> ".expected.json"), rows)
    {stem, rows}
  end

  def rows!(%{"states" => states}) when is_list(states) and states != [] do
    checkpoint_fields =
      states
      |> List.last()
      |> Enum.filter(fn {key, _} ->
        key == "rows" or String.ends_with?(key, "::rows")
      end)

    encoded =
      case checkpoint_fields do
        [{_key, encoded}] -> encoded
        _ -> raise ArgumentError, "ITF must contain exactly one rows variable"
      end

    rows = decode(encoded)

    unless is_list(rows) and rows != [] and Enum.all?(rows, &(is_map(&1) and is_binary(&1["op"]))),
      do:
        raise(ArgumentError, "ITF must contain a nonempty checkpoint list with operation labels")

    rows
  end

  def rows!(_document), do: raise(ArgumentError, "ITF must contain a nonempty states list")

  def replay!(directory, stem, rows, initial, driver) when is_function(driver, 2) do
    observed = Path.join(directory, stem <> ".observed.jsonl")
    File.write!(observed, "")

    Enum.with_index(rows)
    |> Enum.reduce(initial, fn {expected, index}, state ->
      try do
        {next, actual} = driver.(state, expected["op"])
        write_line!(observed, %{"index" => index, "actual" => actual})

        if actual !== expected do
          write_json!(Path.join(directory, stem <> ".failure.json"), %{
            "index" => index,
            "op" => expected["op"],
            "expected" => expected,
            "actual" => actual
          })

          raise "trace mismatch at #{stem} checkpoint #{index} (#{expected["op"]}); artifacts: #{directory}"
        end

        next
      rescue
        error ->
          write_json!(Path.join(directory, stem <> ".error.json"), %{
            "index" => index,
            "op" => expected["op"],
            "error" => Exception.message(error)
          })

          reraise error, __STACKTRACE__
      end
    end)
  end

  def decode(%{"#bigint" => n}) when is_binary(n), do: String.to_integer(n)
  def decode(%{"#list" => values}), do: Enum.map(values, &decode/1)
  def decode(%{"#set" => values}), do: Enum.map(values, &decode/1)
  def decode(values) when is_list(values), do: Enum.map(values, &decode/1)
  def decode(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, decode(v)} end)
  def decode(value), do: value

  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp write_line!(path, value), do: File.write!(path, [:json.encode(value), "\n"], [:append])
  defp write_json!(path, value), do: File.write!(path, [:json.encode(value), "\n"])

  defp invoke!(directory, args, label) do
    {output, status} = System.cmd("quint", args, stderr_to_stdout: true)
    File.write!(Path.join(directory, label <> ".log"), output)
    if status != 0, do: raise("Quint failed (#{status}); artifacts: #{directory}")
  end
end

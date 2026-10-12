defmodule Beamlet.QuintStructureTest do
  use ExUnit.Case, async: true

  @root Path.expand("../model/quint", __DIR__)
  @entries ~w(beamletExecution.qnt beamletNormalUse.qnt beamletRecovery.qnt)
  @extension_types ~r/\b(?:Decision|ReconciliationCommand|RuleRegistration|Supersession|DispositionBinding)\b/

  test "first-release entries have no transitive governance or test dependency" do
    for entry <- @entries,
        path <- reachable(Path.join(@root, entry), MapSet.new()) do
      relative = Path.relative_to(path, @root)
      refute relative == "beamletCore.qnt", "#{entry} imports the composition reference"
      refute String.starts_with?(relative, ["scenarios/", "mutations/"]), relative
      refute String.ends_with?(relative, "_test.qnt"), relative

      refute File.read!(path) =~ @extension_types,
             "#{entry} imports extension types via #{relative}"
    end
  end

  test "Quint imports are acyclic and each source stays within the module size budget" do
    paths = Path.wildcard(Path.join(@root, "**/*.qnt"))

    for path <- paths do
      assert length(String.split(File.read!(path), "\n", trim: false)) <= 201,
             "#{path} exceeds 200 lines"
    end

    Enum.reduce(paths, MapSet.new(), &assert_acyclic(&1, MapSet.new(), &2))
  end

  defp imports(path) do
    Regex.scan(~r/\bfrom\s+"([^"]+)"/, File.read!(path), capture: :all_but_first)
    |> Enum.map(fn [relative] ->
      suffix = if Path.extname(relative) == ".qnt", do: "", else: ".qnt"
      Path.expand(relative <> suffix, Path.dirname(path))
    end)
    |> Enum.uniq()
  end

  defp reachable(path, visited) do
    if MapSet.member?(visited, path) do
      visited
    else
      Enum.reduce(imports(path), MapSet.put(visited, path), &reachable/2)
    end
  end

  defp assert_acyclic(path, ancestors, checked) do
    refute MapSet.member?(ancestors, path), "cyclic Quint import at #{path}"

    if MapSet.member?(checked, path) do
      checked
    else
      imports(path)
      |> Enum.reduce(checked, &assert_acyclic(&1, MapSet.put(ancestors, path), &2))
      |> MapSet.put(path)
    end
  end
end

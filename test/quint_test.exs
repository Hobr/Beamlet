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
          ["--timeout"]
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
end

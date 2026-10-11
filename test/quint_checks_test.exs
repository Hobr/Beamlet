defmodule Beamlet.QuintChecksTest do
  use ExUnit.Case, async: true

  setup do
    dir = Path.join(System.tmp_dir!(), "beamlet-check-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{trace: Path.join(dir, "counterexample.itf.json")}
  end

  test "an invariant violation requires its generated trace", %{trace: trace} do
    File.write!(trace, ~s({"states": [{}, {}]}))
    assert :ok = Beamlet.QuintChecks.validate_counterexample!(1, "Invariant violated", trace)
  end

  test "parse and runtime failures never count as detected mutations", %{trace: trace} do
    File.write!(trace, ~s({"states": [{}, {}]}))

    for output <- ["Error [QNT404]: Name not found", "Runtime error", "No violation found"] do
      assert_raise Mix.Error, fn ->
        Beamlet.QuintChecks.validate_counterexample!(1, output, trace)
      end
    end
  end

  test "success and abnormal termination never count as invariant failures", %{trace: trace} do
    File.write!(trace, ~s({"states": [{}, {}]}))

    for status <- [0, 2, 137] do
      assert_raise Mix.Error, fn ->
        Beamlet.QuintChecks.validate_counterexample!(status, "Invariant violated", trace)
      end
    end
  end

  test "missing or empty traces cannot satisfy the check", %{trace: trace} do
    assert_raise Mix.Error, fn ->
      Beamlet.QuintChecks.validate_counterexample!(1, "Invariant violated", trace)
    end

    File.write!(trace, "")

    assert_raise Mix.Error, fn ->
      Beamlet.QuintChecks.validate_counterexample!(1, "Invariant violated", trace)
    end
  end

  test "invalid CLI options stop before invoking Quint" do
    invalid_numbers =
      for flag <- ~w(--samples --directed-samples --jobs --threads),
          value <- ~w(0 -1 not-an-integer),
          do: [flag, value]

    for args <- invalid_numbers ++ [["--phase", "oops"], ["--unknown"], ["extra"]] do
      assert_raise Mix.Error, ~r/must be positive|Invalid arguments|Unknown phase/, fn ->
        Mix.Tasks.Beamlet.Check.run(args)
      end
    end
  end
end

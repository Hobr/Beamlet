defmodule Beamlet.CLI.I18nTest do
  @moduledoc """
  CLI locale rules: Chinese by default, trusted configuration first,
  `BEAMLET_LANG` next, and a safe fallback for unusable values.

  `Beamlet.CLI.SessionTest` pins English for the behaviour assertions; these
  tests own the resolution order and the rendered copy in both languages.
  """
  use ExUnit.Case
  alias Beamlet.CLI.{Locale, Renderer, Runner, Session}
  alias Beamlet.I18n
  alias Beamlet.I18n.Vocabulary

  @env "BEAMLET_LANG"

  setup do
    previous_locale = Application.fetch_env(:beamlet_cli, :locale)
    previous_default = Application.fetch_env(:beamlet_cli, :default_locale)
    previous_env = System.get_env(@env)

    on_exit(fn ->
      restore_env(:locale, previous_locale)
      restore_env(:default_locale, previous_default)
      restore_system_env(previous_env)
      Locale.put("zh_CN")
    end)

    Application.delete_env(:beamlet_cli, :locale)
    Application.put_env(:beamlet_cli, :default_locale, "zh_CN")
    System.delete_env(@env)
    :ok
  end

  test "defaults to Chinese when neither configuration nor environment is set" do
    Application.delete_env(:beamlet_cli, :default_locale)

    assert Locale.locale() == "zh_CN"
    Locale.put()

    assert Renderer.render(:ok) == "成功"
    assert Renderer.render([]) == "（无）"
    assert Renderer.render({:error, :timeout}) == "错误：超时"
    assert Renderer.render(%{status: :running, steps: 0}) =~ "运行中"

    help = Renderer.render(:help)
    assert help =~ "命令 / 策略"
    assert help =~ "配置文件是受信、可执行的运维方自有 Elixir 代码"
    assert help =~ "帮助 | connect <trusted-node>"
    refute help =~ "commands / policy"
  end

  test "trusted configuration wins over BEAMLET_LANG" do
    Application.put_env(:beamlet_cli, :locale, "en")
    System.put_env(@env, "zh_CN")
    assert Locale.locale() == "en"

    Application.put_env(:beamlet_cli, :locale, "zh_CN")
    System.put_env(@env, "en")
    assert Locale.locale() == "zh_CN"

    # The shipped `:default_locale` ranks below the environment, otherwise the
    # documented environment override could never take effect.
    Application.delete_env(:beamlet_cli, :locale)
    Application.put_env(:beamlet_cli, :default_locale, "zh_CN")
    System.put_env(@env, "en")
    assert Locale.locale() == "en"

    System.delete_env(@env)
    assert Locale.locale() == "zh_CN"
  end

  test "BEAMLET_LANG overrides the shipped default and accepts aliases" do
    System.put_env(@env, "en")
    assert Locale.locale() == "en"

    Locale.put()
    assert Renderer.render(:ok) == "ok"
    assert Renderer.render({:error, :alias_exists}) == "error: alias_exists"
    assert Renderer.render(:help) =~ "commands / policy"

    System.put_env(@env, "en-US")
    assert Locale.locale() == "en"

    System.put_env(@env, "zh-cn")
    assert Locale.locale() == "zh_CN"
  end

  test "unusable values are skipped instead of hiding a usable one" do
    Application.put_env(:beamlet_cli, :locale, "klingon")
    System.put_env(@env, "en")
    assert Locale.locale() == "en"

    Application.delete_env(:beamlet_cli, :locale)
    System.put_env(@env, "also-bad")
    assert Locale.locale() == "zh_CN"
  end

  test "the runner installs the locale once, before any line is read" do
    Application.put_env(:beamlet_cli, :locale, "zh_CN")
    System.delete_env(@env)

    assert %{out: chinese} = run(["help"])
    assert chinese =~ "命令 / 策略"
    refute chinese =~ "commands / policy"

    Application.put_env(:beamlet_cli, :locale, "en")
    assert %{out: english} = run(["help"])
    assert english =~ "commands / policy"
    refute english =~ "命令 / 策略"
  end

  test "unknown reasons are rendered as a bounded, translated phrase" do
    Locale.put("zh_CN")
    assert Renderer.render({:error, {:secret, "sentinel"}}) == "错误：请求失败"
    refute Renderer.render({:error, {:secret, "sentinel"}}) =~ "sentinel"

    Locale.put("en")
    assert Renderer.render({:error, {:secret, "sentinel"}}) == "error: request_failed"
  end

  test "shared vocabulary is translated through the shared catalogue" do
    try do
      Locale.put("zh_CN")
      assert I18n.gettext("running") == "运行中"
      assert Vocabulary.reason(:stale_agent) == "Agent 已过期"

      Locale.put("en")
      assert I18n.gettext("running") == "running"
      assert Vocabulary.reason(:stale_agent) == "stale_agent"
    after
      Locale.put("zh_CN")
    end
  end

  # Every command line is consumed once; the runner then sees EOF.
  defp run(lines) do
    Process.put(:i18n_lines, lines)
    parent = self()

    output = fn text -> send(parent, {:out, text}) end

    exit = fn code ->
      send(parent, {:exit, code})
      :ok
    end

    read = fn ->
      case Process.get(:i18n_lines) do
        [line | rest] ->
          Process.put(:i18n_lines, rest)
          line

        [] ->
          :eof
      end
    end

    :ok = Runner.run(Session.new(), read: read, output: output, exit: exit)
    assert_receive {:exit, 0}

    text =
      Stream.repeatedly(fn ->
        receive do
          {:out, chunk} -> chunk
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(&(&1 != nil))
      |> Enum.join("\n")

    %{out: text}
  end

  defp restore_env(key, :error), do: Application.delete_env(:beamlet_cli, key)
  defp restore_env(key, {:ok, value}), do: Application.put_env(:beamlet_cli, key, value)

  defp restore_system_env(nil), do: System.delete_env(@env)
  defp restore_system_env(value), do: System.put_env(@env, value)
end

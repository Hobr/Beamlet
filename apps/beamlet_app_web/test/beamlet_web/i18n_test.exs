defmodule Beamlet.Web.I18nTest do
  @moduledoc """
  Locale behaviour of the Web surface.

  Every other Web test pins the language through the explicit `en` session
  locale (see `Beamlet.Web.ConnCase`) so it keeps asserting behaviour instead of
  copy. These tests own the locale rules themselves: the shipped default is
  Chinese, `?locale=` and the session both switch it, unknown values fall back
  safely, and the Chinese pages contain no leftover English or internal terms.
  """
  use Beamlet.Web.ConnCase
  import Phoenix.LiveViewTest
  alias Beamlet.Web.{Handles, Locale}

  @chinese_heading "你想做什么？"
  @english_heading "What would you like to do?"

  describe "shipped default" do
    test "a request without session or query renders Chinese" do
      # A session-less connection is what a first-time visitor sends.
      conn = get(Phoenix.ConnTest.build_conn(), ~p"/")
      html = html_response(conn, 200)

      assert html =~ @chinese_heading
      assert html =~ ~s(<html lang="zh-CN">)
      refute html =~ @english_heading
      assert get_session(conn, "locale") == nil
    end

    test "the canonical default is shared with the CLI" do
      assert Beamlet.I18n.Locale.default() == "zh_CN"
      assert Application.fetch_env!(:beamlet_app_web, :default_locale) == "zh_CN"
      assert Locale.resolve(nil, nil) == "zh_CN"
    end
  end

  describe "Chinese pages" do
    @tag locale: "zh_CN"
    test "workbench root and creation form are Chinese", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ @chinese_heading
      assert html =~ "工作台"
      assert html =~ "新建 Agent"
      refute html =~ @english_heading

      {:ok, _new, new_html} = live(conn, ~p"/agents/new")
      assert new_html =~ "创建已停用：没有已配置的公开预设。"
      refute new_html =~ "Creation disabled"
    end

    @tag locale: "zh_CN"
    test "the three management pages are Chinese", %{conn: conn} do
      start_supervised!({Beamlet.Node, roles: [:interaction]})

      for {path, section, expected} <- [
            {~p"/admin/nodes", "节点", ["已收到上次观测", "刷新观测"]},
            {~p"/admin/presets", "预设", ["目录读取不可用：不可用。保留上次观测；当前事实未知"]},
            {~p"/admin/diagnostics", "诊断", ["未解析到精确的实时句柄。请从已有 Agent 工作区打开诊断。"]}
          ] do
        {:ok, view, html} = live(conn, path)

        assert html =~ "工作台"
        assert html =~ "只读 " <> section
        assert html =~ "导航不等于授权。仍适用受信部署控制。"
        assert html =~ "上次观测（Web 接收）："

        eventually(fn ->
          rendered = render(view)
          for text <- expected, do: assert(rendered =~ text)
        end)
      end
    end

    @tag locale: "zh_CN"
    test "node read results are Chinese", %{conn: conn} do
      start_supervised!({Beamlet.Node, roles: [:interaction]})
      {:ok, view, _html} = live(conn, ~p"/admin/nodes")

      eventually(fn ->
        html = render(view)
        assert html =~ "范围：显式本地 VM 与已配置的受信目标。"
        assert html =~ "公开读取边界：每次调用 32 个目标"
        assert html =~ "连接状态：本地（无需分布式）"
        assert html =~ "读取完整度：完整"
        refute html =~ "Public read bounds"
        refute html =~ "Connection:"
      end)
    end

    @tag locale: "zh_CN"
    test "the Agent workspace is Chinese", %{conn: conn} do
      start_supervised!({Beamlet.Node, roles: [:authority]})
      start_supervised!(Handles)

      {:ok, ref} =
        Beamlet.Agent.start(node(),
          id: "i18n-workspace",
          model: %{
            provider: "deterministic",
            config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}}
          }
        )

      {:ok, handle} = Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})
      {:ok, view, _html} = live(conn, ~p"/agents/#{handle}")

      eventually(fn ->
        html = render(view)
        assert html =~ "Agent 工作区"
        assert html =~ "初始输入：未提交 · 导航：未请求"
        assert html =~ "当前并发活动"
        refute html =~ "Agent workspace"
        refute html =~ "Not submitted"
      end)
    end

    @tag locale: "zh_CN"
    test "no leftover English or internal terms on the sampled Chinese pages", %{conn: conn} do
      pages = [
        ~p"/",
        ~p"/agents/new",
        ~p"/admin/nodes",
        ~p"/admin/presets",
        ~p"/admin/diagnostics"
      ]

      for path <- pages do
        {:ok, _view, html} = live(conn, path)

        for english <- [
              @english_heading,
              "Discover now",
              "Live Agents",
              "New Agent",
              "Navigation is not authorization",
              "What would you like to do?"
            ] do
          refute html =~ english, "#{path} leaked English copy: #{english}"
        end

        for internal <- ["#Function<", "Elixir.Beamlet", "%{", "{{"] do
          refute html =~ internal, "#{path} leaked an internal term: #{internal}"
        end
      end
    end
  end

  describe "switching" do
    @tag locale: "zh_CN"
    test "?locale=en survives in the session and can switch back", %{conn: conn} do
      english = get(conn, ~p"/?locale=en")

      assert html_response(english, 200) =~ @english_heading
      assert html_response(english, 200) =~ ~s(<html lang="en">)
      assert get_session(english, "locale") == "en"

      # Later pages keep English without repeating the query.
      kept = get(english, ~p"/agents/new")
      assert html_response(kept, 200) =~ @english_heading
      refute html_response(kept, 200) =~ @chinese_heading

      chinese = get(kept, ~p"/?locale=zh_CN")
      assert html_response(chinese, 200) =~ @chinese_heading
      assert html_response(get(chinese, ~p"/"), 200) =~ @chinese_heading
    end

    test "locale aliases are canonicalised", %{conn: conn} do
      chinese = get(conn, ~p"/?locale=zh")
      assert html_response(chinese, 200) =~ @chinese_heading
      assert html_response(chinese, 200) =~ ~s(<html lang="zh-CN">)
      assert get_session(chinese, "locale") == "zh_CN"

      english = get(Phoenix.ConnTest.build_conn(), ~p"/?locale=en-us")
      assert html_response(english, 200) =~ @english_heading
      assert html_response(english, 200) =~ ~s(<html lang="en">)
      assert get_session(english, "locale") == "en"
    end

    test "an unknown locale falls back to the default and is never persisted" do
      # No session at all: the only remaining sources are the invalid query value
      # and the configured default.
      conn = get(Phoenix.ConnTest.build_conn(), ~p"/?locale=klingon")
      html = html_response(conn, 200)

      assert html =~ @chinese_heading
      refute html =~ @english_heading
      assert get_session(conn, "locale") == nil
    end

    @tag locale: "zh_CN"
    test "an unknown locale keeps the session choice instead of resetting to English", %{
      conn: conn
    } do
      english = get(conn, ~p"/?locale=en")
      assert get_session(english, "locale") == "en"

      kept = get(english, ~p"/?locale=klingon")
      assert html_response(kept, 200) =~ @english_heading
      assert get_session(kept, "locale") == "en"
    end

    test "a LiveView mount honours the session locale", %{conn: conn} do
      chinese_conn = Plug.Test.init_test_session(conn, %{"locale" => "zh_CN"})
      {:ok, _view, chinese} = live(chinese_conn, ~p"/")
      assert chinese =~ @chinese_heading

      english_conn = Plug.Test.init_test_session(conn, %{"locale" => "en"})
      {:ok, _view, english} = live(english_conn, ~p"/")
      assert english =~ @english_heading
    end

    test "handle_params re-resolves the locale for an already mounted LiveView" do
      Beamlet.I18n.Locale.put("zh_CN")

      try do
        assert Beamlet.I18n.gettext("running") == "运行中"

        socket =
          %Phoenix.LiveView.Socket{}
          |> Phoenix.Component.assign(:locale, "zh_CN")
          |> Locale.on_params(%{"locale" => "en"}, "/admin/nodes?locale=en")

        assert socket.assigns.locale == "en"
        assert socket.assigns.current_path == "/admin/nodes"
        assert socket.assigns.locale_options |> Enum.map(& &1.code) == ["zh_CN", "en"]
        assert Beamlet.I18n.gettext("running") == "running"
      after
        Beamlet.I18n.Locale.put("zh_CN")
      end
    end

    test "the switcher keeps the current path and offers both languages", %{conn: conn} do
      conn = get(conn, ~p"/admin/nodes")
      html = html_response(conn, 200)

      assert html =~ ~s(href="/admin/nodes?locale=zh_CN")
      assert html =~ ~s(href="/admin/nodes?locale=en")
      assert html =~ "中文"
      assert html =~ "English"
    end
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, n) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      receive do
      after
        20 -> eventually(fun, n - 1)
      end
  end
end

defmodule BeamletWeb.ComponentsLiveTest do
  use BeamletWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "form submission validates blank names and escapes the greeting", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/components")
    assert html =~ "Form preview"
    assert html =~ ~s(phx-hook="PetalDropdown")

    view |> form("#preview-form", preview: %{name: "   "}) |> render_submit()
    assert has_element?(view, "#flash-error", "Enter a name.")

    view |> form("#preview-form", preview: %{name: " <script> "}) |> render_submit()
    assert render(view) =~ "Hello, &lt;script&gt;!"
    refute has_element?(view, "#flash-error")
  end

  test "dialog opens and closes through the Petal cancel event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/components")
    refute has_element?(view, "#preview-dialog")

    view |> element("#open-dialog") |> render_click()
    assert has_element?(view, "#preview-dialog [role=dialog]", "A Petal dialog")

    render_click(view, "close_modal")
    refute has_element?(view, "#preview-dialog")
  end

  test "menu notifications can be cleared without losing the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/components")

    view |> element("#preview-actions button", "Show notification") |> render_click()
    assert has_element?(view, "#flash-info", "Notification from the actions menu.")

    render_click(view, "lv:clear-flash", %{"key" => "info"})
    refute has_element?(view, "#flash-info")
    assert has_element?(view, "#client-error[hidden]")
    assert has_element?(view, "#server-error[hidden]")
  end

  defmodule StreamTableLive do
    use BeamletWeb, :live_view

    def mount(_params, _session, socket) do
      {:ok, stream(socket, :items, [%{id: 1, name: "Alpha"}, %{id: 2, name: "Beta"}])}
    end

    def render(assigns) do
      ~H"""
      <.table id="items" rows={@streams.items} row_item={fn {_id, item} -> item end}>
        <:col :let={item} label="Name">{item.name}</:col>
        <:action :let={item}>
          <.button phx-click="delete" phx-value-id={item.id}>Delete {item.name}</.button>
        </:action>
      </.table>
      """
    end

    def handle_event("delete", %{"id" => id}, socket) do
      {:noreply, stream_delete_by_dom_id(socket, :items, "items-#{id}")}
    end
  end

  test "tables retain streamed row ids, row mapping, and action slots", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, StreamTableLive)

    assert has_element?(view, "#items[phx-update=stream] #items-1", "Alpha")
    assert has_element?(view, "#items-2", "Beta")

    view |> element("#items-1 button", "Delete Alpha") |> render_click()

    refute has_element?(view, "#items-1")
    assert has_element?(view, "#items-2", "Beta")
  end
end

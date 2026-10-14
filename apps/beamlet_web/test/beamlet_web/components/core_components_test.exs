defmodule BeamletWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  use BeamletWeb, :html

  import Phoenix.LiveViewTest

  test "buttons retain Phoenix navigation and native form attributes" do
    html = render_component(&navigation_buttons/1, %{})

    assert html =~ ~s(href="/components")
    assert html =~ ~s(data-phx-link="redirect")
    assert html =~ ~s(data-phx-link="patch")
    assert html =~ ~s(href="https://example.com")
    assert html =~ ~s(type="submit")
    assert html =~ ~s(form="profile")
    assert html =~ "pc-button--primary"
    refute html =~ ~s(variant="primary")
  end

  test "disabled navigation buttons do not navigate" do
    html = render_component(&disabled_button/1, %{})
    assert html =~ "<button"
    assert html =~ "disabled"
    refute html =~ "href="
    refute html =~ "phx-click="
  end

  test "labelled form fields retain errors, names, values, and escaping" do
    form =
      to_form(%{"name" => "<script>"},
        as: :profile,
        errors: [name: {"should be at least %{count} character(s)", [count: 2]}]
      )

    html = render_component(&input/1, field: form[:name], label: "Name")

    assert html =~ ~s(for="profile_name")
    assert html =~ ~s(name="profile[name]")
    assert html =~ "&lt;script&gt;"
    assert html =~ "should be at least 2 character(s)"
    assert html =~ "pc-text-input"
    refute html =~ "<script>"
  end

  test "unused fields suppress validation errors" do
    form =
      to_form(%{"name" => "", "_unused_name" => ""},
        as: :profile,
        errors: [name: {"can't be blank", []}]
      )

    html = render_component(&input/1, field: form[:name], label: "Name")
    refute html =~ "can't be blank"
    refute html =~ "can&#39;t be blank"
  end

  test "checkbox, select, and textarea retain their form semantics" do
    html = render_component(&form_controls/1, %{})

    assert html =~ ~s(type="hidden")
    assert html =~ ~s(value="false")
    assert html =~ ~s(type="checkbox")
    assert html =~ "checked"
    document = LazyHTML.from_fragment(html)
    assert Enum.count(LazyHTML.query(document, ~s(option[value="b"][selected]))) == 1
    assert LazyHTML.query(document, "textarea") |> LazyHTML.attribute("rows") == ["7"]
    assert Enum.count(LazyHTML.query(document, ~s(input[name="enabled"][required]))) == 1
    assert html =~ "A &amp; B"
  end

  test "multiple selects keep array names and disabled checkboxes submit nothing" do
    form = to_form(%{"choices" => ["b"]}, as: :profile)

    html =
      render_component(&input/1,
        field: form[:choices],
        type: "select",
        multiple: true,
        options: [{"B", "b"}]
      )

    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "select[multiple]") |> LazyHTML.attribute("name") == [
             "profile[choices][]"
           ]

    disabled =
      render_component(&input/1, type: "checkbox", name: "enabled", value: true, disabled: true)

    document = LazyHTML.from_fragment(disabled)
    assert Enum.count(LazyHTML.query(document, "input[type=checkbox][disabled]")) == 1
    assert Enum.count(LazyHTML.query(document, "input[type=hidden]:not([disabled])")) == 0
  end

  test "native Petal fields use the application's validation translator" do
    assert PetalComponents.Helpers.translate_error({"must be %{count}", [count: 3]}) ==
             BeamletWeb.CoreComponents.translate_error({"must be %{count}", [count: 3]})
  end

  defp navigation_buttons(assigns) do
    ~H"""
    <.button navigate={~p"/components"}>Navigate</.button>
    <.button patch={~p"/components"}>Patch</.button>
    <.button href="https://example.com">External</.button>
    <.button type="submit" form="profile" variant="primary">Save</.button>
    """
  end

  defp disabled_button(assigns) do
    ~H"""
    <.button navigate={~p"/components"} disabled phx-click="save">Disabled</.button>
    """
  end

  defp form_controls(assigns) do
    ~H"""
    <.input type="checkbox" name="enabled" value={true} label="Enabled" required />
    <.input type="select" name="choice" value="b" options={[{"A", "a"}, {"B", "b"}]} />
    <.input type="textarea" name="notes" value="A & B" rows="7" />
    """
  end
end

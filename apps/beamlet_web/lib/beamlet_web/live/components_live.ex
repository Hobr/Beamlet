defmodule BeamletWeb.ComponentsLive do
  @moduledoc "A small interactive reference for the web application's shared components."
  use BeamletWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Components",
       form: to_form(%{"name" => ""}, as: :preview),
       preview_name: nil,
       show_modal: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Components
        <:subtitle>Try the building blocks used throughout Beamlet Web.</:subtitle>
      </.header>

      <div class="mt-6 grid gap-6 lg:grid-cols-2">
        <.card>
          <.card_content heading="Form preview">
            <p class="mb-6 text-sm text-gray-600 dark:text-gray-400">
              Enter a name to preview a greeting. This example does not save your data.
            </p>
            <.form for={@form} id="preview-form" phx-submit="preview">
              <.input field={@form[:name]} label="Name" placeholder="Your name" />
              <.button type="submit" variant="primary">Preview greeting</.button>
            </.form>
            <.alert :if={@preview_name} color="success" class="mt-6">
              Hello, {@preview_name}!
            </.alert>
          </.card_content>
        </.card>

        <.card>
          <.card_content heading="Menus and dialogs">
            <p class="mb-6 text-sm text-gray-600 dark:text-gray-400">
              Open a dialog or use the menu to show a notification.
            </p>
            <div class="flex flex-wrap items-center gap-4">
              <.button id="open-dialog" phx-click="open_modal" variant="primary">
                Open dialog
              </.button>
              <.dropdown label="Actions" options_container_id="preview-actions" align="start">
                <.dropdown_menu_item
                  link_type="button"
                  phx-click="notify"
                  label="Show notification"
                />
              </.dropdown>
            </div>
          </.card_content>
        </.card>
      </div>

      <.modal :if={@show_modal} id="preview-dialog" title="A Petal dialog">
        <p>Dialogs support Escape, backdrop dismissal, and keyboard focus management.</p>
        <:footer>
          <.button phx-click="close_modal" variant="primary">Done</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("preview", %{"preview" => %{"name" => name}}, socket) do
    form = to_form(%{"name" => name}, as: :preview)

    case String.trim(name) do
      "" ->
        {:noreply,
         assign(socket, form: form, preview_name: nil) |> put_flash(:error, "Enter a name.")}

      name ->
        {:noreply, assign(socket, form: form, preview_name: name) |> clear_flash()}
    end
  end

  def handle_event("open_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, true)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  def handle_event("notify", _params, socket) do
    {:noreply, put_flash(socket, :info, "Notification from the actions menu.")}
  end
end

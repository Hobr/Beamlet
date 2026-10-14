defmodule BeamletWeb.Layouts do
  @moduledoc "Shared application layouts, flash messages, and theme controls."
  use BeamletWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-gray-200 bg-white dark:border-gray-800 dark:bg-gray-900">
      <.container class="flex flex-wrap items-center justify-between gap-4 py-4">
        <.link href={~p"/"} class="flex items-center gap-2 text-lg font-semibold">
          <.icon name="hero-bolt-solid" class="size-6 text-primary-600 dark:text-primary-400" />
          Beamlet
        </.link>
        <nav aria-label={gettext("Main navigation")} class="flex flex-wrap items-center gap-3">
          <.button href={~p"/components"} color="gray" variant="ghost" size="sm">
            {gettext("Components")}
          </.button>
          <.button
            href="https://github.com/phoenixframework/phoenix"
            color="gray"
            variant="ghost"
            size="sm"
          >
            GitHub
          </.button>
          <.theme_toggle />
        </nav>
      </.container>
    </header>

    <main id="main-content" class="py-12 sm:py-20">
      <.container>{render_slot(@inner_block)}</.container>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed right-4 top-4 z-50 w-80 max-w-[calc(100vw-2rem)] space-y-3 sm:w-96"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc "Three-way theme preference; the root script resolves system mode before first paint."
  def theme_toggle(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={gettext("Color theme")}
      class="flex gap-1 rounded-lg border border-gray-200 p-1 dark:border-gray-700"
      phx-mounted={JS.dispatch("phx:sync-theme")}
    >
      <.button
        :for={
          {theme, icon, label} <- [
            {"system", "hero-computer-desktop-micro", gettext("Use system theme")},
            {"light", "hero-sun-micro", gettext("Use light theme")},
            {"dark", "hero-moon-micro", gettext("Use dark theme")}
          ]
        }
        type="button"
        color="gray"
        variant="ghost"
        size="sm"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme={theme}
        aria-label={label}
        aria-pressed="false"
        class={[
          "px-2!",
          theme == "system" &&
            "[[data-theme-preference=system]_&]:bg-gray-200 [[data-theme-preference=system]_&]:dark:bg-gray-700",
          theme == "light" &&
            "[[data-theme-preference=light]_&]:bg-gray-200 [[data-theme-preference=light]_&]:dark:bg-gray-700",
          theme == "dark" &&
            "[[data-theme-preference=dark]_&]:bg-gray-200 [[data-theme-preference=dark]_&]:dark:bg-gray-700"
        ]}
      >
        <.icon name={icon} class="size-4" />
      </.button>
    </div>
    """
  end
end

defmodule BeamletWeb.CoreComponents do
  @moduledoc """
  Application components and Phoenix generator compatibility built on Petal.

  Petal components are imported by BeamletWeb. These adapters retain Phoenix's
  navigation button, labelled input, and table action-slot APIs.
  """
  use Phoenix.Component
  use Gettext, backend: BeamletWeb.Gettext

  alias PetalComponents.{Alert, Button, Field, Table}
  alias Phoenix.LiveView.JS

  attr :id, :string
  attr :flash, :map, default: %{}
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error]
  attr :rest, :global
  slot :inner_block

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      role="alert"
      class="pointer-events-auto"
      {@rest}
    >
      <Alert.alert
        color={if @kind == :error, do: "danger", else: "info"}
        variant="soft"
        heading={@title}
        with_icon
        close_button_properties={[
          type: "button",
          "aria-label": gettext("close"),
          "phx-click": JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")
        ]}
      >
        {msg}
      </Alert.alert>
    </div>
    """
  end

  @doc "A Petal button accepting Phoenix href/navigate/patch and Petal to/link_type."
  attr :class, :any, default: nil
  attr :variant, :string, default: "soft"
  attr :color, :string, default: "primary"
  attr :size, :string, default: "md"
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :icon, :string, default: nil
  attr :to, :string, default: nil
  attr :link_type, :string, default: "button"
  attr :rest, :global, include: ~w(href navigate patch method download name value type form)
  slot :inner_block, required: true

  def button(assigns) do
    {link_type, to} =
      cond do
        assigns.rest[:navigate] -> {"live_redirect", assigns.rest.navigate}
        assigns.rest[:patch] -> {"live_patch", assigns.rest.patch}
        assigns.rest[:href] -> {"a", assigns.rest.href}
        true -> {assigns.link_type, assigns.to}
      end

    assigns =
      assigns
      |> assign(:link_type, link_type)
      |> assign(:to, to)
      |> assign(:variant, if(assigns.variant == "primary", do: "solid", else: assigns.variant))
      |> assign(:rest, Map.drop(assigns.rest, [:href, :navigate, :patch]))

    ~H"""
    <Button.button
      class={@class}
      variant={@variant}
      color={@color}
      size={@size}
      loading={@loading}
      disabled={@disabled}
      icon={@icon}
      to={@to}
      link_type={@link_type}
      {@rest}
    >
      {render_slot(@inner_block)}
    </Button.button>
    """
  end

  @doc "Phoenix's labelled input API, rendered with Petal Field."
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :checked, :boolean
  attr :prompt, :string, default: nil
  attr :options, :list, default: []
  attr :multiple, :boolean, default: false
  attr :class, :any, default: nil
  attr :error_class, :string, default: nil

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(assigns) do
    assigns =
      assign(
        assigns,
        :petal_assigns,
        assigns
        |> Map.delete(:error_class)
        |> Map.put(:class, [assigns.class, assigns.errors != [] && assigns.error_class])
        |> Map.put(:rows, assigns.rest[:rows] || "4")
        |> Map.put(:required, assigns.rest[:required] || false)
        |> Map.put(:rest, Map.drop(assigns.rest, [:rows, :required]))
      )

    ~H"""
    <Field.field {@petal_assigns} />
    """
  end

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">{render_slot(@inner_block)}</h1>
        <p :if={@subtitle != []} class="text-sm text-gray-600 dark:text-gray-400">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc "Petal table styling with Phoenix stream, row-click, and action-slot support."
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil
  attr :row_click, :any, default: nil
  attr :row_item, :any, default: &Function.identity/1

  slot :col, required: true do
    attr :label, :string
  end

  slot :action

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <Table.table>
      <thead>
        <Table.tr>
          <Table.th :for={col <- @col}>{col[:label]}</Table.th>
          <Table.th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </Table.th>
        </Table.tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <Table.tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <Table.td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </Table.td>
          <Table.td :if={@action != []}>
            <div class="flex items-center justify-end gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </Table.td>
        </Table.tr>
      </tbody>
    </Table.table>
    """
  end

  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="divide-y divide-gray-200 dark:divide-gray-800">
      <div :for={item <- @item} class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
        <dt class="font-medium">{item.title}</dt>
        <dd class="mt-1 text-gray-600 sm:col-span-2 sm:mt-0 dark:text-gray-400">
          {render_slot(item)}
        </dd>
      </div>
    </dl>
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc "Translate validation errors through Beamlet's Gettext backend."
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(BeamletWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(BeamletWeb.Gettext, "errors", msg, opts)
    end
  end

  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end

defmodule Beamlet.Web.Agents do
  @moduledoc "One-attempt creation and input; ambiguous acknowledgements never trigger retries."
  alias Beamlet.{Agent, Node}
  alias Beamlet.Web.{Handles, Presets}

  @type input_result ::
          {:accepted, Agent.turn()}
          | {:rejected, :busy | :invalid_or_oversize_input | :stale_ref | :invalid_command}
          | :input_unknown
  @type creation_result ::
          {:created,
           %{ref: Agent.Ref.t(), navigation: Handles.navigation(), input: input_result()}}
          | {:create_unknown, %{authority: node(), id: binary()}}
          | {:rejected, :invalid_draft}
  @spec discover(term()) :: {:ok, Node.Agents.result()} | {:error, :invalid_query}
  def discover(targets), do: Node.Agents.discover(targets)
  @spec attach(term()) :: Handles.navigation()
  def attach(descriptor), do: Handles.remember(descriptor)

  @spec create(term()) :: creation_result()
  def create(draft) do
    case Presets.resolve(draft) do
      {:ok, resolved} ->
        authority =
          if resolved.authority == :local,
            do: node(),
            else: String.to_existing_atom(resolved.authority)

        id = "web-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

        case Agent.start(authority, Keyword.put(resolved.options, :id, id)) do
          {:ok, ref} ->
            navigation = Handles.remember(%{authority: ref.authority, id: ref.id, pid: ref.pid})
            {:created, %{ref: ref, navigation: navigation, input: input(ref, resolved.task)}}

          _ ->
            {:create_unknown, %{authority: authority, id: id}}
        end

      _ ->
        {:rejected, :invalid_draft}
    end
  end

  @spec input(Agent.Ref.t(), term()) :: input_result()
  def input(ref, text) do
    case Agent.input(ref, text) do
      {:ok, turn} ->
        {:accepted, turn}

      {:error, reason}
      when reason in [:busy, :invalid_or_oversize_input, :stale_ref, :invalid_command] ->
        {:rejected, reason}

      _ ->
        :input_unknown
    end
  end
end

defmodule Beamlet.I18n.Vocabulary do
  @moduledoc """
  Translates the shared status/reason vocabulary for both surfaces.

  Callers pass whatever atom/value they already render; only words declared by
  `Beamlet.I18n.Catalogue` are looked up. Everything else is returned as text
  without translation, so business identifiers, tool names, roles and unknown
  internal reasons keep their existing rendering instead of inventing copy.
  """
  alias Beamlet.I18n
  alias Beamlet.I18n.Catalogue

  @doc """
  Status/state word for an atom or binary, translated when it is shared
  vocabulary.
  """
  @spec status(value) :: value | String.t() when value: var
  def status(value) when is_binary(value), do: word(value, Catalogue.statuses(), :status)
  def status(value) when is_atom(value) and not is_nil(value), do: status(Atom.to_string(value))
  def status(value), do: value

  @doc """
  Error/outcome word for an atom or binary, translated when it is shared
  vocabulary.
  """
  @spec reason(value) :: value | String.t() when value: var
  def reason(value) when is_binary(value), do: word(value, Catalogue.reasons(), :reason)
  def reason(value) when is_atom(value) and not is_nil(value), do: reason(Atom.to_string(value))
  def reason(value), do: value

  @spec word(String.t(), [String.t()], :status | :reason) :: String.t()
  defp word(value, known, :status) do
    if value in known, do: I18n.gettext(value), else: value
  end

  defp word(value, known, :reason) do
    if value in known, do: I18n.dgettext("errors", value), else: value
  end
end

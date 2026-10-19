defmodule Beamlet.I18n.Vocabulary do
  @moduledoc """
  仅翻译 Catalogue 声明的状态与原因。已知 atom 转为文本后查询，未知 atom/binary 保留文本，其他值原样返回；调用方仍须采用安全呈现规则。

  Translates the shared status/reason vocabulary for both surfaces.

  Callers pass whatever atom/value they already render; only words declared by
  `Beamlet.I18n.Catalogue` are looked up. Everything else is returned as text
  without translation, so business identifiers, tool names, roles and unknown
  internal reasons keep their existing rendering instead of inventing copy.
  """
  alias Beamlet.I18n
  alias Beamlet.I18n.Catalogue

  @doc """
  仅翻译声明过的状态词；未知 atom 转为文本，其他非文本值原样返回。

  Status/state word for an atom or binary, translated when it is shared
  vocabulary.
  """
  @spec status(value) :: value | String.t() when value: var
  def status(value) when is_binary(value), do: word(value, Catalogue.statuses(), :status)
  def status(value) when is_atom(value) and not is_nil(value), do: status(Atom.to_string(value))
  def status(value), do: value

  @doc """
  仅翻译声明过的原因；未知 atom 转为文本，其他非文本值原样返回。

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

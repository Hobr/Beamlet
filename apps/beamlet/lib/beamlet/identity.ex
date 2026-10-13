defmodule Beamlet.Identity do
  @moduledoc """
  Submission identity within a trusted authority collection.

  A nil key means a new operation on every successful submission. These strings
  identify facts; they are not credentials. Text is compared without normalization.
  """

  @enforce_keys [:collection, :namespace]
  defstruct [:collection, :namespace, :key]

  @type t :: %__MODULE__{collection: String.t(), namespace: String.t(), key: String.t() | nil}

  @spec new(term(), term(), term()) :: {:ok, t()} | {:error, :invalid_identity}
  def new(collection, namespace, key \\ nil) do
    if valid_text?(collection) and valid_text?(namespace) and (is_nil(key) or valid_text?(key)),
      do: {:ok, %__MODULE__{collection: collection, namespace: namespace, key: key}},
      else: {:error, :invalid_identity}
  end

  @doc "Validates an opaque identity string, limited to 256 UTF-8 bytes."
  @spec valid_text?(term()) :: boolean()
  def valid_text?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)
end

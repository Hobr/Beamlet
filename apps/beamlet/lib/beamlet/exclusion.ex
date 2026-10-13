defmodule Beamlet.Exclusion do
  @moduledoc """
  A resource Adapter's verified exclusion of past AND future execution.

  Construct only after verifying an external protocol's evidence, never by copying
  flags from an untrusted report body. The original authorization and query binding
  identify the excluded attempt. The Domain checks this association; it cannot
  verify the real provider's fencing or receipt guarantee.
  """

  alias Beamlet.{Token, Value}

  @enforce_keys [:authorization, :query_binding, :evidence_ref]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          authorization: Token.t(),
          query_binding: %{String.t() => Value.t()},
          evidence_ref: String.t()
        }
end

defmodule Beamlet.Token do
  @moduledoc """
  A scoped Worker lease identity. Possession alone is not a start authorization.

  Worker restarts must use a new incarnation. Generation is allocated by the
  Authority and never wraps; it does not provide external-resource fencing.
  """

  @enforce_keys [:collection, :intent_id, :execution_id, :worker, :incarnation, :generation]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          collection: String.t(),
          intent_id: String.t(),
          execution_id: String.t(),
          worker: String.t(),
          incarnation: String.t(),
          generation: pos_integer()
        }
end

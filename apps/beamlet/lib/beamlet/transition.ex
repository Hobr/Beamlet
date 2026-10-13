defmodule Beamlet.Transition do
  @moduledoc """
  A proposed snapshot, History delta and command reply.

  Storage must commit the snapshot and events together before acknowledging.
  This is not a durable receipt. A rejected command can carry a lease-expiry
  barrier: its events must be committed rather than discarded with a rollback.
  """

  alias Beamlet.Intent

  @enforce_keys [:intent, :reply]
  defstruct [:intent, :reply, events: []]

  @type event :: %{
          kind: atom(),
          execution_id: String.t() | nil,
          actor: String.t(),
          at: integer(),
          version: pos_integer(),
          details: map()
        }
  @type t :: %__MODULE__{intent: Intent.t(), reply: term(), events: [event()]}
end

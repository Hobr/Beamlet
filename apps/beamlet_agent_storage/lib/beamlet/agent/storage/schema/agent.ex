defmodule Beamlet.Agent.Storage.Schema.Agent do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Agent.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "agents" do
    field(:dispatch_scope_id, :string)
    field(:authority_id, :string)
    field(:alias, :string)
    field(:definition, Beamlet.Agent.Storage.JSON)
    field(:head_checkpoint_id, :string)
    field(:generation, :integer)
    field(:lock_version, :integer)
    field(:history_seq, :integer)
    field(:forked_from_agent_id, :string)
    field(:forked_from_checkpoint_id, :string)
  end

  @typedoc "Agent row including empty construction state; persisted invariants remain enforced at runtime."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          dispatch_scope_id: String.t() | nil,
          authority_id: String.t() | nil,
          alias: String.t() | nil,
          definition: Beamlet.Agent.Storage.Records.value(),
          head_checkpoint_id: String.t() | nil,
          generation: integer() | nil,
          lock_version: integer() | nil,
          history_seq: integer() | nil,
          forked_from_agent_id: String.t() | nil,
          forked_from_checkpoint_id: String.t() | nil
        }
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id authority_id definition generation lock_version history_seq)a
    )
  end
end

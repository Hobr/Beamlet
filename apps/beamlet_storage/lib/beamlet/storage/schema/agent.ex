defmodule Beamlet.Storage.Schema.Agent do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "agents" do
    field :authority_id, :string
    field :alias, :string
    field :definition, Beamlet.Storage.JSON
    field :head_checkpoint_id, :string
    field :generation, :integer
    field :lock_version, :integer
    field :history_seq, :integer
    field :forked_from_agent_id, :string
    field :forked_from_checkpoint_id, :string
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id authority_id definition generation lock_version history_seq)a
    )
  end
end

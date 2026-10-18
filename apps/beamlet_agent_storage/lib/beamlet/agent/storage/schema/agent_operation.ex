defmodule Beamlet.Agent.Storage.Schema.AgentOperation do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Agent.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "agent_operations" do
    field(:owner_agent_id, :string)
    field(:turn_id, :string)
    field(:tool_call_id, :string)
    field(:ordinal, :integer)
    field(:step_id, :string)
    field(:role, :string)
    field(:owner_generation, :integer)
    field(:prepared_seq, :integer)
    field(:sources, Beamlet.Agent.Storage.JSON, kind: :operation)
  end

  def changeset(record, attrs),
    do:
      RecordChangeset.build(
        record,
        attrs,
        ~w(id owner_agent_id turn_id step_id role owner_generation prepared_seq sources)a
      )
end

defmodule Beamlet.Agent.Storage.Schema.Command do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Agent.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "commands" do
    field(:scope_id, :string)
    field(:command_id, :string)
    field(:request_digest, :string)
    field(:response, Beamlet.Agent.Storage.JSON, kind: :command)
    field(:recorded_at, :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    RecordChangeset.build(
      record,
      attrs,
      ~w(id scope_id command_id request_digest response recorded_at)a
    )
  end
end

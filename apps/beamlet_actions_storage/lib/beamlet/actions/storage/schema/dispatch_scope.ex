defmodule Beamlet.Actions.Storage.Schema.DispatchScope do
  @moduledoc false
  use Ecto.Schema
  alias Beamlet.Actions.Storage.RecordChangeset
  @primary_key {:id, :string, autogenerate: false}
  schema "dispatch_scopes" do
    field(:epoch, :integer)
  end

  @type t :: %__MODULE__{id: String.t() | nil, epoch: integer() | nil}
  @spec changeset(t(), term()) :: Ecto.Changeset.t(t())
  def changeset(record, attrs), do: RecordChangeset.build(record, attrs, [:id, :epoch])
end

defmodule Synapse.Schemas.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :type, :string
    field :title, :string
    field :created_by, :string

    has_many :participants, Synapse.Schemas.Participant
    has_many :messages, Synapse.Schemas.Message

    timestamps(type: :utc_datetime)
  end

  @valid_types ~w(dm group)

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:type, :title, :created_by])
    |> validate_required([:type, :created_by])
    |> validate_inclusion(:type, @valid_types)
    |> validate_dm_title()
  end

  defp validate_dm_title(changeset) do
    if get_field(changeset, :type) == "group" do
      validate_required(changeset, [:title])
    else
      changeset
    end
  end
end

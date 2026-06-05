defmodule Synapse.Schemas.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "conversation_participants" do
    belongs_to :conversation, Synapse.Schemas.Conversation, type: :binary_id
    field :user_id, :string
    field :role, :string, default: "member"
    field :unread_count, :integer, default: 0
    field :last_read_at, :utc_datetime
    field :joined_at, :utc_datetime
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:conversation_id, :user_id, :role])
    |> validate_required([:conversation_id, :user_id])
    |> validate_inclusion(:role, ~w(owner member))
    |> unique_constraint([:conversation_id, :user_id])
  end
end

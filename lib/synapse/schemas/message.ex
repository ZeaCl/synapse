defmodule Synapse.Schemas.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    belongs_to :conversation, Synapse.Schemas.Conversation, type: :binary_id
    field :sender_id, :string
    field :content, :string
    field :mentions, {:array, :string}, default: []
    belongs_to :reply_to, Synapse.Schemas.Message, type: :binary_id
    field :type, :string, default: "text"
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @valid_types ~w(text image voice file system)

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:conversation_id, :sender_id, :content, :mentions, :reply_to_id, :type, :metadata])
    |> validate_required([:conversation_id, :sender_id, :content])
    |> validate_inclusion(:type, @valid_types)
  end
end

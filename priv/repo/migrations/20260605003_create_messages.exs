defmodule Synapse.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all), null: false
      add :sender_id, :string, null: false
      add :content, :text, null: false
      add :mentions, {:array, :string}, default: []
      add :reply_to_id, references(:messages, type: :uuid, on_delete: :nilify_all)
      add :type, :string, null: false, default: "text"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:messages, [:conversation_id, :inserted_at])
    create index(:messages, [:sender_id])
  end
end

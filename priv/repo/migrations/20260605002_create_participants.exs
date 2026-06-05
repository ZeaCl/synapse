defmodule Synapse.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    create table(:conversation_participants, primary_key: false) do
      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, :string, null: false
      add :role, :string, null: false, default: "member"
      add :unread_count, :integer, null: false, default: 0
      add :last_read_at, :utc_datetime
      add :joined_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:conversation_participants, [:conversation_id, :user_id])
    create index(:conversation_participants, [:user_id])
  end
end

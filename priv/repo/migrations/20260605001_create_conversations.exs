defmodule Synapse.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :type, :string, null: false
      add :title, :string
      add :created_by, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:created_by])
  end
end

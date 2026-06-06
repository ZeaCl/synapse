defmodule Synapse.Schemas.ParticipantTest do
  use Synapse.DataCase, async: true

  alias Synapse.Schemas.Participant

  describe "changeset/2" do
    test "valid participant" do
      changeset = Participant.changeset(%Participant{}, %{
        conversation_id: Ecto.UUID.generate(),
        user_id: "user_a"
      })
      assert changeset.valid?
    end

    test "default role is member" do
      changeset = Participant.changeset(%Participant{}, %{
        conversation_id: Ecto.UUID.generate(),
        user_id: "user_a"
      })
      assert Ecto.Changeset.get_field(changeset, :role) == "member"
    end

    test "valid owner role" do
      changeset = Participant.changeset(%Participant{}, %{
        conversation_id: Ecto.UUID.generate(),
        user_id: "user_a",
        role: "owner"
      })
      assert changeset.valid?
    end

    test "requires conversation_id" do
      changeset = Participant.changeset(%Participant{}, %{user_id: "user_a"})
      refute changeset.valid?
    end

    test "requires user_id" do
      changeset = Participant.changeset(%Participant{}, %{
        conversation_id: Ecto.UUID.generate()
      })
      refute changeset.valid?
    end

    test "invalid role" do
      changeset = Participant.changeset(%Participant{}, %{
        conversation_id: Ecto.UUID.generate(),
        user_id: "user_a",
        role: "admin"
      })
      refute changeset.valid?
    end
  end
end

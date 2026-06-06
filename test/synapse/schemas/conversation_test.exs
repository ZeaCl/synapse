defmodule Synapse.Schemas.ConversationTest do
  use Synapse.DataCase, async: true

  alias Synapse.Schemas.Conversation

  describe "changeset/2" do
    test "valid dm conversation" do
      changeset = Conversation.changeset(%Conversation{}, %{
        type: "dm",
        created_by: "user_a"
      })
      assert changeset.valid?
    end

    test "valid group conversation requires title" do
      changeset = Conversation.changeset(%Conversation{}, %{
        type: "group",
        created_by: "user_a"
      })
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
    end

    test "valid group with title" do
      changeset = Conversation.changeset(%Conversation{}, %{
        type: "group",
        title: "My Team",
        created_by: "user_a"
      })
      assert changeset.valid?
    end

    test "invalid type" do
      changeset = Conversation.changeset(%Conversation{}, %{
        type: "invalid",
        created_by: "user_a"
      })
      refute changeset.valid?
    end

    test "requires created_by" do
      changeset = Conversation.changeset(%Conversation{}, %{type: "dm"})
      refute changeset.valid?
    end
  end
end

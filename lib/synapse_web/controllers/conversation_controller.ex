defmodule SynapseWeb.ConversationController do
  use SynapseWeb, :controller

  alias Synapse.Repo
  alias Synapse.Schemas.{Conversation, Participant}
  import Ecto.Query

  @doc """
  GET /conversations
  Lists all conversations for the authenticated user.
  """
  def index(conn, _params) do
    user_id = conn.assigns.user_id

    conversations =
      from(c in Conversation,
        join: p in Participant, on: p.conversation_id == c.id,
        where: p.user_id == ^user_id,
        order_by: [desc: c.updated_at],
        preload: [:participants]
      )
      |> Repo.all()

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(conversations, &serialize/1)})
  end

  @doc """
  GET /conversations/:id
  """
  def show(conn, %{"id" => id}) do
    user_id = conn.assigns.user_id

    conversation =
      from(c in Conversation,
        where: c.id == ^id,
        preload: [:participants]
      )
      |> Repo.one()

    if conversation do
      if participant?(id, user_id) do
        conn |> put_status(:ok) |> json(%{data: serialize(conversation)})
      else
        conn |> put_status(403) |> json(%{error: "not_participant"})
      end
    else
      conn |> put_status(404) |> json(%{error: "not_found"})
    end
  end

  @doc """
  POST /conversations
  Creates a new DM or group conversation.
  """
  def create(conn, params) do
    user_id = conn.assigns.user_id
    type = params["type"] || "dm"
    participant_ids = params["participant_ids"] || []

    # For DM: check if conversation already exists between these two users
    result =
      if type == "dm" and length(participant_ids) == 1 do
        existing = find_existing_dm(user_id, List.first(participant_ids))
        if existing, do: {:ok, existing}, else: do_create(type, params["title"], user_id, participant_ids)
      else
        do_create(type, params["title"], user_id, participant_ids)
      end

    case result do
      {:ok, conversation} ->
        conn
        |> put_status(:created)
        |> json(%{data: serialize(conversation)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", details: changeset.errors})
    end
  end


  # ── Private ──

  defp do_create(type, title, creator_id, participant_ids) do
    Repo.transaction(fn ->
      {:ok, conv} =
        %Conversation{}
        |> Conversation.changeset(%{type: type, title: title, created_by: creator_id})
        |> Repo.insert()

      # Add creator as owner
      %Participant{}
      |> Participant.changeset(%{conversation_id: conv.id, user_id: creator_id, role: "owner"})
      |> Repo.insert!()

      # Add other participants
      user_ids = if is_list(participant_ids), do: participant_ids, else: []
      Enum.each(user_ids, fn pid ->
        %Participant{}
        |> Participant.changeset(%{conversation_id: conv.id, user_id: pid, role: "member"})
        |> Repo.insert!(on_conflict: :nothing)
      end)

      Repo.preload(conv, [:participants])
    end)
  end

  defp find_existing_dm(user1, user2) do
    # Find conversations where both users are participants
    sub =
      from p in Participant,
        group_by: p.conversation_id,
        having: fragment("array_agg(?) @> ?", p.user_id, ^[user1, user2]),
        select: %{conversation_id: p.conversation_id}

    from(c in Conversation,
      join: s in subquery(sub), on: c.id == s.conversation_id,
      where: c.type == "dm",
      preload: [:participants]
    )
    |> Repo.one()
  end

  defp participant?(conv_id, user_id) do
    Repo.exists?(from p in Participant, where: p.conversation_id == ^conv_id and p.user_id == ^user_id)
  end

  defp serialize(conv) do
    %{
      id: conv.id,
      type: conv.type,
      title: conv.title,
      created_by: conv.created_by,
      participants: Enum.map(conv.participants || [], fn p ->
        %{user_id: p.user_id, role: p.role}
      end),
      last_message: last_message(conv),
      inserted_at: conv.inserted_at,
      updated_at: conv.updated_at
    }
  end

  defp last_message(_conv) do
    # Last message is fetched separately for index performance
    nil
  end
end

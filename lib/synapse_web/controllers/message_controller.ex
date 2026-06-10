defmodule SynapseWeb.MessageController do
  use SynapseWeb, :controller

  alias Synapse.Repo
  alias Synapse.Schemas.Message
  import Ecto.Query

  @doc """
  GET /conversations/:conversation_id/messages?before=ISO8601&limit=50

  Returns paginated messages with cursor-based pagination.
  """
  def index(conn, %{"conversation_id" => conv_id} = params) do
    user_id = conn.assigns.user_id

    unless participant?(conv_id, user_id) do
      conn |> put_status(403) |> json(%{error: "not_participant"})
    else
      limit = String.to_integer(params["limit"] || "50")
      before = params["before"]

      query =
        from(m in Message,
          where: m.conversation_id == ^conv_id,
          order_by: [desc: :inserted_at],
          limit: ^(limit + 1)
        )

      query = if before do
        {:ok, dt, _} = DateTime.from_iso8601(before)
        from m in query, where: m.inserted_at < ^dt
      else
        query
      end

      messages = Repo.all(query)
      has_more = length(messages) > limit
      messages = if has_more, do: Enum.take(messages, limit), else: messages

      next_cursor =
        case List.last(messages) do
          nil -> nil
          msg -> DateTime.to_iso8601(msg.inserted_at)
        end

      conn
      |> put_status(:ok)
      |> json(%{
        data: Enum.map(messages, &serialize/1),
        cursor: %{next: next_cursor, has_more: has_more}
      })
    end
  end

  @doc """
  POST /conversations/:conversation_id/messages

  Creates a message and broadcasts it via the Conversation GenServer.

  Optional `sender_id` in body allows trusted callers (e.g., Platform)
  to post messages on behalf of another participant (e.g., agent responses).
  """
  def create(conn, %{"conversation_id" => conv_id} = params) do
    auth_user_id = conn.assigns.user_id
    content = params["content"]
    sender_id = params["sender_id"] || auth_user_id

    # Guard: both auth user and sender must be participants
    unless participant?(conv_id, auth_user_id) and participant?(conv_id, sender_id) do
      conn |> put_status(403) |> json(%{error: "not_participant"})
    else
      # Route through GenServer (handles mentions, Glia forwarding, PubSub)
      Synapse.Conversation.send_message(conv_id, sender_id, content)

      conn
      |> put_status(:created)
      |> json(%{status: "sent", conversation_id: conv_id, sender_id: sender_id})
    end
  end

  # ── Private ──

  defp participant?(conv_id, user_id) do
    Repo.exists?(
      from p in Synapse.Schemas.Participant,
        where: p.conversation_id == ^conv_id and p.user_id == ^user_id
    )
  end

  defp serialize(msg) do
    %{
      id: msg.id,
      conversation_id: msg.conversation_id,
      sender_id: msg.sender_id,
      content: msg.content,
      mentions: msg.mentions,
      type: msg.type,
      metadata: msg.metadata,
      inserted_at: msg.inserted_at
    }
  end
end

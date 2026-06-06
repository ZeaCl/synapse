defmodule Synapse.Conversation do
  @moduledoc """
  Manages an active conversation as a GenServer.

  One process per active conversation (someone has the WebSocket open).
  Handles message delivery, @mention resolution, and typing tracking.
  Auto-shuts down after 30 minutes of inactivity.
  """

  use GenServer
  require Logger

  alias Synapse.Repo
  alias Synapse.Schemas.{Message, Participant}
  import Ecto.Query

  @idle_timeout :timer.minutes(30)

  # ── Client API ──

  def start_link({conv_id, _opts}) do
    GenServer.start_link(__MODULE__, conv_id, name: via_tuple(conv_id))
  end

  def send_message(conv_id, sender_id, content) do
    case Registry.lookup(Synapse.ConversationRegistry, conv_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:send_message, sender_id, content})

      [] ->
        # GenServer not running — start it, then persist and broadcast
        DynamicSupervisor.start_child(Synapse.ConversationSupervisor, {__MODULE__, {conv_id, %{}}})
        Process.sleep(50)
        GenServer.cast(via_tuple(conv_id), {:send_message, sender_id, content})
    end
  end

  def typing(conv_id, user_id) do
    case Registry.lookup(Synapse.ConversationRegistry, conv_id) do
      [{pid, _}] -> GenServer.cast(pid, {:typing, user_id})
      [] -> :ok
    end
  end

  def participant?(conv_id, user_id) do
    Repo.exists?(
      from p in Participant,
        where: p.conversation_id == ^conv_id and p.user_id == ^user_id
    )
  end

  # ── GenServer Callbacks ──

  @impl true
  def init(conv_id) do
    schedule_idle_check()
    {:ok, %{conv_id: conv_id, typing_users: MapSet.new(), last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:send_message, sender_id, content}, state) do
    # 1. Parse @mentions
    mentions = Synapse.MessageParser.extract_mentions(content)
    resolved = resolve_mentions(mentions)

    # 2. Persist message
    {:ok, msg} =
      %Message{}
      |> Message.changeset(%{
        conversation_id: state.conv_id,
        sender_id: sender_id,
        content: content,
        mentions: Enum.map(resolved, & &1.id),
        type: "text"
      })
      |> Repo.insert()

    saved = Repo.preload(msg, :conversation)

    # 3. Side effects (async, non-blocking)
    Task.start(fn ->
      # Add mentioned users as participants
      Enum.each(resolved, fn user ->
        add_participant(state.conv_id, user.id)

        # Forward to Glia if agent
        if user.is_agent do
          Synapse.GliaClient.push_message(user.id, state.conv_id, saved)
        end
      end)
    end)

    # 4. Broadcast via PubSub
    Phoenix.PubSub.broadcast(Synapse.PubSub, topic(state.conv_id), {:new_message, saved})

    {:noreply, %{state | last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast({:typing, user_id}, state) do
    typing = MapSet.put(state.typing_users, user_id)

    Phoenix.PubSub.broadcast(Synapse.PubSub, topic(state.conv_id), {:typing_start, user_id})

    # Auto-clear typing after 3 seconds
    Process.send_after(self(), {:clear_typing, user_id}, 3000)

    {:noreply, %{state | typing_users: typing, last_activity: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:clear_typing, user_id}, state) do
    typing = MapSet.delete(state.typing_users, user_id)
    Phoenix.PubSub.broadcast(Synapse.PubSub, topic(state.conv_id), {:typing_stop, user_id})
    {:noreply, %{state | typing_users: typing}}
  end

  @impl true
  def handle_info(:idle_check, state) do
    # Auto-shutdown after idle timeout regardless of connections
    # (Tracker-based presence check requires phoenix_presence dep)
    Logger.info("[Conversation] #{state.conv_id} — idle shutdown")
    {:stop, :normal, state}
  end

  # ── Private Helpers ──

  defp topic(conv_id), do: "conversation:#{conv_id}"

  defp via_tuple(conv_id), do: {:via, Registry, {Synapse.ConversationRegistry, conv_id}}

  defp schedule_idle_check do
    Process.send_after(self(), :idle_check, @idle_timeout)
  end

  defp resolve_mentions(usernames) do
    # Skip Thalamus resolution when auth bypass is enabled
    if Application.get_env(:synapse, :auth_test_bypass, false) do
      Enum.map(usernames, fn name ->
        %{id: name, name: name, is_agent: false}
      end)
    else
      Synapse.ThalamusClient.resolve_users(usernames)
    end
  end

  defp add_participant(conv_id, user_id) do
    already = Repo.exists?(
      from p in Participant,
        where: p.conversation_id == ^conv_id and p.user_id == ^user_id
    )

    unless already do
      %Participant{}
      |> Participant.changeset(%{conversation_id: conv_id, user_id: user_id, role: "member"})
      |> Repo.insert(on_conflict: :nothing)
    end
  end
end

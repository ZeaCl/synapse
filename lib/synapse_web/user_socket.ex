defmodule SynapseWeb.UserSocket do
  use Phoenix.Socket

  channel "conversation:*", SynapseWeb.ConversationChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Synapse.ThalamusClient.verify_jwt(token) do
      {:ok, claims} ->
        socket =
          socket
          |> assign(:user_id, claims["sub"] || claims["user_id"])
          |> assign(:name, claims["name"])
          |> assign(:is_agent, claims["is_agent"] || false)

        {:ok, socket}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end

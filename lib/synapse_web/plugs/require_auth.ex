defmodule SynapseWeb.Plugs.RequireAuth do
  @moduledoc """
  Validates JWT Bearer token from Authorization header.

  Assigns :user_id, :name, :is_agent to the connection on success.
  Returns 401 on failure.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Synapse.ThalamusClient.verify_jwt(token) do
      conn
      |> assign(:user_id, claims["sub"] || claims["user_id"])
      |> assign(:name, claims["name"])
      |> assign(:is_agent, claims["is_agent"] || false)
    else
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized", reason: reason}))
        |> halt()

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end

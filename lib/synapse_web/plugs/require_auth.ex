defmodule SynapseWeb.Plugs.RequireAuth do
  @moduledoc """
  Validates JWT Bearer token from Authorization header.

  In dev/test mode, allows bypassing via x-test-user-id header.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if test_bypass_enabled?() do
      case get_req_header(conn, "x-test-user-id") do
        [user_id | _] ->
          conn
          |> assign(:user_id, user_id)
          |> assign(:name, test_header(conn, "x-test-name") || user_id)
          |> assign(:is_agent, test_header(conn, "x-test-is-agent") == "true")

        _ ->
          verify_jwt(conn)
      end
    else
      verify_jwt(conn)
    end
  end

  defp verify_jwt(conn) do
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

  defp test_header(conn, key) do
    case get_req_header(conn, key) do
      [val | _] -> val
      _ -> nil
    end
  end

  defp test_bypass_enabled? do
    Application.get_env(:synapse, :auth_test_bypass, false)
  end
end

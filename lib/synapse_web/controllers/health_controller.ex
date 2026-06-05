defmodule SynapseWeb.HealthController do
  use SynapseWeb, :controller

  def index(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok", service: "synapse", timestamp: DateTime.utc_now()})
  end
end

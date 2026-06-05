defmodule SynapseWeb.Router do
  use SynapseWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug SynapseWeb.Plugs.RequireAuth
  end

  scope "/", SynapseWeb do
    pipe_through :api

    resources "/conversations", ConversationController, only: [:index, :show, :create] do
      resources "/messages", MessageController, only: [:index, :create]
    end
  end

  pipeline :public do
    plug :accepts, ["json"]
  end

  # Health check (no auth)
  scope "/", SynapseWeb do
    pipe_through :public

    get "/health", HealthController, :index
  end

  if Application.compile_env(:synapse, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: SynapseWeb.Telemetry
    end
  end
end

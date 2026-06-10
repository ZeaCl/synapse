defmodule Synapse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: Synapse.Finch},
      SynapseWeb.Telemetry,
      Synapse.Repo,
      {DNSCluster, query: Application.get_env(:synapse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Synapse.PubSub},
      {Registry, keys: :unique, name: Synapse.ConversationRegistry},
      {DynamicSupervisor, name: Synapse.ConversationSupervisor, strategy: :one_for_one},
      SynapseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Synapse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SynapseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp tracker_child do
    if Application.get_env(:synapse, :tracker_enabled, true) do
      {Phoenix.Tracker, name: Synapse.Tracker, pubsub_server: Synapse.PubSub}
    else
      # Return a no-op worker for test mode
      {Task.Supervisor, name: Synapse.TrackerPlaceholder}
    end
  end
end

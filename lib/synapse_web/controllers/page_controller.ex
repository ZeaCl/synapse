defmodule SynapseWeb.PageController do
  use SynapseWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

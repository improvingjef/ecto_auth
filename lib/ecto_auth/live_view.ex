defmodule EctoAuth.LiveView do
  @moduledoc """
  LiveView `on_mount` hook that sets the `EctoAuth.Context`.

  ## Usage

      # In your router.ex:
      live_session :authenticated,
        on_mount: [{EctoAuth.LiveView, :default}] do
        live "/organizations", OrganizationLive.Index
      end

  The hook reads the user from `socket.assigns` (set during the initial
  HTTP request by your authentication plug). For reconnects, it falls
  back to loading the user from the session via a configurable function.

  ## Configuration

  Configure the session loader in your application config:

      config :ecto_auth,
        load_user_from_session: &MyApp.Accounts.get_user_from_session/1

  """

  @doc """
  `on_mount` callback for LiveView.

  Accepts `:default` as the argument.
  """
  def on_mount(:default, _params, session, socket) do
    user = socket.assigns[:current_user] || load_user_from_session(session)

    if user do
      EctoAuth.Context.put_context(%{user: user})
    end

    {:cont, socket}
  end

  defp load_user_from_session(session) do
    case Application.get_env(:ecto_auth, :load_user_from_session) do
      fun when is_function(fun, 1) -> fun.(session)
      _ -> nil
    end
  end
end

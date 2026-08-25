defmodule EctoAuth.Plug do
  @moduledoc """
  Plug that sets the `EctoAuth.Context` from `conn.assigns` for HTTP requests.

  ## Usage

      # In your router.ex:
      pipeline :browser do
        # ... other plugs that authenticate and set conn.assigns.current_user
        plug EctoAuth.Plug
      end

  ## Options

    * `:user_assign` - the key in `conn.assigns` that holds the current user.
      Defaults to `:current_user`.

    * `:context_fn` - an optional function that receives the user and returns
      the full context map. Defaults to `fn user -> %{user: user} end`.

  """

  @doc "Initializes the plug options."
  def init(opts), do: opts

  @doc "Sets the auth context from conn.assigns."
  def call(conn, opts) do
    user_key = Keyword.get(opts, :user_assign, :current_user)
    user = conn.assigns[user_key]

    if user do
      context_fn = Keyword.get(opts, :context_fn, &%{user: &1})
      EctoAuth.Context.put_context(context_fn.(user))
    end

    conn
  end
end

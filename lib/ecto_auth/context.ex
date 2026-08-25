defmodule EctoAuth.Context do
  @moduledoc """
  Process-dict based auth context management.

  Stores the current authorization context (typically `%{user: current_user}`)
  in the process dictionary, following the same pattern as `Ecto.Repo`'s
  dynamic repo.

  The context is a map with any keys needed by your auth scopes.

  ## Usage

      EctoAuth.Context.put_context(%{user: current_user})
      EctoAuth.Context.get_context()
      #=> %{user: current_user}

  ## Process propagation

      Task.async(EctoAuth.Context.propagate(fn ->
        Repo.all(Organization) # still scoped to original user
      end))

  """

  @key :ecto_auth_context

  @doc """
  Stores the auth context in the process dictionary.
  """
  @spec put_context(map()) :: map() | nil
  def put_context(ctx) when is_map(ctx), do: Process.put(@key, ctx)

  @doc """
  Retrieves the auth context from the process dictionary.
  Returns `nil` if no context has been set.
  """
  @spec get_context() :: map() | nil
  def get_context, do: Process.get(@key)

  @doc """
  Resolves the auth context from opts (`:auth_context` key) or falls back
  to the process dictionary.
  """
  @spec resolve_context(keyword()) :: map() | nil
  def resolve_context(opts) do
    Keyword.get(opts, :auth_context, get_context())
  end

  @doc """
  Wraps a function to propagate the current context across process boundaries.

  Useful for `Task.async`, `GenServer` spawning, etc.

  ## Example

      Task.async(EctoAuth.Context.propagate(fn ->
        Repo.all(Organization)
      end))

  """
  @spec propagate(fun()) :: fun()
  def propagate(fun) when is_function(fun, 0) do
    ctx = get_context()

    fn ->
      if ctx, do: put_context(ctx)
      fun.()
    end
  end

  @doc """
  Temporarily switches to a different context for the duration of the function call.

  Restores the previous context (or removes it) after the function returns.

  ## Example

      EctoAuth.Context.with_context(%{user: admin}, fn ->
        Repo.all(Organization) # scoped as admin
      end)

  """
  @spec with_context(map(), fun()) :: any()
  def with_context(ctx, fun) when is_map(ctx) and is_function(fun, 0) do
    old = get_context()
    put_context(ctx)

    try do
      fun.()
    after
      if old, do: put_context(old), else: Process.delete(@key)
    end
  end
end

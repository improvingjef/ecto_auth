defmodule EctoAuth.Schema do
  @moduledoc """
  DSL for declaring authorization scopes on Ecto schemas.

  Provides `auth_scope/2` and `auth_changeset_scope/2` macros that define
  how queries and changesets should be scoped for authorization.

  ## Two ways to define a query scope

  ### 1. Function — full control

      auth_scope :member, fn query, context ->
        from o in query,
          join: m in MyApp.Member, on: m.organization_id == o.id,
          where: m.user_id == ^context.user.id
      end

  ### 2. Path — auto-generates joins from association chain

      auth_scope :buyer_access, user.buyer.sites

  The first segment (`user`) is the context key. The rest are associations
  walked at runtime to build JOINs and a WHERE clause.
  """

  defmacro __using__(_opts) do
    quote do
      import EctoAuth.Schema, only: [auth_scope: 2, auth_changeset_scope: 2]
      import EctoAuth.Associations.HasOneOfMany, only: [has_one_of_many: 2, has_one_of_many: 3]
      Module.register_attribute(__MODULE__, :ecto_auth_scopes, accumulate: true)
      Module.register_attribute(__MODULE__, :ecto_auth_changeset_scopes, accumulate: true)
      @before_compile EctoAuth.Schema
    end
  end

  @doc """
  Defines a query scope for authorization.

  ## With a function

      auth_scope :member, fn query, context ->
        from o in query,
          join: m in assoc(o, :members),
          where: m.user_id == ^context.user.id
      end

  ## With dot notation

      auth_scope :buyer_access, user.buyer.sites

  The first segment is the context key, the rest are associations.
  At runtime, the association chain is walked to build JOINs and WHERE.
  """
  defmacro auth_scope(name, opts_or_fun)

  defmacro auth_scope(name, {{:., _, _}, _, _} = dot_expr) do
    # Dot notation: user.buyer.sites
    steps = unwrap_dot_path(dot_expr)

    quote do
      Module.put_attribute(__MODULE__, :ecto_auth_scopes,
        {unquote(name), {:path, unquote(steps)}})
    end
  end

  defmacro auth_scope(name, fun) do
    # fn form — raw function
    escaped_fun = Macro.escape(fun)

    quote do
      Module.put_attribute(__MODULE__, :ecto_auth_scopes,
        {unquote(name), {:fun, unquote(escaped_fun)}})
    end
  end

  @doc false
  # Recursively unwraps user.buyer.sites AST into [:user, :buyer, :sites]
  def unwrap_dot_path({{:., _, [receiver, name]}, _, []}) when is_atom(name) do
    unwrap_dot_path(receiver) ++ [name]
  end

  def unwrap_dot_path({name, _, _}) when is_atom(name) do
    [name]
  end

  @doc """
  Defines a changeset scope for authorization.

  The function receives the changeset and the auth context map,
  and must return a (possibly modified) changeset.

  ## Example

      auth_changeset_scope :member, fn changeset, context ->
        if authorized?(changeset.data, context) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :base, "unauthorized")
        end
      end

  """
  defmacro auth_changeset_scope(name, fun) do
    escaped_fun = Macro.escape(fun)

    quote do
      Module.put_attribute(
        __MODULE__,
        :ecto_auth_changeset_scopes,
        {unquote(name), unquote(escaped_fun)}
      )
    end
  end

  defmacro __before_compile__(env) do
    auth_scopes = Module.get_attribute(env.module, :ecto_auth_scopes) |> Enum.reverse()

    auth_changeset_scopes =
      Module.get_attribute(env.module, :ecto_auth_changeset_scopes) |> Enum.reverse()

    scope_names = Enum.map(auth_scopes, &elem(&1, 0))
    changeset_scope_names = Enum.map(auth_changeset_scopes, &elem(&1, 0))

    scope_clauses =
      for {name, spec} <- auth_scopes do
        case spec do
          {:path, steps} ->
            quote do
              def __auth_scope__(unquote(name), query, context) do
                EctoAuth.Path.apply_path(query, unquote(steps), context)
              end
            end

          {:fun, fun_ast} ->
            quote do
              def __auth_scope__(unquote(name), query, context) do
                unquote(fun_ast).(query, context)
              end
            end
        end
      end

    changeset_scope_clauses =
      for {name, fun_ast} <- auth_changeset_scopes do
        quote do
          def __auth_changeset_scope__(unquote(name), changeset, context) do
            unquote(fun_ast).(changeset, context)
          end
        end
      end

    quote do
      def __auth__(:scopes), do: unquote(scope_names)
      def __auth__(:changeset_scopes), do: unquote(changeset_scope_names)

      unquote_splicing(scope_clauses)
      unquote_splicing(changeset_scope_clauses)
    end
  end
end

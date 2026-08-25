defmodule EctoAuth.Policy do
  @moduledoc """
  Central policy module for defining authorization scopes externally.

  Use this when you want all auth rules in one auditable place rather than
  scattered across schemas.

  ## Usage

      defmodule MyApp.AuthPolicy do
        use EctoAuth.Policy

        scope Organization, :member, [:user, :person, :members, :organization]
        scope Project,      :team,   [:user, :person, :team_members, :project]
      end

  Then configure your app:

      config :ecto_auth, policy: MyApp.AuthPolicy

  Or pass it explicitly when wiring your Repo:

      def prepare_query(op, query, opts) do
        EctoAuth.Repo.prepare_query(op, query, opts, policy: MyApp.AuthPolicy)
      end

  ## Priority

  When both a schema and a policy define scopes for the same schema,
  the schema's scope takes precedence (it's closer to the data).
  The policy acts as a fallback.
  """

  defmacro __using__(_opts) do
    quote do
      import EctoAuth.Policy, only: [scope: 3]
      Module.register_attribute(__MODULE__, :ecto_auth_policy_scopes, accumulate: true)
      @before_compile EctoAuth.Policy
    end
  end

  @doc """
  Defines an authorization scope for a schema.

      scope Organization, :member, [:user, :person, :members, :organization]

  """
  defmacro scope(schema, name, steps) when is_list(steps) do
    quote do
      Module.put_attribute(__MODULE__, :ecto_auth_policy_scopes, {
        unquote(schema),
        unquote(name),
        unquote(steps)
      })
    end
  end

  defmacro __before_compile__(env) do
    scopes = Module.get_attribute(env.module, :ecto_auth_policy_scopes) |> Enum.reverse()

    # Group by schema
    by_schema =
      Enum.group_by(scopes, &elem(&1, 0), fn {_schema, name, steps} -> {name, steps} end)

    quote do
      @doc "Returns the list of schemas with policy scopes."
      def __schemas__, do: unquote(Map.keys(by_schema))

      @doc "Returns scope names for a schema."
      def __scopes__(schema)

      unquote_splicing(
        for {schema, name_steps} <- by_schema do
          names = Enum.map(name_steps, &elem(&1, 0))

          quote do
            def __scopes__(unquote(schema)), do: unquote(names)
          end
        end
      )

      def __scopes__(_), do: []

      @doc "Applies a named scope to a query."
      def __apply_scope__(schema, name, query, context)

      unquote_splicing(
        for {schema, name_steps} <- by_schema, {name, steps} <- name_steps do
          quote do
            def __apply_scope__(unquote(schema), unquote(name), query, context) do
              EctoAuth.Path.apply_path(query, unquote(steps), context)
            end
          end
        end
      )

      def __apply_scope__(_, _, query, _), do: query
    end
  end
end

defmodule EctoAuth.Repo do
  @moduledoc """
  Query and changeset interception for authorization.

  Scopes are applied to the FROM source and — by default — to every join
  whose source schema has auth scopes. This prevents accidental auth bypass
  through joins.

  ## Usage

      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
        use EctoAuth.Repo

        def prepare_query(op, query, opts) do
          EctoAuth.Repo.prepare_query(op, query, opts)
        end

        def prepare_changeset(op, cs, opts) do
          EctoAuth.Repo.prepare_changeset(op, cs, opts)
        end
      end

  `prepare_query/3` is a stock `Ecto.Repo` callback and needs no help.
  `prepare_changeset/3` is not: stock Ecto has no write-side twin of
  `prepare_query/3`, so `use EctoAuth.Repo` overrides the six
  changeset-taking write functions (`insert/2`, `update/2`, `delete/2` and
  their bang variants) to run `prepare_changeset/3` before calling through
  to Ecto's own implementation. See "The write hook" in
  `documentation/design/ecto-fork.html` for the full rationale and the
  transparency table against the fork's version of this hook.

  ## Recursive join scoping

  Given:

      from o in Organization,
        join: p in Project, on: p.organization_id == o.id

  If both Organization and Project have auth scopes, both are applied.
  Project's join is wrapped in a scoped subquery so the ON clause still works.

  Disable with `scope_joins: false`:

      Repo.all(query, scope_joins: false)

  ## Bypass

      Repo.all(Organization, skip_auth: true)

  """

  @write_functions [insert: :insert, update: :update, delete: :delete,
                     insert!: :insert, update!: :update, delete!: :delete]

  @doc """
  Gives a repo the write-side hook stock Ecto doesn't have.

  Stock `Ecto.Repo` already calls `prepare_query/3` on every read; there is
  no equivalent callback invoked before `insert/2`, `update/2`, `delete/2`
  or their bang variants, and — unlike `prepare_query/3` and
  `prepare_changeset/3` — Ecto does not mark those six as `defoverridable`,
  so `use EctoAuth.Repo` does that itself via `Module.make_overridable/2`
  before redefining them. Each override normalizes the argument to a
  changeset, runs `prepare_changeset/3`, and calls through to Ecto's own
  implementation with the result. A default
  `prepare_changeset/3` that returns `{changeset, opts}` unchanged is
  injected and is itself `defoverridable`, so a repo can define its own
  (typically delegating to `EctoAuth.Repo.prepare_changeset/3`) the same way
  it defines `prepare_query/3`.

  Because nested association writes (`has_many`, `has_one`, `belongs_to`,
  `many_to_many`) dispatch back through the owning repo module's own
  `insert`/`update`/`delete`, they run through this same override — the
  hook is not limited to the top-level call. `insert_all/3`,
  `update_all/3` and `delete_all/2` take no changeset and are untouched;
  guard them with `prepare_query/3` as today.
  """
  defmacro __using__(_opts) do
    write_overrides =
      for {fun, op} <- @write_functions do
        quote do
          # Arity 2 only: `use Ecto.Repo` already defines an arity-1 clause
          # (from its own `opts \\ []` default) that calls straight through
          # to arity 2 — since that call resolves to whatever arity-2
          # definition is in effect when the module finishes compiling, it
          # reaches this override without our needing (or being able, since
          # it's not overridable) to redefine it.
          def unquote(fun)(struct_or_changeset, opts) do
            changeset =
              struct_or_changeset
              |> Ecto.Changeset.change()
              |> Map.put(:repo, __MODULE__)

            {changeset, opts} = prepare_changeset(unquote(op), changeset, opts)
            super(changeset, opts)
          end

          defoverridable [{unquote(fun), 2}]
        end
      end

    write_arities = for {fun, _op} <- @write_functions, do: {fun, 2}

    quote do
      @doc false
      def prepare_changeset(_op, changeset, opts), do: {changeset, opts}
      defoverridable prepare_changeset: 3

      # `use Ecto.Repo`, expanded above this `use EctoAuth.Repo`, defines
      # insert/2, update/2, delete/2 and their bang variants directly —
      # unlike prepare_query/3 and prepare_changeset/3, Ecto does not mark
      # them `defoverridable`. Do it ourselves so `super/2` below reaches
      # Ecto's own implementation.
      Module.make_overridable(__MODULE__, unquote(write_arities))

      unquote(write_overrides)
    end
  end

  @doc """
  Applies authorization scopes to queries.

  Scopes the FROM source, then walks joins and scopes any that reference
  schemas with auth scopes (wrapping them in subqueries).

  ## Options

    * `:skip_auth` — bypass authorization entirely
    * `:auth_scope` — select a specific named scope for the FROM source
    * `:auth_context` — override the process-dict context
    * `:scope_joins` — set to `false` to skip recursive join scoping (default: `true`)
    * `:policy` — policy module to use as fallback (repo_opts)
  """
  @spec prepare_query(atom(), Ecto.Query.t(), keyword(), keyword()) ::
          {Ecto.Query.t(), keyword()}
  def prepare_query(_operation, query, opts, repo_opts \\ []) do
    if opts[:skip_auth] do
      {query, opts}
    else
      context = EctoAuth.Context.resolve_context(opts)

      if is_nil(context) do
        {query, opts}
      else
        policy = Keyword.get(repo_opts, :policy) || Application.get_env(:ecto_auth, :policy)

        query = scope_from(query, opts, context, policy)
        query = if Keyword.get(opts, :scope_joins, true),
                  do: scope_joins(query, context, policy),
                  else: query

        {query, opts}
      end
    end
  end

  @doc """
  Applies authorization scopes to changesets.

  Pass `skip_auth: true` in opts to bypass authorization.
  Pass `auth_scope: :scope_name` to select a specific scope.
  """
  @spec prepare_changeset(atom(), Ecto.Changeset.t(), keyword()) ::
          {Ecto.Changeset.t(), keyword()}
  def prepare_changeset(_operation, changeset, opts) do
    if opts[:skip_auth] do
      {changeset, opts}
    else
      apply_changeset_scope(changeset, opts)
    end
  end

  # --- FROM scoping ---

  defp scope_from(query, opts, context, policy) do
    schema = get_query_schema(query)

    cond do
      is_nil(schema) ->
        query

      has_auth?(schema) ->
        scope_name = Keyword.get(opts, :auth_scope) || hd(schema.__auth__(:scopes))
        schema.__auth_scope__(scope_name, query, context)

      policy && has_policy_scope?(policy, schema) ->
        scope_name = Keyword.get(opts, :auth_scope) || hd(policy.__scopes__(schema))
        policy.__apply_scope__(schema, scope_name, query, context)

      true ->
        query
    end
  end

  # --- JOIN scoping ---

  defp scope_joins(query, context, policy) do
    case query.joins do
      [] ->
        query

      joins ->
        updated = Enum.map(joins, &maybe_scope_join(&1, context, policy))
        %{query | joins: updated}
    end
  end

  defp maybe_scope_join(%{source: {_table, schema}} = join, context, policy)
       when is_atom(schema) and not is_nil(schema) do
    cond do
      has_auth?(schema) ->
        scope_name = hd(schema.__auth__(:scopes))
        wrap_join_in_subquery(join, schema, scope_name, context, :schema)

      policy && has_policy_scope?(policy, schema) ->
        scope_name = hd(policy.__scopes__(schema))
        wrap_join_in_subquery(join, schema, scope_name, context, {:policy, policy})

      true ->
        join
    end
  end

  # Subquery joins — recurse into the inner query
  defp maybe_scope_join(%{source: %Ecto.SubQuery{query: inner} = sub} = join, context, policy) do
    scoped_inner = scope_from(inner, [], context, policy)
    scoped_inner = scope_joins(scoped_inner, context, policy)
    %{join | source: %{sub | query: scoped_inner}}
  end

  defp maybe_scope_join(join, _context, _policy), do: join

  defp wrap_join_in_subquery(join, schema, scope_name, context, source) do
    inner = Ecto.Queryable.to_query(schema)

    scoped =
      case source do
        :schema -> schema.__auth_scope__(scope_name, inner, context)
        {:policy, policy} -> policy.__apply_scope__(schema, scope_name, inner, context)
      end

    # If the scope denied access (WHERE false), don't wrap the join —
    # the FROM-level scope already handles access control, and wrapping
    # with an empty subquery would break the parent query.
    if deny_all?(scoped) do
      join
    else
      scoped =
        if join.prefix,
          do: %{scoped | prefix: join.prefix},
          else: scoped

      %{join | source: %Ecto.SubQuery{query: scoped}}
    end
  end

  defp deny_all?(%{wheres: wheres}) do
    Enum.any?(wheres, fn %{expr: expr} -> expr == false end)
  end

  # --- Changeset scoping ---

  defp apply_changeset_scope(changeset, opts) do
    with schema when not is_nil(schema) <- get_changeset_schema(changeset),
         true <- has_changeset_auth?(schema),
         context when not is_nil(context) <- EctoAuth.Context.resolve_context(opts) do
      scope_name = Keyword.get(opts, :auth_scope) || hd(schema.__auth__(:changeset_scopes))
      {schema.__auth_changeset_scope__(scope_name, changeset, context), opts}
    else
      _ -> {changeset, opts}
    end
  end

  # --- Helpers ---

  defp get_query_schema(%Ecto.Query{from: %{source: {_table, schema}}}) when not is_nil(schema),
    do: schema

  defp get_query_schema(_), do: nil

  defp get_changeset_schema(%Ecto.Changeset{data: %{__struct__: schema}}), do: schema
  defp get_changeset_schema(_), do: nil

  defp has_auth?(schema) do
    Code.ensure_loaded?(schema) and
      function_exported?(schema, :__auth__, 1) and schema.__auth__(:scopes) != []
  end

  defp has_changeset_auth?(schema) do
    Code.ensure_loaded?(schema) and
      function_exported?(schema, :__auth__, 1) and schema.__auth__(:changeset_scopes) != []
  end

  defp has_policy_scope?(policy, schema) do
    Code.ensure_loaded?(policy) and
      function_exported?(policy, :__scopes__, 1) and policy.__scopes__(schema) != []
  end
end

defmodule EctoAuth.RepoTest do
  use ExUnit.Case, async: true

  alias EctoAuth.Test.{User, Organization, Project, UnscopedSchema}

  import Ecto.Query

  setup do
    Process.delete(:ecto_auth_context)
    :ok
  end

  describe "prepare_query/3 — FROM scoping" do
    test "applies scope when context is set" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})
      query = from(o in Organization)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])
      assert length(result.joins) == 2
    end

    test "skips when skip_auth: true" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})
      query = from(o in Organization)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, skip_auth: true)
      assert result.joins == []
    end

    test "skips when no context is set" do
      query = from(o in Organization)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])
      assert result.joins == []
    end

    test "skips for schemas without auth scopes" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})
      query = from(u in UnscopedSchema)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])
      assert result.joins == []
    end

    test "uses auth_context from opts over process dict" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})
      query = from(o in Organization)

      override_ctx = %{user: %User{id: 99}}
      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, auth_context: override_ctx)
      assert length(result.joins) == 2
    end

    test "uses specified auth_scope name" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})
      query = from(o in Organization)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, auth_scope: :member)
      assert length(result.joins) == 2
    end
  end

  describe "prepare_query/3 — JOIN scoping" do
    test "scopes joins on schemas with auth scopes" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})

      query =
        from o in UnscopedSchema,
          join: p in Project, on: p.organization_id == o.id

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])

      # The join on Project should be wrapped in a subquery
      [join] = result.joins
      assert %Ecto.SubQuery{query: inner} = join.source

      # The inner subquery should have the auth scope's joins + wheres
      assert length(inner.joins) == 2
      assert inner.wheres != []
    end

    test "leaves joins on unscoped schemas untouched" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})

      query =
        from o in Organization,
          join: u in UnscopedSchema, on: u.id == o.id

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])

      # Organization FROM gets scoped (2 joins from scope + 1 original = 3 total)
      # The UnscopedSchema join stays as-is (tuple source, not subquery)
      unscoped_join = Enum.find(result.joins, fn j ->
        match?({_, UnscopedSchema}, j.source)
      end)

      assert unscoped_join != nil
    end

    test "scopes both FROM and joins" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})

      query =
        from o in Organization,
          join: p in Project, on: p.organization_id == o.id

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])

      # FROM scope adds 2 joins (Member, Person)
      # Original Project join is wrapped in scoped subquery
      # So: 2 (from scope) + 1 (Project, now subquery) = 3 joins
      assert length(result.joins) == 3

      # Find the Project join — it should now be a subquery
      project_join = Enum.find(result.joins, fn j ->
        match?(%Ecto.SubQuery{}, j.source)
      end)

      assert project_join != nil
      assert %Ecto.SubQuery{query: inner} = project_join.source
      assert length(inner.joins) == 2
    end

    test "scope_joins: false disables join scoping" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})

      query =
        from o in UnscopedSchema,
          join: p in Project, on: p.organization_id == o.id

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, scope_joins: false)

      # Project join should NOT be wrapped in a subquery
      [join] = result.joins
      assert {_table, Project} = join.source
    end

    test "recurses into existing subquery joins" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})

      # A join that's already a subquery — should still get scoped
      inner_query = from(p in Project)

      query =
        from o in UnscopedSchema,
          join: p in subquery(inner_query), on: p.organization_id == o.id

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])

      [join] = result.joins
      assert %Ecto.SubQuery{query: inner} = join.source

      # The inner Project query should have auth scope applied
      assert length(inner.joins) == 2
      assert inner.wheres != []
    end
  end

  describe "prepare_changeset/3" do
    test "applies changeset scope when context is set" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}, allowed_org_ids: []})
      changeset = Ecto.Changeset.change(%Organization{id: 1, name: "Org"}, %{name: "New"})

      {result, _opts} = EctoAuth.Repo.prepare_changeset(:update, changeset, [])
      assert result.errors == [base: {"unauthorized", []}]
      refute result.valid?
    end

    test "passes through when authorized" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}, allowed_org_ids: [1]})
      changeset = Ecto.Changeset.change(%Organization{id: 1, name: "Org"}, %{name: "New"})

      {result, _opts} = EctoAuth.Repo.prepare_changeset(:update, changeset, [])
      assert result.errors == []
      assert result.valid?
    end

    test "skips when skip_auth: true" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}, allowed_org_ids: []})
      changeset = Ecto.Changeset.change(%Organization{id: 1, name: "Org"}, %{name: "New"})

      {result, _opts} = EctoAuth.Repo.prepare_changeset(:update, changeset, skip_auth: true)
      assert result.errors == []
    end

    test "skips when no context is set" do
      changeset = Ecto.Changeset.change(%Organization{id: 1, name: "Org"}, %{name: "New"})

      {result, _opts} = EctoAuth.Repo.prepare_changeset(:update, changeset, [])
      assert result.errors == []
    end

    test "skips for schemas without changeset scopes" do
      EctoAuth.Context.put_context(%{user: %User{id: 1}})
      changeset = Ecto.Changeset.change(%UnscopedSchema{id: 1, value: "v"}, %{value: "new"})

      {result, _opts} = EctoAuth.Repo.prepare_changeset(:update, changeset, [])
      assert result.errors == []
    end
  end
end

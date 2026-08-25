defmodule EctoAuth.SchemaTest do
  use ExUnit.Case, async: true

  alias EctoAuth.Test.{User, Organization, UnscopedSchema}

  test "schema defines __auth__(:scopes)" do
    assert Organization.__auth__(:scopes) == [:member]
  end

  test "schema defines __auth__(:changeset_scopes)" do
    assert Organization.__auth__(:changeset_scopes) == [:member]
  end

  test "__auth_scope__/3 modifies query" do
    import Ecto.Query
    query = from(o in Organization)
    context = %{user: %User{id: 42}}

    result = Organization.__auth_scope__(:member, query, context)
    assert %Ecto.Query{} = result
    # Verify the query has joins (the scope adds 2 joins)
    assert length(result.joins) == 2
  end

  test "__auth_changeset_scope__/3 adds errors for unauthorized" do
    changeset = Ecto.Changeset.change(%Organization{id: 1, name: "Org"}, %{name: "New"})
    context = %{user: %User{id: 1}, allowed_org_ids: []}

    result = Organization.__auth_changeset_scope__(:member, changeset, context)
    assert result.errors == [base: {"unauthorized", []}]
  end

  test "__auth_changeset_scope__/3 passes through for authorized" do
    changeset = Ecto.Changeset.change(%Organization{id: 1, name: "Org"}, %{name: "New"})
    context = %{user: %User{id: 1}, allowed_org_ids: [1]}

    result = Organization.__auth_changeset_scope__(:member, changeset, context)
    assert result.errors == []
  end

  test "unscoped schema does not export __auth__" do
    refute function_exported?(UnscopedSchema, :__auth__, 1)
  end
end

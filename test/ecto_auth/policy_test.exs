defmodule EctoAuth.PolicyTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias EctoAuth.Test.{User, PathOrg, PolicyOrg, AuthPolicy}

  setup do
    Process.delete(:ecto_auth_context)
    :ok
  end

  describe "policy module" do
    test "lists schemas" do
      assert PolicyOrg in AuthPolicy.__schemas__()
    end

    test "lists scopes for schema" do
      assert AuthPolicy.__scopes__(PolicyOrg) == [:member]
    end

    test "returns empty for unknown schema" do
      assert AuthPolicy.__scopes__(String) == []
    end

    test "applies scope to query" do
      context = %{user: %User{id: 42}}
      query = from(o in PolicyOrg)

      result = AuthPolicy.__apply_scope__(PolicyOrg, :member, query, context)

      assert %Ecto.Query{} = result
      assert length(result.joins) == 2
      assert result.wheres != []
    end
  end

  describe "policy via EctoAuth.Repo" do
    test "applies policy scope as fallback" do
      EctoAuth.Context.put_context(%{user: %User{id: 42}})
      query = from(o in PolicyOrg)

      # PolicyOrg has no schema-level auth — falls back to policy
      {result, _opts} =
        EctoAuth.Repo.prepare_query(:all, query, [], policy: AuthPolicy)

      assert length(result.joins) == 2
      assert result.wheres != []
    end

    test "schema scope takes precedence over policy" do
      EctoAuth.Context.put_context(%{user: %User{id: 42}})

      # PathOrg has schema-level scopes — policy is ignored
      query = from(o in PathOrg)

      {result_schema, _} = EctoAuth.Repo.prepare_query(:all, query, [], policy: AuthPolicy)
      assert length(result_schema.joins) == 2
    end

    test "skip_auth bypasses policy" do
      EctoAuth.Context.put_context(%{user: %User{id: 42}})
      query = from(o in PolicyOrg)

      {result, _opts} =
        EctoAuth.Repo.prepare_query(:all, query, [skip_auth: true], policy: AuthPolicy)

      assert result.joins == []
    end
  end
end

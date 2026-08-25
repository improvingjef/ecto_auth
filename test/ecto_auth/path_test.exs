defmodule EctoAuth.PathTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias EctoAuth.Test.{User, Person, Member, PathOrg, Employee, Team}

  setup do
    Process.delete(:ecto_auth_context)
    :ok
  end

  describe "resolve_steps/2" do
    test "walks association chain correctly" do
      assocs = EctoAuth.Path.resolve_steps(User, [:person, :members, :organization])

      assert length(assocs) == 3

      [a1, a2, a3] = assocs
      # User has_one :person → Person
      assert a1.owner == User
      assert a1.related == Person
      assert a1.related_key == :user_id

      # Person has_many :members → Member
      assert a2.owner == Person
      assert a2.related == Member
      assert a2.related_key == :person_id

      # Member belongs_to :organization → Organization
      assert a3.owner == Member
      assert a3.related == EctoAuth.Test.Organization
      assert a3.owner_key == :organization_id
    end

    test "raises on missing association" do
      assert_raise ArgumentError, ~r/no association :nonexistent/, fn ->
        EctoAuth.Path.resolve_steps(User, [:nonexistent])
      end
    end
  end

  describe "apply_path/3 — dot notation on schema" do
    test "builds correct joins" do
      context = %{user: %User{id: 42}}
      query = from(o in PathOrg)

      result = PathOrg.__auth_scope__(:member, query, context)

      assert %Ecto.Query{} = result
      # Should have 2 joins (Member + Person)
      assert length(result.joins) == 2
      assert result.wheres != []
    end
  end

  describe "apply_path/3 via EctoAuth.Repo" do
    test "applies path scope through prepare_query" do
      EctoAuth.Context.put_context(%{user: %User{id: 42}})
      query = from(o in PathOrg)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])

      assert length(result.joins) == 2
      assert result.wheres != []
    end

    test "skip_auth bypasses path scope" do
      EctoAuth.Context.put_context(%{user: %User{id: 42}})
      query = from(o in PathOrg)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, skip_auth: true)

      assert result.joins == []
      assert result.wheres == []
    end
  end

  describe "apply_path/3 — belongs_to first step" do
    test "builds correct joins when path starts with belongs_to" do
      context = %{employee: %Employee{id: 1, department_id: 42}}
      query = from(t in Team)

      result = EctoAuth.Path.apply_path(
        query,
        [:employee, :department, :teams],
        context
      )

      assert %Ecto.Query{} = result
      # Should have 1 join (departments)
      assert length(result.joins) == 1
      assert result.wheres != []
    end

    test "uses FK value (not PK) for belongs_to anchor" do
      context = %{employee: %Employee{id: 1, department_id: 42}}
      query = from(t in Team)

      result = EctoAuth.Path.apply_path(
        query,
        [:employee, :department, :teams],
        context
      )

      # The WHERE should use department_id (42), not employee id (1)
      [where] = result.wheres
      assert where.params == [{42, {1, :id}}]
    end

    test "works through schema auth_scope macro" do
      context = %{employee: %Employee{id: 1, department_id: 42}}
      query = from(t in Team)

      result = Team.__auth_scope__(:dept_member, query, context)

      assert %Ecto.Query{} = result
      assert length(result.joins) == 1
      assert result.wheres != []
    end

    test "works through EctoAuth.Repo.prepare_query" do
      EctoAuth.Context.put_context(%{employee: %Employee{id: 1, department_id: 42}})
      query = from(t in Team)

      {result, _opts} = EctoAuth.Repo.prepare_query(:all, query, [])

      assert length(result.joins) == 1
      assert result.wheres != []
    end
  end

  describe "apply_path/3 — nil anchor returns empty" do
    test "returns no rows when context is missing anchor key" do
      context = %{account: %User{id: 1}}
      query = from(o in PathOrg)

      result = EctoAuth.Path.apply_path(
        query,
        [:user, :person, :members, :organization],
        context
      )

      assert result.joins == []
      # WHERE false — guarantees zero rows
      assert [%{expr: false}] = result.wheres
    end

    test "returns no rows when anchor value is nil" do
      context = %{employee: %Employee{id: 1, department_id: nil}}
      query = from(t in Team)

      result = EctoAuth.Path.apply_path(
        query,
        [:employee, :department, :teams],
        context
      )

      assert result.joins == []
      assert [%{expr: false}] = result.wheres
    end
  end
end

defmodule EctoAuth.RepoWriteHookTest do
  @moduledoc """
  D0.3b (documentation/design/ecto-fork.html, "The write hook"): stock Ecto
  has no `prepare_changeset/3` repo callback, so `use EctoAuth.Repo`
  overrides `insert/2`, `update/2`, `delete/2` and their bang variants to
  run the hook itself and call through to Ecto's generated implementation.
  These tests exercise `EctoAuth.TestRepo` (test/support/test_repo.ex), a
  repo on a fake in-memory adapter — no database needed, mirroring how
  Ecto's own suite tests repo callbacks with `Ecto.TestAdapter`.
  """

  use ExUnit.Case, async: true

  alias EctoAuth.Test.{WriteHookParent, WriteHookChild}
  alias EctoAuth.TestRepo

  setup do
    Process.delete(:ecto_auth_test_hook)
    :ok
  end

  defp record_ops_hook(agent) do
    fn op, changeset, opts ->
      Agent.update(agent, &[op | &1])
      {changeset, opts}
    end
  end

  defp start_recorder do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    agent
  end

  defp recorded(agent), do: Agent.get(agent, &Enum.reverse/1)

  describe "each write function invokes the hook with the right operation atom" do
    test "insert/2" do
      agent = start_recorder()
      TestRepo.on_prepare_changeset(record_ops_hook(agent))

      assert {:ok, %WriteHookParent{}} = TestRepo.insert(%WriteHookParent{name: "a"})
      assert recorded(agent) == [:insert]
    end

    test "update/2" do
      agent = start_recorder()
      TestRepo.on_prepare_changeset(record_ops_hook(agent))

      changeset = Ecto.Changeset.change(%WriteHookParent{id: 1, name: "a"}, %{name: "b"})
      assert {:ok, %WriteHookParent{}} = TestRepo.update(changeset)
      assert recorded(agent) == [:update]
    end

    test "delete/2" do
      agent = start_recorder()
      TestRepo.on_prepare_changeset(record_ops_hook(agent))

      assert {:ok, %WriteHookParent{}} = TestRepo.delete(%WriteHookParent{id: 1, name: "a"})
      assert recorded(agent) == [:delete]
    end

    test "insert!/2" do
      agent = start_recorder()
      TestRepo.on_prepare_changeset(record_ops_hook(agent))

      assert %WriteHookParent{} = TestRepo.insert!(%WriteHookParent{name: "a"})
      assert recorded(agent) == [:insert]
    end

    test "update!/2" do
      agent = start_recorder()
      TestRepo.on_prepare_changeset(record_ops_hook(agent))

      changeset = Ecto.Changeset.change(%WriteHookParent{id: 1, name: "a"}, %{name: "b"})
      assert %WriteHookParent{} = TestRepo.update!(changeset)
      assert recorded(agent) == [:update]
    end

    test "delete!/2" do
      agent = start_recorder()
      TestRepo.on_prepare_changeset(record_ops_hook(agent))

      assert %WriteHookParent{} = TestRepo.delete!(%WriteHookParent{id: 1, name: "a"})
      assert recorded(agent) == [:delete]
    end
  end

  test "a hook that adds an error returns {:error, changeset} without touching the database" do
    TestRepo.on_prepare_changeset(fn _op, changeset, opts ->
      {Ecto.Changeset.add_error(changeset, :name, "denied"), opts}
    end)

    assert {:error, changeset} = TestRepo.insert(%WriteHookParent{name: "a"})
    assert changeset.errors == [name: {"denied", []}]

    # The fake adapter announces every write it actually performs by
    # message to self() (see EctoAuth.TestAdapter.insert/6) — assert none
    # arrived, i.e. the hook short-circuited before the adapter was ever
    # reached.
    refute_received {:insert, _meta}
  end

  test "insert!/2 raises Ecto.InvalidChangesetError, not touching the database, when the hook errors" do
    TestRepo.on_prepare_changeset(fn _op, changeset, opts ->
      {Ecto.Changeset.add_error(changeset, :name, "denied"), opts}
    end)

    assert_raise Ecto.InvalidChangesetError, fn ->
      TestRepo.insert!(%WriteHookParent{name: "a"})
    end

    refute_received {:insert, _meta}
  end

  test "a bare struct is accepted (not just a pre-built changeset)" do
    agent = start_recorder()

    TestRepo.on_prepare_changeset(fn _op, changeset, opts ->
      Agent.update(agent, &[changeset | &1])
      {changeset, opts}
    end)

    assert {:ok, %WriteHookParent{name: "a"}} = TestRepo.insert(%WriteHookParent{name: "a"})
    assert [%Ecto.Changeset{data: %WriteHookParent{name: "a"}}] = recorded(agent)
  end

  test "nested (has_many) association changesets pass through the hook" do
    agent = start_recorder()

    TestRepo.on_prepare_changeset(fn op, changeset, opts ->
      Agent.update(agent, &[{op, changeset.data.__struct__} | &1])
      {changeset, opts}
    end)

    changeset =
      %WriteHookParent{name: "parent"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:children, [%WriteHookChild{label: "child"}])

    assert {:ok, %WriteHookParent{children: [%WriteHookChild{}]}} = TestRepo.insert(changeset)

    # The top-level insert runs through the hook, and so does the child's
    # insert — `on_repo_change` (EctoAuth.Associations.HasOneOfMany's own
    # implementation, and stock Ecto.Association.Has's) dispatches back
    # through `apply(repo, action, [changeset, opts])`, i.e. through
    # `TestRepo.insert/2` again, which is exactly what's overridden.
    assert recorded(agent) == [insert: WriteHookParent, insert: WriteHookChild]
  end

  test "insert_all does not go through the hook" do
    agent = start_recorder()
    TestRepo.on_prepare_changeset(record_ops_hook(agent))

    TestRepo.insert_all(WriteHookParent, [%{name: "a"}, %{name: "b"}])

    assert recorded(agent) == []
  end
end

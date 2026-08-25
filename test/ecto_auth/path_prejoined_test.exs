defmodule EctoAuth.PathPrejoinedTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias EctoAuth.Test.{User, PathOrg}

  # Regression: a path scope applied to a query that ALREADY carries a join
  # must anchor its first generated join on the FROM (binding 0), not on the
  # caller's last binding. Found in production (Influx org picker): the old
  # anchoring produced `path_join.fk == callers_join.id` — zero rows.
  defp binding_refs(on_expr) do
    on_expr
    |> Macro.prewalk([], fn
      {:&, _, [ix]} = node, acc -> {node, [ix | acc]}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end

  test "first path join anchors on binding 0 even when the query is pre-joined" do
    context = %{user: %User{id: 42}}

    prejoined =
      from(o in PathOrg,
        join: other in PathOrg,
        on: other.id == o.id
      )

    scoped = PathOrg.__auth_scope__(hd(PathOrg.__auth__(:scopes)), prejoined, context)

    # The FIRST path-generated join sits right after the caller's own joins;
    # its ON must reference the FROM (binding 0), never the caller's join (1).
    # (Later path joins correctly chain on each other — not asserted here.)
    first_path_join = Enum.at(scoped.joins, length(prejoined.joins))
    refs = binding_refs(first_path_join.on.expr)
    assert 0 in refs, "first path join must anchor on the FROM, got #{inspect(refs)}"
    refute 1 in refs, "first path join must not anchor on the caller's own join"
  end

  test "bare query behavior is unchanged" do
    context = %{user: %User{id: 42}}
    scoped = PathOrg.__auth_scope__(hd(PathOrg.__auth__(:scopes)), from(o in PathOrg), context)
    assert length(scoped.joins) >= 1
    assert scoped.wheres != []
  end
end

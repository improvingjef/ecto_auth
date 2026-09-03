defmodule EctoAuth.Associations.HasOneOfManyTest do
  use ExUnit.Case, async: true

  alias EctoAuth.Test.Post
  alias EctoAuth.Test.Comment
  alias EctoAuth.Associations.HasOneOfMany

  test "Ecto.Schema.association/5 is the extension point has_one_of_many registers through" do
    # D0.3b (documentation/design/ecto-fork.html §B): the fork carried a copy
    # of this function as Ecto.Association.Options.association/5. On stock
    # Ecto it is Ecto.Schema.association/5, @doc false but stable across every
    # 3.x release. If a future Ecto release renames or removes it, this pins
    # the failure to a clear assertion here instead of a cryptic
    # UndefinedFunctionError at compile time of every schema using
    # has_one_of_many.
    Code.ensure_loaded!(Ecto.Schema)

    assert function_exported?(Ecto.Schema, :association, 5),
           "Ecto.Schema.association/5 is gone or changed arity — " <>
             "has_one_of_many/3 (lib/ecto_auth/associations/has_one_of_many.ex) " <>
             "registers the association type through it and needs updating"
  end

  test "association is defined on schema" do
    assoc = Post.__schema__(:association, :latest_comment)
    assert %HasOneOfMany{} = assoc
    assert assoc.cardinality == :one
    assert assoc.field == :latest_comment
    assert assoc.owner == Post
    assert assoc.related == Comment
    assert assoc.owner_key == :id
    assert assoc.related_key == :post_id
    assert assoc.order_by == [desc: :inserted_at]
  end

  test "has_many association still works alongside has_one_of_many" do
    assoc = Post.__schema__(:association, :comments)
    assert assoc.cardinality == :many
    assert assoc.related == Comment
  end

  test "builds correct assoc_query" do
    assoc = Post.__schema__(:association, :latest_comment)
    query = HasOneOfMany.assoc_query(assoc, nil, [1])

    assert %Ecto.Query{} = query
    # Should have a where clause and distinct
    assert query.distinct != nil
  end

  test "builds correct joins_query" do
    assoc = Post.__schema__(:association, :latest_comment)
    query = HasOneOfMany.joins_query(assoc)

    assert %Ecto.Query{} = query
    assert length(query.joins) == 1
  end

  test "preload_info returns correct tuple" do
    assoc = Post.__schema__(:association, :latest_comment)
    assert {:assoc, ^assoc, {0, :post_id}} = HasOneOfMany.preload_info(assoc)
  end

  test "build creates struct with owner key" do
    assoc = Post.__schema__(:association, :latest_comment)
    owner = %Post{id: 42, title: "hello"}

    result = HasOneOfMany.build(assoc, owner, %{})
    assert %Comment{} = result
    assert result.post_id == 42
  end

  test "not loaded placeholder has correct cardinality" do
    post = %Post{}
    assert %Ecto.Association.NotLoaded{__cardinality__: :one} = post.latest_comment
  end
end

defmodule EctoAuth.Associations.HasOneOfManyTest do
  use ExUnit.Case, async: true

  alias EctoAuth.Test.Post
  alias EctoAuth.Test.Comment
  alias EctoAuth.Associations.HasOneOfMany

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

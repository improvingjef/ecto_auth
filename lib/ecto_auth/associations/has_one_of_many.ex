defmodule EctoAuth.Associations.HasOneOfMany do
  @moduledoc """
  A custom association that provides `:one` cardinality from a `has_many`
  relationship, constrained by `order_by` and using a subquery for uniqueness.

  This is useful for patterns like "latest comment", "first reply",
  "highest-scored review", etc.

  ## Usage

      use EctoAuth.Schema

      schema "posts" do
        has_one_of_many :latest_comment, Comment,
          order_by: [desc: :inserted_at],
          foreign_key: :post_id
      end

  ## How it works

  For preloading, it builds a subquery that selects the first matching record
  per parent using `DISTINCT ON` (PostgreSQL) or a `ROW_NUMBER()` window
  function pattern.

  For joins, it uses a lateral join subquery with the ordering constraint.
  """

  import Ecto.Query

  @behaviour Ecto.Association

  defstruct [
    :cardinality,
    :field,
    :owner,
    :related,
    :owner_key,
    :related_key,
    :queryable,
    :on_cast,
    :order_by,
    on_delete: :nothing,
    on_replace: :raise,
    where: [],
    unique: true,
    defaults: [],
    relationship: :child,
    ordered: true,
    preload_order: []
  ]

  @doc """
  Macro to define a `has_one_of_many` association inside a schema block.

  ## Options

    * `:order_by` - (required) the ordering used to pick the "one" record.
      Example: `[desc: :inserted_at]`

    * `:foreign_key` - the foreign key on the related schema. Defaults to
      the owner module name singularized with `_id` appended.

    * `:references` - the key on the owner schema. Defaults to the primary key.

    * `:where` - additional static filters.

  """
  defmacro has_one_of_many(name, queryable, opts \\ []) do
    quote do
      Ecto.Association.Options.association(
        __MODULE__,
        :one,
        unquote(name),
        EctoAuth.Associations.HasOneOfMany,
        [queryable: unquote(queryable)] ++ unquote(opts)
      )
    end
  end

  @impl true
  def struct(module, name, opts) do
    queryable = Keyword.fetch!(opts, :queryable)
    related = Ecto.Association.related_from_query(queryable, name)

    ref =
      case Module.get_attribute(module, :primary_key) do
        {key, _type, _autogenerate} -> key
        nil -> raise ArgumentError, "has_one_of_many requires the owner to have a primary key"
      end

    owner_key = Keyword.get(opts, :references, ref)

    unless Module.get_attribute(module, :ecto_fields)[owner_key] do
      raise ArgumentError,
            "schema does not have field #{inspect(owner_key)} used by " <>
              "association #{inspect(name)}"
    end

    foreign_key =
      Keyword.get(opts, :foreign_key, Ecto.Association.association_key(module, owner_key))

    order_by = Keyword.get(opts, :order_by, [])

    unless is_list(order_by) and order_by != [] do
      raise ArgumentError,
            "has_one_of_many #{inspect(name)} requires a non-empty :order_by option"
    end

    preload_order = Ecto.Association.validate_preload_order!(name, order_by)

    %__MODULE__{
      cardinality: :one,
      field: name,
      owner: module,
      related: related,
      owner_key: owner_key,
      related_key: foreign_key,
      queryable: queryable,
      on_cast: nil,
      order_by: order_by,
      where: Keyword.get(opts, :where, []),
      preload_order: preload_order
    }
  end

  @impl true
  def after_verify_validation(%{queryable: queryable, related_key: related_key}) do
    cond do
      not is_atom(queryable) ->
        :ok

      not Code.ensure_loaded?(queryable) ->
        {:error, "associated schema #{inspect(queryable)} does not exist"}

      not function_exported?(queryable, :__schema__, 2) ->
        {:error, "associated module #{inspect(queryable)} is not an Ecto schema"}

      is_nil(queryable.__schema__(:type, related_key)) ->
        {:error,
         "associated schema #{inspect(queryable)} does not have field `#{related_key}`"}

      true ->
        :ok
    end
  end

  @impl true
  def build(
        %{owner_key: owner_key, related_key: related_key, queryable: queryable} = _refl,
        owner,
        attributes
      ) do
    related = Ecto.Association.related_from_query(queryable, nil)
    data = related.__struct__() |> struct(attributes)
    %{data | related_key => Map.get(owner, owner_key)}
  end

  @impl true
  def joins_query(
        %{
          related_key: related_key,
          owner: owner,
          owner_key: owner_key,
          queryable: queryable,
          order_by: order_by
        } = assoc
      ) do
    from(o in owner,
      join:
        q in subquery(
          from(x in queryable,
            where: field(x, ^related_key) == field(parent_as(:owner), ^owner_key),
            order_by: ^order_by,
            limit: 1
          )
        ),
      as: :owner,
      on: true
    )
    |> Ecto.Association.combine_joins_query(assoc.where, 1)
  end

  @impl true
  def assoc_query(
        %{related_key: related_key, queryable: queryable, order_by: order_by} = assoc,
        query,
        values
      ) do
    query = query || queryable

    from(x in query,
      where: field(x, ^related_key) in ^values,
      distinct: field(x, ^related_key),
      order_by: ^order_by
    )
    |> Ecto.Association.combine_assoc_query(assoc.where)
  end

  @impl true
  def preload_info(%{related_key: related_key} = refl) do
    {:assoc, refl, {0, related_key}}
  end

  @impl true
  def on_repo_change(
        %{related_key: related_key, owner_key: owner_key},
        %{data: parent, repo: repo},
        %{action: action} = changeset,
        _adapter,
        opts
      ) do
    value = Map.get(parent, owner_key)
    changeset = Ecto.Changeset.put_change(changeset, related_key, value)

    case apply(repo, action, [changeset, opts]) do
      {:ok, struct} -> {:ok, struct}
      {:error, changeset} -> {:error, changeset}
    end
  end
end

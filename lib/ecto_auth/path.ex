defmodule EctoAuth.Path do
  @moduledoc """
  Resolves context-relative association paths into Ecto query joins.

  A path is a list of atoms where the first element is a context key and the
  rest are association names. For example, `[:user, :buyer, :sites]` means:

      context.user --:buyer--> Buyer --:sites--> Site

  The anchor module is discovered at runtime from `context.user.__struct__`,
  then each association's metadata is read to get join keys.

  ## Dot notation

  Inside `auth_scope`, paths can be written as bare dot notation:

      auth_scope :buyer_access, user.buyer.sites

  This is equivalent to `[:user, :buyer, :sites]`.

  ## Generated SQL

  For the path `user.buyer.sites` with `context.user.buyer_id = 5`:

      FROM sites s
      JOIN buyers b ON b.id = s.buyer_id
      WHERE b.id = 5

  Resolved paths are cached in `:persistent_term` for zero-cost repeat access.
  """

  import Ecto.Query

  @doc """
  Applies an authorization path to a query.

  The path is `[context_key | association_steps]`. The context key selects
  the anchor record from the context map, and its `__struct__` provides
  the starting schema for association walking.
  """
  def apply_path(query, [context_key | steps], context) when is_atom(context_key) do
    anchor_record = context[context_key]

    if is_nil(anchor_record) do
      where(query, false)
    else
      anchor = anchor_record.__struct__
      assocs = get_or_resolve(anchor, steps)
      build_query(query, assocs, anchor, anchor_record)
    end
  end

  defp get_or_resolve(anchor, steps) do
    key = {:ecto_auth_path, anchor, steps}

    case :persistent_term.get(key, :not_cached) do
      :not_cached ->
        resolved = resolve_steps(anchor, steps)
        :persistent_term.put(key, resolved)
        resolved

      cached ->
        cached
    end
  end

  @doc false
  def resolve_steps(anchor, steps) do
    {assocs, _final} =
      Enum.reduce(steps, {[], anchor}, fn step, {acc, current} ->
        assoc = current.__schema__(:association, step)

        unless assoc do
          available = current.__schema__(:associations)

          raise ArgumentError,
                "no association #{inspect(step)} on #{inspect(current)}. " <>
                  "Available: #{inspect(available)}"
        end

        {acc ++ [assoc], assoc.related}
      end)

    assocs
  end

  defp build_query(query, assocs, anchor, anchor_record) do
    [where_assoc | join_assocs] = assocs

    {anchor_value, rk} = where_params(where_assoc, anchor, anchor_record)

    if is_nil(anchor_value) do
      where(query, false)
    else
      # Remaining assocs (reversed) → JOINs from target schema back to anchor.
      #
      # ANCHORING: the first generated join must bind the FROM (binding 0) —
      # never `[..., prev]`, which grabs whatever join the caller's query
      # already carries and silently produces a nonsense ON clause (zero
      # rows). Found in production by Influx's org picker, whose query
      # pre-joins before the scope is applied. Subsequent path joins chain
      # on the join we just added, where `[..., prev]` is correct. The final
      # WHERE has the sibling rule: bind the last path join if we added any,
      # else the FROM itself.
      join_assocs = Enum.reverse(join_assocs)

      {query, joined?} =
        join_assocs
        |> Enum.with_index()
        |> Enum.reduce({query, false}, fn {assoc, idx}, {q, _} ->
          schema = assoc.owner
          ok = assoc.owner_key
          ark = assoc.related_key

          q =
            if idx == 0 do
              join(q, :inner, [o], j in ^schema, on: field(j, ^ok) == field(o, ^ark))
            else
              join(q, :inner, [..., prev], j in ^schema, on: field(j, ^ok) == field(prev, ^ark))
            end

          {q, true}
        end)

      if joined? do
        where(query, [..., last], field(last, ^rk) == ^anchor_value)
      else
        where(query, [o], field(o, ^rk) == ^anchor_value)
      end
    end
  end

  defp where_params(%Ecto.Association.BelongsTo{} = assoc, _anchor, record) do
    {Map.get(record, assoc.owner_key), assoc.related_key}
  end

  defp where_params(assoc, anchor, record) do
    pk = hd(anchor.__schema__(:primary_key))
    {Map.get(record, pk), assoc.related_key}
  end
end

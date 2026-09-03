defmodule EctoAuth.TestAdapter do
  @moduledoc """
  A minimal in-process `Ecto.Adapter` for exercising `EctoAuth.Repo`'s write
  hook without a database. Modeled on Ecto's own `test/support/test_repo.exs`
  (not shipped in the hex package, so not reusable directly) — trimmed to
  just what `insert/2`, `update/2` and `delete/2` need to complete
  successfully against a fake, in-memory backend.
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Transaction

  defmacro __before_compile__(_opts), do: :ok

  def ensure_all_started(_, _), do: {:ok, []}

  def init(_opts) do
    {:ok, Supervisor.child_spec({Task, fn -> :timer.sleep(:infinity) end}, []), %{meta: :meta}}
  end

  def checkout(mod, _opts, fun) do
    Process.put({mod, :checked_out?}, true)

    try do
      fun.()
    after
      Process.delete({mod, :checked_out?})
    end
  end

  def checked_out?(mod), do: Process.get({mod, :checked_out?}) || false

  ## Types

  def loaders({:map, _}, type), do: [&Ecto.Type.embedded_load(type, &1, :json)]
  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders(_primitive, type), do: [type]

  def dumpers({:map, _}, type), do: [&Ecto.Type.embedded_dump(type, &1, :json)]
  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(_primitive, type), do: [type]

  def autogenerate(:id), do: nil
  def autogenerate(:embed_id), do: Ecto.UUID.autogenerate()
  def autogenerate(:binary_id), do: Ecto.UUID.bingenerate()

  ## Queryable

  def prepare(operation, query), do: {:nocache, {operation, query}}

  def execute(_, _meta, {:nocache, {:all, query}}, _params, _opts) do
    send(self(), {:all, query})
    results_for_all_query(query)
  end

  def execute(_, _meta, {:nocache, {op, query}}, _params, _opts) do
    send(self(), {op, query})
    {1, nil}
  end

  def stream(_, _meta, {:nocache, {:all, query}}, _params, _opts) do
    Stream.map([:execute], fn :execute -> results_for_all_query(query) end)
  end

  defp results_for_all_query(%{select: %{fields: [_ | _] = fields}}) do
    {1, [List.duplicate(nil, length(fields))]}
  end

  defp results_for_all_query(%{select: %{fields: []}}), do: {1, [[]]}
  defp results_for_all_query(_), do: {1, []}

  ## Schema

  def insert_all(_, meta, header, rows, on_conflict, returning, placeholders, opts) do
    meta =
      Map.merge(meta, %{
        header: header,
        on_conflict: on_conflict,
        returning: returning,
        placeholders: placeholders,
        prefix: opts[:prefix]
      })

    send(self(), {:insert_all, meta, rows})
    {length(if is_list(rows), do: rows, else: [rows]), nil}
  end

  def insert(_, %{context: nil, prefix: prefix} = meta, fields, on_conflict, returning, _opts) do
    meta = Map.merge(meta, %{fields: fields, on_conflict: on_conflict, returning: returning, prefix: prefix})
    send(self(), {:insert, meta})
    {:ok, Enum.zip(returning, 1..length(returning)//1)}
  end

  def insert(_, %{context: context}, _fields, _on_conflict, _returning, _opts), do: context

  def update(_, %{context: nil} = meta, [_ | _] = changes, filters, returning, _opts) do
    meta = Map.merge(meta, %{changes: changes, filters: filters, returning: returning})
    send(self(), {:update, meta})
    {:ok, Enum.zip(returning, 1..length(returning)//1)}
  end

  def update(_, %{context: nil}, [], _filters, _returning, _opts), do: {:ok, []}
  def update(_, %{context: context}, _changes, _filters, _returning, _opts), do: context

  def delete(_, %{context: nil} = meta, filters, returning, _opts) do
    meta = Map.merge(meta, %{filters: filters, returning: returning})
    send(self(), {:delete, meta})
    {:ok, Enum.zip(returning, 1..length(returning)//1)}
  end

  def delete(_, %{context: context}, _filters, _returning, _opts), do: context

  ## Transactions

  def transaction(mod, _opts, fun) do
    Process.put({mod, :in_transaction?}, true)

    try do
      {:ok, fun.()}
    catch
      :throw, {:ecto_rollback, value} -> {:error, value}
    after
      Process.delete({mod, :in_transaction?})
    end
  end

  def in_transaction?(mod), do: Process.get({mod, :in_transaction?}) || false

  def rollback(_, value) do
    throw({:ecto_rollback, value})
  end
end

defmodule EctoAuth.TestRepo do
  @moduledoc """
  A repo backed by `EctoAuth.TestAdapter` (no database) used to prove the
  `use EctoAuth.Repo` write hook actually fires around `insert`, `update`,
  `delete` and their bang variants, without standing up Postgres.

  Tests steer `prepare_changeset/3` per-call via the `:ecto_auth_test_hook`
  process dictionary key (set with `EctoAuth.TestRepo.on_prepare_changeset/1`)
  rather than repo config, since ExUnit runs each test in its own process
  and the dictionary is process-local — no cross-test leakage, no need for
  `async: false`.
  """

  use Ecto.Repo, otp_app: :ecto_auth, adapter: EctoAuth.TestAdapter
  use EctoAuth.Repo

  def prepare_changeset(op, changeset, opts) do
    case Process.get(:ecto_auth_test_hook) do
      nil -> EctoAuth.Repo.prepare_changeset(op, changeset, opts)
      hook when is_function(hook, 3) -> hook.(op, changeset, opts)
    end
  end

  @doc "Installs a per-process `prepare_changeset/3` implementation for the current test."
  def on_prepare_changeset(fun) when is_function(fun, 3) do
    Process.put(:ecto_auth_test_hook, fun)
  end
end

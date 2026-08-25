defmodule EctoAuth.ContextTest do
  use ExUnit.Case, async: true

  alias EctoAuth.Context

  setup do
    # Clean up process dict before each test
    Process.delete(:ecto_auth_context)
    :ok
  end

  test "put_context/get_context round-trips" do
    assert Context.get_context() == nil
    Context.put_context(%{user: %{id: 1}})
    assert Context.get_context() == %{user: %{id: 1}}
  end

  test "resolve_context prefers opts over process dict" do
    Context.put_context(%{user: %{id: 1}})
    override = %{user: %{id: 2}}
    assert Context.resolve_context(auth_context: override) == override
  end

  test "resolve_context falls back to process dict" do
    Context.put_context(%{user: %{id: 1}})
    assert Context.resolve_context([]) == %{user: %{id: 1}}
  end

  test "resolve_context returns nil when no context set" do
    assert Context.resolve_context([]) == nil
  end

  test "propagate carries context to new process" do
    Context.put_context(%{user: %{id: 42}})
    parent = self()

    fun = Context.propagate(fn ->
      send(parent, {:context, Context.get_context()})
    end)

    Task.async(fun) |> Task.await()
    assert_received {:context, %{user: %{id: 42}}}
  end

  test "propagate with nil context doesn't crash" do
    parent = self()

    fun = Context.propagate(fn ->
      send(parent, {:context, Context.get_context()})
    end)

    Task.async(fun) |> Task.await()
    assert_received {:context, nil}
  end

  test "with_context temporarily switches context" do
    Context.put_context(%{user: %{id: 1}})

    result = Context.with_context(%{user: %{id: 99}}, fn ->
      assert Context.get_context() == %{user: %{id: 99}}
      :inner_result
    end)

    assert result == :inner_result
    assert Context.get_context() == %{user: %{id: 1}}
  end

  test "with_context restores nil when no previous context" do
    assert Context.get_context() == nil

    Context.with_context(%{user: %{id: 1}}, fn ->
      assert Context.get_context() == %{user: %{id: 1}}
    end)

    assert Context.get_context() == nil
  end

  test "with_context restores previous context even on exception" do
    Context.put_context(%{user: %{id: 1}})

    assert_raise RuntimeError, fn ->
      Context.with_context(%{user: %{id: 2}}, fn ->
        raise "boom"
      end)
    end

    assert Context.get_context() == %{user: %{id: 1}}
  end
end

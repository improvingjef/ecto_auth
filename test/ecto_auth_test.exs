defmodule EctoAuthTest do
  use ExUnit.Case, async: true

  test "EctoAuth module exists" do
    assert is_list(EctoAuth.module_info())
  end
end

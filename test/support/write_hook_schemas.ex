defmodule EctoAuth.Test.WriteHookParent do
  @moduledoc "Fixture for `EctoAuth.Repo` write-hook tests (test/ecto_auth/repo_write_hook_test.exs)."
  use Ecto.Schema

  schema "write_hook_parents" do
    field :name, :string
    has_many :children, EctoAuth.Test.WriteHookChild, foreign_key: :parent_id
  end
end

defmodule EctoAuth.Test.WriteHookChild do
  @moduledoc "Fixture for `EctoAuth.Repo` write-hook tests (test/ecto_auth/repo_write_hook_test.exs)."
  use Ecto.Schema

  schema "write_hook_children" do
    field :label, :string
    belongs_to :parent, EctoAuth.Test.WriteHookParent
  end
end

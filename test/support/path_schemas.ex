defmodule EctoAuth.Test.PathOrg do
  @moduledoc "Organization scoped via context-relative path."
  use Ecto.Schema
  use EctoAuth.Schema

  schema "organizations" do
    field :name, :string

    auth_scope :member, user.person.members.organization
  end
end

defmodule EctoAuth.Test.PolicyOrg do
  @moduledoc "Organization with no schema-level scopes (uses external policy)."
  use Ecto.Schema

  schema "organizations" do
    field :name, :string
  end
end

defmodule EctoAuth.Test.AuthPolicy do
  use EctoAuth.Policy

  scope EctoAuth.Test.PolicyOrg, :member, [:user, :person, :members, :organization]
end

# --- belongs_to first-step test schemas ---

defmodule EctoAuth.Test.Department do
  use Ecto.Schema

  schema "departments" do
    field :name, :string
    has_many :employees, EctoAuth.Test.Employee
    has_many :teams, EctoAuth.Test.Team
  end
end

defmodule EctoAuth.Test.Employee do
  use Ecto.Schema

  schema "employees" do
    field :name, :string
    belongs_to :department, EctoAuth.Test.Department
  end
end

defmodule EctoAuth.Test.Team do
  @moduledoc "Team scoped via belongs_to first step: employee.department.teams"
  use Ecto.Schema
  use EctoAuth.Schema

  schema "teams" do
    field :name, :string
    belongs_to :department, EctoAuth.Test.Department

    auth_scope :dept_member, employee.department.teams
  end
end

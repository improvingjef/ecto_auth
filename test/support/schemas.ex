defmodule EctoAuth.Test.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    has_one :person, EctoAuth.Test.Person
    has_many :persons, EctoAuth.Test.Person
  end
end

defmodule EctoAuth.Test.Person do
  use Ecto.Schema

  schema "persons" do
    field :name, :string
    belongs_to :user, EctoAuth.Test.User
    has_many :members, EctoAuth.Test.Member
  end
end

defmodule EctoAuth.Test.Member do
  use Ecto.Schema

  schema "members" do
    field :role, :string
    belongs_to :person, EctoAuth.Test.Person
    belongs_to :organization, EctoAuth.Test.Organization
  end
end

defmodule EctoAuth.Test.Organization do
  use Ecto.Schema
  use EctoAuth.Schema

  import Ecto.Query

  schema "organizations" do
    field :name, :string
    has_many :members, EctoAuth.Test.Member

    auth_scope :member, fn query, context ->
      from o in query,
        join: m in EctoAuth.Test.Member, on: m.organization_id == o.id,
        join: p in EctoAuth.Test.Person, on: p.id == m.person_id,
        where: p.user_id == ^context.user.id
    end

    auth_changeset_scope :member, fn changeset, context ->
      org = changeset.data

      if org.id && org.id in (context[:allowed_org_ids] || []) do
        changeset
      else
        Ecto.Changeset.add_error(changeset, :base, "unauthorized")
      end
    end
  end
end

defmodule EctoAuth.Test.Project do
  use Ecto.Schema
  use EctoAuth.Schema

  schema "projects" do
    field :title, :string
    belongs_to :organization, EctoAuth.Test.Organization

    auth_scope :team, user.person.members.organization
  end
end

defmodule EctoAuth.Test.UnscopedSchema do
  use Ecto.Schema

  schema "unscoped" do
    field :value, :string
  end
end

defmodule EctoAuth do
  @moduledoc """
  Relation-based authorization for Ecto.

  EctoAuth adds transparent authorization scoping to Ecto queries and
  changesets. It works by hooking into Ecto's `prepare_query/3` and
  `prepare_changeset/3` callbacks to automatically apply authorization
  rules defined on your schemas.

  ## Setup

  1. Define auth scopes on your schemas:

      ```elixir
      defmodule MyApp.Organization do
        use Ecto.Schema
        use EctoAuth.Schema

        schema "organizations" do
          field :name, :string

          auth_scope :member, fn query, context ->
            from o in query,
              join: m in MyApp.Member, on: m.organization_id == o.id,
              where: m.user_id == ^context.user.id
          end
        end
      end
      ```

  2. Wire your Repo:

      ```elixir
      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres

        def prepare_query(op, query, opts),
          do: EctoAuth.Repo.prepare_query(op, query, opts)

        def prepare_changeset(op, cs, opts),
          do: EctoAuth.Repo.prepare_changeset(op, cs, opts)
      end
      ```

  3. Set the auth context (e.g., in a Plug):

      ```elixir
      plug EctoAuth.Plug
      ```

  ## Bypass

      Repo.all(Organization, skip_auth: true)

  ## Explicit context

      Repo.all(Organization, auth_context: %{user: admin})

  """
end

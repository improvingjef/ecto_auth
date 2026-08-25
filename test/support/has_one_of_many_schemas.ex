defmodule EctoAuth.Test.Comment do
  use Ecto.Schema

  schema "comments" do
    field :body, :string
    field :inserted_at, :utc_datetime
    belongs_to :post, EctoAuth.Test.Post
  end
end

defmodule EctoAuth.Test.Post do
  use Ecto.Schema
  use EctoAuth.Schema

  schema "posts" do
    field :title, :string
    has_many :comments, EctoAuth.Test.Comment

    has_one_of_many :latest_comment, EctoAuth.Test.Comment,
      order_by: [desc: :inserted_at],
      foreign_key: :post_id
  end
end

defmodule EctoAuth.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_auth,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, github: "improvingjef/ecto", ref: "8b42a813d0b264b1f36c777821b76d9053d7d9b3"}
    ]
  end
end

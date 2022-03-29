defmodule ModKit.MixProject do
  use Mix.Project

  def project do
    [
      app: :modkit,
      version: "0.1.2",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end
end

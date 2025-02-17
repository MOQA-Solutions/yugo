defmodule Yugo.MixProject do
  use Mix.Project

  def project do
    [
      app: :yugo,
      version: "1.0.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Yugo is an easy and high-level IMAP client library.",
      package: package(),
      name: "Yugo",
      source_url: "https://github.com/Flying-Toast/yugo",
      docs: [
        source_ref: "master",
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:req, "~>0.5.0"}, 
      # {:mnesia_database, git: "https://github.com/MOQA-Solutions/mnesia_database"}
      {:mnesia_database, path: "/home/abdelghani/fds/mnesia_database"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Flying-Toast/yugo"}
    ]
  end
end

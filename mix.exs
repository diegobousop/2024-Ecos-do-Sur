defmodule Chatbot.MixProject do
  use Mix.Project

  def project do
    [
      app: :chatbot,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      releases: [
	first_release: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        cookie: "chatbot_first_cookie"
      ],
	second_release: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        cookie: "chatbot_second_cookie"
      ],
        third_release: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        cookie: "chatbot_third_cookie"
      ]
    ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Chatbot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telegram, git: "https://github.com/visciang/telegram.git", tag: "1.2.1"},
      {:poolboy, "~> 1.5.2"},
      {:credo, "~> 1.7.5"},
      {:gettext, "~> 0.24.0"},
      {:httpoison, "~> 2.2.1"},
      {:poison, "~> 5.0.0"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end

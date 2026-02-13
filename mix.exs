defmodule Arke.MixProject do
  use Mix.Project

  @version "0.4.4"
  @scm_url "https://github.com/arkemishub/arke"
  @site_url "https://arkehub.com"

  def project do
    [
      app: :arke,
      name: "Arke",
      version: @version,
      build_path: "./_build",
      config_path: "./config/config.exs",
      deps_path: "./deps",
      lockfile: "./mix.lock",
      elixir: "~> 1.13",
      source_url: @scm_url,
      homepage_url: @site_url,
      dialyzer: [plt_add_apps: ~w[eex]a],
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      aliases: aliases(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: false],
      versioning: versioning()
    ]
  end

  defp versioning do
    [
      tag_prefix: "v",
      commit_msg: "v%s",
      annotation: "tag release-%s created with mix_version",
      annotate: true
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Arke.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:typed_struct, "~> 0.3.0"},
      {:uuid, "~> 1.1"},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:timex, "~> 3.7.11"},
      {:google_api_storage, "~> 0.34.0"},
      {:goth, "~> 1.3.0"},
      {:httpoison, "~> 2.0"},
      {:calendar, "~> 1.0.0"},
      {:xlsxir, "~> 1.6"},
      {:libcluster, "~> 3.3"}
    ]
  end

  defp aliases do
    [
      test: [
        "test"
      ],
      "test.ci": [
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Arke low code framework Core"
  end

  defp package() do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "arke",
      # These are the default files included in the package
      licenses: ["Apache-2.0"],
      links: %{
        "Website" => @site_url,
        "Github" => @scm_url
      }
    ]
  end
end

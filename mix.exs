defmodule Arke.MixProject do
  use Mix.Project

  @version "0.7.0"
  @scm_url "https://github.com/arkemis/arke"
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
      {:jason, "~> 1.0"},
      {:uuid, "~> 1.1"},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.3", only: :test},
      {:req, "~> 0.7"},
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
      files: ~w(lib mix.exs README* LICENSE* CHANGELOG* usage-rules.md usage-rules),
      licenses: ["Apache-2.0"],
      links: %{
        "Website" => @site_url,
        "Github" => @scm_url
      }
    ]
  end
end

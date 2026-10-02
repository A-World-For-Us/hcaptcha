defmodule Hcaptcha.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/A-World-For-Us/hcaptcha"

  def project do
    [
      app: :hcaptcha,
      name: "hcaptcha",
      source_url: @source_url,
      version: @version,
      elixir: "~> 1.17",
      description: description(),
      deps: deps(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,

      # Dialyzer:
      dialyzer: [
        list_unused_filters: true,
        ignore_warnings: ".dialyzer_ignore.exs",
        # Put the project-level PLT in the priv/ directory (instead of the default _build/ location)
        # for the CI to be able to cache it between builds
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :test
      ]
    ]
  end

  defp description do
    """
    A simple hCaptcha package for Elixir applications, provides verification
    and templates for rendering forms with the hCaptcha widget
    """
  end

  defp deps do
    [
      {:httpoison, "~> 3.0"},
      {:jason, "~> 1.4", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end
end

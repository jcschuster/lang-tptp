defmodule LangTptp.MixProject do
  use Mix.Project

  def project do
    [
      app: :lang_tptp_gen,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tptp, "~> 0.3.0"},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end
end

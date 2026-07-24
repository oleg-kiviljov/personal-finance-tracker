defmodule PersonalFinanceTracker.MixProject do
  use Mix.Project

  def project do
    [
      app: :personal_finance_tracker,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      usage_rules: usage_rules(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Synced into CLAUDE.md by `mix usage_rules.sync`. Phoenix core rules inlined; ecto/live_vue and
  # ALL Ash rules linked (fetched on demand) to keep the file lean.
  defp usage_rules do
    [
      file: "CLAUDE.md",
      usage_rules: [
        "phoenix:elixir",
        "phoenix:html",
        "phoenix:liveview",
        "phoenix:phoenix",
        {"phoenix:ecto", link: :markdown},
        {"live_vue", link: :markdown},
        {~r/^ash_/, link: :markdown},
        {:ash,
         link: :markdown,
         sub_rules: [
           "authorization",
           "code_interfaces",
           "code_structure",
           "migrations",
           "actions",
           "relationships",
           "calculations",
           "aggregates",
           "testing",
           "data_layers",
           "exist_expressions",
           "query_filter",
           "querying_data",
           "generating_code"
         ]}
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {PersonalFinanceTracker.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ash_credo, "~> 0.15", only: [:dev, :test], runtime: false},
      {:quickbeam, "~> 0.8"},
      {:live_vue, "~> 1.0"},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:oban, "~> 2.0"},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.6", only: [:dev]},
      {:live_debugger, "~> 1.0", only: [:dev]},
      {:oban_web, "~> 2.0"},
      {:ash_oban, "~> 0.8"},
      {:ash_postgres, "~> 2.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash, "~> 3.0"},
      # SAT solver Ash uses to solve authorization policies (required once resources declare policies).
      {:picosat_elixir, "~> 0.2"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      # Test-data setup uses Ash idioms (domain code interfaces, Ash.Generator, Ash.Seed) — no
      # ExMachina. stream_data (which Ash.Generator + property tests use) comes transitively via ash,
      # so it is not declared here.
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      # Quiet flags: npm's audit/funding banners are pure noise in the build sandbox's console
      # stream; errors still print at loglevel=error.
      "assets.setup": ["phoenix_vite.npm assets install --no-audit --no-fund --loglevel=error"],
      "assets.build": [
        "phoenix_vite.npm vite build --manifest --ssrManifest --emptyOutDir true",
        "phoenix_vite.npm vite build --emptyOutDir false --ssr js/server.js --outDir ../priv/static"
      ],
      "assets.deploy": [
        "assets.build"
      ],
      precommit: [
        # (The "TagEngine as an EEx.Engine is deprecated" warning that forced this flag off came
        # from live_vue 1.2.1's sigil_H, not LV itself — fixed in live_vue 1.2.2, which calls
        # TagEngine.compile/2.)
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        # Ignore the CSP finding by TYPE, not by fingerprint. `--skip` (.sobelow-skips) keys on the
        # file path, so the scaffolder's web-module rename (personal_finance_tracker_web → <app>_web)
        # broke the skip and failed every generated app's CI. `-i Config.CSP` is rename-independent and
        # still catches NEW sobelow findings in generated code. (Add a real CSP to drop this later.)
        "sobelow --exit -i Config.CSP",
        "deps.audit",
        "test"
      ]
    ]
  end
end

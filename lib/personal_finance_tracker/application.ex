defmodule PersonalFinanceTracker.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PersonalFinanceTrackerWeb.Telemetry,
      PersonalFinanceTracker.Repo,
      {DNSCluster,
       query: Application.get_env(:personal_finance_tracker, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:personal_finance_tracker, :ash_domains),
         Application.fetch_env!(:personal_finance_tracker, Oban)
       )},
      {Phoenix.PubSub, name: PersonalFinanceTracker.PubSub},
      # Start a worker by calling: PersonalFinanceTracker.Worker.start_link(arg)
      # {PersonalFinanceTracker.Worker, arg},
      # Start to serve requests, typically the last entry
      PersonalFinanceTrackerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PersonalFinanceTracker.Supervisor]

    children =
      children ++
        if(Application.get_env(:live_vue, :ssr_module) == LiveVue.SSR.QuickBEAM,
          # SSRRuntime starts the QuickBEAM SSR runtime with a 32 MB JS stack (LiveVue's own child
          # runs at the 8 MB default, which Nuxt UI's tailwind-merge init overflows). It registers
          # under the LiveVue.SSR.QuickBEAM name, so render/3 is unaffected.
          do: [PersonalFinanceTracker.SSRRuntime],
          else: []
        )

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PersonalFinanceTrackerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

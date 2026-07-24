defmodule PersonalFinanceTrackerWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use PersonalFinanceTrackerWeb, :controller
      use PersonalFinanceTrackerWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: PersonalFinanceTrackerWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: PersonalFinanceTrackerWeb.Gettext

      # Add support for Vue components
      use LiveVue

      # Generate component for each vue file, so you can use <.ComponentName> syntax
      # instead of <.vue v-component="ComponentName">
      use LiveVue.Components, vue_root: ["./assets/vue", "./lib/personal_finance_tracker_web"]

      # Override ~H sigil to inject shared props into <.vue> tags
      # Configure shared props in config :live_vue, :shared_props
      import Phoenix.Component, except: [sigil_H: 2]
      import LiveVue.SharedPropsView, only: [sigil_H: 2]

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import PersonalFinanceTrackerWeb.CoreComponents
      # LiveVue helpers (to_vue_form/1 — normalize forms before passing them to Vue islands)
      import PersonalFinanceTrackerWeb.LiveVueHelpers

      # Common modules used in templates
      alias PersonalFinanceTrackerWeb.Layouts
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: PersonalFinanceTrackerWeb.Endpoint,
        router: PersonalFinanceTrackerWeb.Router,
        statics: PersonalFinanceTrackerWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end

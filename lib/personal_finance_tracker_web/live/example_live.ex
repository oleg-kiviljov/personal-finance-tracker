defmodule PersonalFinanceTrackerWeb.ExampleLive do
  @moduledoc """
  ⚠️  EXAMPLE PAGE — DELETE ME.

  A throwaway reference showing the LiveView ↔ LiveVue ↔ Nuxt UI form pattern this template is built
  around. It is wired to `/` only so a fresh scaffold renders something real.

  When you build your first feature, **delete this file and `assets/vue/ExampleForm.vue`** and point
  `/` (in `router.ex`) at your own LiveView. Nothing else depends on these two files.

  Patterns to copy (they recur in every feature — this is why the example exists):

    * `connected?/1`-guarded data loading — Iron Law #1: no DB queries in the disconnected mount.
    * `to_vue_form/1` — normalize a form before it becomes a Vue prop (see `LiveVueHelpers`); an
      `AshPhoenix.Form` create form has `data: nil` and crashes LiveVue SSR without it.
    * the `"validate"` / `"submit"` event round-trip, driven from the Vue island.
    * binding Nuxt UI inputs to `useLiveForm` fields — see `ExampleForm.vue`.

  A real feature backs the form with `AshPhoenix.Form` instead of the plain in-memory `to_form/2`
  used here — the LiveView shape is identical, only the form *source* differs. The `# with Ash:`
  comments mark the exact seams.
  """
  use PersonalFinanceTrackerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # DB access belongs ONLY inside `if connected?` (Iron Law #1). This example has no DB, but the
    # guard shows the shape: load real data (lists, categories, …) in the connected branch and keep
    # the disconnected first render query-free.
    socket =
      if connected?(socket) do
        assign(socket, :status, "connected — load your data here")
      else
        assign(socket, :status, "connecting…")
      end

    {:ok, assign(socket, :form, blank_form())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.vue v-component="ExampleForm" form={@form} status={@status} />
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    # with Ash: form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, :form, params_form(params))}
  end

  @impl true
  def handle_event("submit", %{"form" => params}, socket) do
    # with Ash: case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
    case validate(params) do
      [] ->
        {:noreply,
         socket
         |> assign(:form, blank_form())
         |> put_flash(:info, "Submitted — thanks, #{params["name"]}!")}

      _errors ->
        {:noreply, assign(socket, :form, params_form(params))}
    end
  end

  # with Ash: to_vue_form(AshPhoenix.Form.for_create(YourResource, :create, domain: YourDomain, as: "form"))
  defp blank_form, do: params_form(%{"name" => "", "message" => ""})

  # Build a form from params, surfacing validation errors — always run it through `to_vue_form/1`.
  defp params_form(params),
    do: to_vue_form(to_form(params, as: "form", errors: validate(params)))

  # Trivial stand-in for real (Ash) validation: name is required.
  defp validate(params) do
    if String.trim(params["name"] || "") == "", do: [name: {"is required", []}], else: []
  end
end

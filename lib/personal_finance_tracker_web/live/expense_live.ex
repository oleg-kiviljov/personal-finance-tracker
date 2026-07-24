defmodule PersonalFinanceTrackerWeb.ExpenseLive do
  @moduledoc """
  Log a new expense. The Vue island (`ExpenseForm`) is a reactive view of an `AshPhoenix.Form` for
  the `Expense :log` action plus the list of categories, both owned here as LiveView assigns.
  """
  use PersonalFinanceTrackerWeb, :live_view

  alias PersonalFinanceTracker.Expenses
  alias PersonalFinanceTracker.Expenses.Expense

  @impl true
  def mount(_params, _session, socket) do
    # Iron Law #1: no DB in the disconnected mount. The form has no DB dependency so it is built in
    # both branches; categories load only once connected.
    socket =
      if connected?(socket) do
        assign(socket, :categories, load_categories())
      else
        assign(socket, :categories, [])
      end

    {:ok, assign(socket, :form, build_form())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.vue v-component="ExpenseForm" form={@form} categories={@categories} />
    </Layouts.app>
    """
  end

  # NOTE: single-user app with no authentication yet — the form is built with `authorize?: false`
  # (see build_form/0). When auth lands, thread an `actor:` through validate/submit and drop the
  # bypass (Iron Law #8: authorize every handle_event).
  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
    {:noreply, assign(socket, :form, to_vue_form(form))}
  end

  @impl true
  def handle_event("submit", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _expense} ->
        {:noreply,
         socket
         |> assign(:form, build_form())
         |> put_flash(:info, "Expense logged.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_vue_form(form))}
    end
  end

  defp load_categories do
    Expenses.list_categories!(authorize?: false)
    |> Enum.map(&%{id: &1.id, name: &1.name})
  end

  defp build_form do
    to_vue_form(
      AshPhoenix.Form.for_create(Expense, :log,
        domain: Expenses,
        as: "form",
        authorize?: false
      )
    )
  end
end

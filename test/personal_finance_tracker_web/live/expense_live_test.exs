defmodule PersonalFinanceTrackerWeb.ExpenseLiveTest do
  # async: true is safe — each test runs in its own sandboxed transaction, so the per-test
  # seed_default_categories/0 inserts are isolated.
  use PersonalFinanceTrackerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PersonalFinanceTracker.Expenses

  setup do
    categories = Expenses.seed_default_categories()
    %{categories: categories, food: Enum.find(categories, &(&1.name == "food"))}
  end

  test "renders the ExpenseForm island with the default categories as a prop", %{
    conn: conn,
    categories: categories
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    vue = LiveVue.Test.get_vue(view)
    assert vue.component == "ExpenseForm"

    prop_names = Enum.map(vue.props["categories"], & &1["name"])
    # The prop mirrors exactly what is in the database (no drift).
    assert MapSet.new(prop_names) == MapSet.new(Enum.map(categories, & &1.name))
    assert "food" in prop_names
    assert length(prop_names) >= 5
  end

  test "submitting a valid expense persists it and flashes a confirmation", %{
    conn: conn,
    food: food
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "submit", %{
      "form" => %{"amount" => "24.99", "category_id" => food.id, "note" => "Weekly shop"}
    })

    assert has_element?(view, "#flash-info", "Expense logged.")

    # Genuinely persisted with today's date and the given values.
    assert [expense] = Expenses.list_expenses!(authorize?: false)
    assert Decimal.equal?(expense.amount, Decimal.new("24.99"))
    assert expense.category_id == food.id
    assert expense.note == "Weekly shop"
    assert expense.date == Date.utc_today()

    # The form is reset to a blank create form after success.
    vue = LiveVue.Test.get_vue(view)
    assert vue.props["form"]["values"]["amount"] in [nil, ""]
  end

  test "validating without an amount surfaces an inline amount error before submit", %{
    conn: conn,
    food: food
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "validate", %{
      "form" => %{"amount" => "", "category_id" => food.id, "note" => ""}
    })

    # Nothing is persisted by validation.
    assert Expenses.list_expenses!(authorize?: false) == []

    vue = LiveVue.Test.get_vue(view)
    assert field_error?(vue.props["form"], "amount", "is required")
    refute field_error?(vue.props["form"], "category_id", "is required")
  end

  test "submitting without an amount is rejected and surfaces an amount error", %{
    conn: conn,
    food: food
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "submit", %{
      "form" => %{"amount" => "", "category_id" => food.id, "note" => ""}
    })

    assert Expenses.list_expenses!(authorize?: false) == []

    vue = LiveVue.Test.get_vue(view)
    assert field_error?(vue.props["form"], "amount", "is required")
  end

  test "submitting without a category is rejected and surfaces a category error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "submit", %{
      "form" => %{"amount" => "10.00", "category_id" => "", "note" => ""}
    })

    assert Expenses.list_expenses!(authorize?: false) == []

    vue = LiveVue.Test.get_vue(view)
    assert field_error?(vue.props["form"], "category_id", "is required")
  end

  # The serialized AshPhoenix.Form prop carries `errors` as a field-keyed map
  # (`%{"amount" => ["is required"], ...}` after the JSON round-trip). Assert the message lives in
  # THIS field's own error list — co-located, so a different field's error can't satisfy it.
  defp field_error?(form_prop, field, message) when is_map(form_prop) do
    case get_in(form_prop, ["errors", field]) do
      msgs when is_list(msgs) -> Enum.any?(msgs, &(&1 =~ message))
      _ -> false
    end
  end
end

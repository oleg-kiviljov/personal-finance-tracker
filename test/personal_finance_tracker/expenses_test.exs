defmodule PersonalFinanceTracker.ExpensesTest do
  @moduledoc """
  Domain-level acceptance tests for logging an expense.
  """
  use PersonalFinanceTracker.DataCase, async: true

  alias PersonalFinanceTracker.Expenses

  setup do
    {:ok, category} = Expenses.create_category("Groceries", authorize?: false)
    %{category: category}
  end

  describe "log_expense/3" do
    test "saves an expense permanently and it can be read back", %{category: category} do
      assert {:ok, expense} =
               Expenses.log_expense(Decimal.new("12.50"), category.id, authorize?: false)

      # Read it back fresh from the DB — proves it persists between sessions.
      assert {:ok, reloaded} = Expenses.get_expense(expense.id, authorize?: false)
      assert Decimal.equal?(reloaded.amount, Decimal.new("12.50"))
      assert reloaded.category_id == category.id
    end

    test "sets the date to today automatically", %{category: category} do
      assert {:ok, expense} =
               Expenses.log_expense(Decimal.new("5.00"), category.id, authorize?: false)

      assert expense.date == Date.utc_today()
    end

    test "date is not a user-settable input", %{category: category} do
      # :date is writable? false and absent from the action's accept list — it can never be
      # supplied by the caller (or a crafted form POST); the attribute default owns it.
      action = Ash.Resource.Info.action(PersonalFinanceTracker.Expenses.Expense, :log)
      refute :date in action.accept

      # Logging still yields today regardless.
      assert {:ok, expense} =
               Expenses.log_expense(Decimal.new("5.00"), category.id, authorize?: false)

      assert expense.date == Date.utc_today()
    end

    test "accepts an optional note", %{category: category} do
      assert {:ok, with_note} =
               Expenses.log_expense(
                 Decimal.new("9.99"),
                 category.id,
                 %{note: "Lunch with a friend"},
                 authorize?: false
               )

      assert with_note.note == "Lunch with a friend"

      # Note is optional — logging without one still succeeds.
      assert {:ok, without_note} =
               Expenses.log_expense(Decimal.new("9.99"), category.id, authorize?: false)

      assert without_note.note == nil
    end

    test "amount is stored as a decimal (euros), never a float", %{category: category} do
      assert {:ok, expense} =
               Expenses.log_expense(Decimal.new("19.95"), category.id, authorize?: false)

      assert %Decimal{} = expense.amount
      refute is_float(expense.amount)
    end

    test "rejects an expense with no amount and reports the amount field", %{category: category} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Expenses.log_expense(nil, category.id, authorize?: false)

      assert :amount in invalid_fields(error)
    end

    test "rejects a non-positive amount on the amount field", %{category: category} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Expenses.log_expense(Decimal.new("0"), category.id, authorize?: false)

      assert :amount in invalid_fields(error)
    end

    test "rejects an expense with no category and reports the category field" do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Expenses.log_expense(Decimal.new("10.00"), nil, authorize?: false)

      assert :category_id in invalid_fields(error)
    end
  end

  describe "default categories" do
    test "a few defaults are seeded idempotently and available for selection" do
      first = Expenses.seed_default_categories()
      names = Enum.map(first, & &1.name)

      # A few defaults exist (stored lowercase).
      assert "food" in names
      assert length(first) >= 5

      # Running again does not duplicate them.
      second = Expenses.seed_default_categories()
      assert length(second) == length(first)
    end
  end

  describe "categories" do
    test "cannot be deleted (no destroy action exists)" do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.destroy(hd(Expenses.list_categories!(authorize?: false)), authorize?: false)
    end
  end

  defp invalid_fields(%Ash.Error.Invalid{errors: errors}) do
    Enum.flat_map(errors, fn
      %{field: field} when not is_nil(field) -> [field]
      _ -> []
    end)
  end
end

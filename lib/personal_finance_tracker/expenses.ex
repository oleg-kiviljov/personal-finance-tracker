defmodule PersonalFinanceTracker.Expenses do
  @moduledoc """
  Expense tracking domain — categories and logged expenses.
  """
  use Ash.Domain,
    otp_app: :personal_finance_tracker

  resources do
    resource PersonalFinanceTracker.Expenses.Category do
      define :create_category, action: :create, args: [:name]
      define :rename_category, action: :rename, args: [:name]
      define :list_categories, action: :read
      define :get_category, action: :read, get_by: [:id]
    end

    resource PersonalFinanceTracker.Expenses.Expense do
      define :log_expense, action: :log, args: [:amount, :category_id]
      define :list_expenses, action: :read
      define :get_expense, action: :read, get_by: [:id]
      define :destroy_expense, action: :destroy
    end
  end

  @default_category_names [
    "Food",
    "Rent",
    "Electricity",
    "Transport",
    "Healthcare",
    "Entertainment",
    "Other"
  ]

  @doc "The default spending categories a fresh install ships with."
  @spec default_category_names() :: [String.t()]
  def default_category_names, do: @default_category_names

  @doc """
  Idempotently create the default categories. Safe to run repeatedly — existing categories
  (matched case-insensitively via the unique identity) are left untouched. Returns the full list
  of categories after seeding.
  """
  @spec seed_default_categories() :: [PersonalFinanceTracker.Expenses.Category.t()]
  def seed_default_categories do
    existing = MapSet.new(list_categories!(authorize?: false), & &1.name)

    Enum.each(@default_category_names, fn name ->
      normalised = PersonalFinanceTracker.Expenses.Changes.NormaliseName.normalise(name)

      unless MapSet.member?(existing, normalised) do
        create_category!(name, authorize?: false)
      end
    end)

    list_categories!(authorize?: false)
  end
end

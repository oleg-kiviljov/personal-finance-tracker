defmodule PersonalFinanceTracker.Expenses.Expense do
  @moduledoc """
  A single recorded purchase: a date (always today when logged), a category, an amount in euros,
  and an optional note.
  """
  use Ash.Resource,
    otp_app: :personal_finance_tracker,
    domain: PersonalFinanceTracker.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @derive {LiveVue.Encoder, only: [:id, :date, :amount, :note, :category_id]}

  postgres do
    table "expenses"
    repo PersonalFinanceTracker.Repo

    references do
      reference :category, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :log do
      # category_id (the belongs_to FK) is set directly from the form's <select>. No
      # manage_relationship — we attach to an existing Category, not create one. :date is not
      # accepted; the attribute default sets it to today.
      accept [:amount, :note, :category_id]

      validate present(:amount), message: "is required"
      validate present(:category_id), message: "is required"
    end
  end

  policies do
    # Single-user app with no authentication yet. Replace with actor-scoped policies when auth lands.
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    # Business attribute (not a system timestamp). Defaults to today at changeset-build time and is
    # not writable — a new expense always uses today's date (never user-supplied).
    attribute :date, :date do
      allow_nil? false
      public? true
      default &Date.utc_today/0
      writable? false
    end

    # Euros (EUR). :decimal — never :float for money (Iron Law #4). Positive only.
    attribute :amount, :decimal do
      allow_nil? false
      public? true
      constraints min: Decimal.new("0.01")
    end

    attribute :note, :string do
      allow_nil? true
      public? true
      constraints max_length: 500
    end

    timestamps()
  end

  relationships do
    belongs_to :category, PersonalFinanceTracker.Expenses.Category do
      allow_nil? false
      public? true
      attribute_writable? true
    end
  end
end

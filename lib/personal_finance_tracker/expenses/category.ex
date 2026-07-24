defmodule PersonalFinanceTracker.Expenses.Category do
  @moduledoc """
  A label for grouping expenses (e.g. Food, Rent, Electricity).

  Names are normalised to lowercase on write so uniqueness is case-insensitive without needing the
  `citext` Postgres extension. Categories can be created and renamed but **not** deleted — there is
  deliberately no `:destroy` action.
  """
  use Ash.Resource,
    otp_app: :personal_finance_tracker,
    domain: PersonalFinanceTracker.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Crosses into a Vue prop (category <select>) — must derive the LiveVue encoder. Plain :string
  # name (no Ash.CiString), so no special scalar encoder is needed.
  @derive {LiveVue.Encoder, only: [:id, :name]}

  postgres do
    table "expense_categories"
    repo PersonalFinanceTracker.Repo
  end

  actions do
    defaults [:read]

    # No :destroy — categories must not be deleted.

    create :create do
      accept [:name]
      change {PersonalFinanceTracker.Expenses.Changes.NormaliseName, []}
    end

    update :rename do
      accept [:name]
      require_atomic? false
      change {PersonalFinanceTracker.Expenses.Changes.NormaliseName, []}
    end
  end

  policies do
    # Single-user app with no authentication yet. Ash is fail-closed, so an explicit open policy is
    # required. Replace with actor-scoped policies when authentication is added.
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80
    end

    timestamps()
  end

  identities do
    # Enforced by a unique index on the (downcased) stored value — DB-level uniqueness is always
    # correct. eager_check? surfaces an *exact-match* duplicate as a clean form error. Known
    # limitation: because the eager check runs on the raw input before NormaliseName downcases it, a
    # case-variant duplicate ("Food" when "food" exists) slips past the eager check and is caught at
    # the DB index instead. This does not affect the "log expense" feature (categories are seeded,
    # not user-created here); adopt `:ci_string` + citext when the category-management UI (ranked
    # task #5) is built, which makes the eager check case-insensitive too.
    identity :unique_name, [:name], eager_check?: true
  end
end

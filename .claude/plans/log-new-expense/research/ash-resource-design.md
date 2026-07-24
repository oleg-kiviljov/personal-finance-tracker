# Ash Resource Design: Log a New Expense

## Context

This is a greenfield Ash domain — `config :ash, ash_domains: []` and no existing Ash resources.
The domain `PersonalFinanceTracker.Expenses` will own two resources: `Category` and `Expense`.
No `Ash.Scope` is in use (no `Scope` module implementing `Ash.Scope.ToOpts` found) — use bare
`actor:` throughout.

---

## Step 0: Repo.installed_extensions Decision (Do This FIRST)

**Recommendation: stay with plain `:string` + a downcased identity check. Do NOT add `citext`.**

Rationale:

- `citext` requires adding `"citext"` to `Repo.installed_extensions/0` **before** running
  `mix ash.codegen`. The CLAUDE.md warns this order is load-bearing — skipping it generates a
  broken migration that leaves partial tables and is painful to recover from.
- For a first feature, the safest approach is a plain `:string` attribute with a
  `before_action` identity check using `eager_check?: true` that Ash normalises to lowercase
  via a `change set_attribute(:name, expr(string_downcase(name)))` on every write.
- This avoids the extension ordering footgun entirely while still enforcing uniqueness correctly.
- If the team later wants true DB-level case-insensitive collation, add `"citext"` to
  `installed_extensions` in a separate PR after the first feature ships, rerun codegen, and
  migrate. The identity + change pattern migrates cleanly to citext with a single alter-column.

**No change to `Repo.installed_extensions` is needed for this feature.**

---

## Step 1: Generator Commands

Run these in order. The `ash.gen.domain` command must come first so the domain module exists
before resources are registered into it.

```bash
mix ash.gen.domain PersonalFinanceTracker.Expenses --yes
mix ash.gen.resource PersonalFinanceTracker.Expenses.Category --domain PersonalFinanceTracker.Expenses --yes
mix ash.gen.resource PersonalFinanceTracker.Expenses.Expense --domain PersonalFinanceTracker.Expenses --yes
```

---

## Step 2: Resource Module — Category

```elixir
defmodule PersonalFinanceTracker.Expenses.Category do
  use Ash.Resource,
    domain: PersonalFinanceTracker.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @derive {LiveVue.Encoder, only: [:id, :name]}

  postgres do
    table "expense_categories"
    repo PersonalFinanceTracker.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [min_length: 1, max_length: 80]
    timestamps()
  end

  identities do
    # eager_check? validates at changeset time (gives real-time form feedback).
    # The :name_normalized identity references the downcased value written by the change below.
    identity :unique_name, [:name], eager_check?: true
  end

  actions do
    defaults [:read]

    # No :destroy action — categories must not be deleted.

    create :create do
      accept [:name]
      # Normalise to lowercase before persisting so the unique index is case-insensitive.
      change fn changeset, _ctx ->
        Ash.Changeset.update_attribute(changeset, :name, fn
          nil -> nil
          name -> String.downcase(String.trim(name))
        end)
      end
      validate string_length(:name, min: 1, max: 80)
    end

    update :rename do
      accept [:name]
      change fn changeset, _ctx ->
        Ash.Changeset.update_attribute(changeset, :name, fn
          nil -> nil
          name -> String.downcase(String.trim(name))
        end)
      end
      validate string_length(:name, min: 1, max: 80)
    end
  end

  policies do
    # No auth yet on first feature — open read, open write.
    # Replace with actor-scoped policies when authentication is added.
    policy always() do
      authorize_if always()
    end
  end
end
```

**Design notes:**

- No `:destroy` action in `defaults` and none defined manually — satisfies "categories cannot be deleted".
- The anonymous `fn changeset, _ctx ->` change is used because the inline `expr(string_downcase(name))`
  approach requires the `Ash.Expr` DSL and works best in `atomic` changes; the anonymous function
  change is correct for the simple case here. If this pattern recurs across resources, extract it
  to `lib/personal_finance_tracker/expenses/changes/downcase_name.ex`.
- The `identity :unique_name` on the downcased `:name` attribute provides DB-level uniqueness
  (AshPostgres generates a unique index). Combined with the downcase change, "Food" and "food"
  map to the same stored value "food", achieving case-insensitive uniqueness without `citext`.

---

## Step 3: Resource Module — Expense

```elixir
defmodule PersonalFinanceTracker.Expenses.Expense do
  use Ash.Resource,
    domain: PersonalFinanceTracker.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @derive {LiveVue.Encoder, only: [:id, :date, :amount, :note, :category_id]}

  postgres do
    table "expenses"
    repo PersonalFinanceTracker.Repo
  end

  attributes do
    uuid_primary_key :id

    # :date is a business attribute (not a system timestamp). Default to today at create time.
    # Using default: &Date.utc_today/0 means Ash calls the function at changeset build time,
    # so it always reflects today's date. writable?: false makes it immutable after creation.
    attribute :date, :date,
      allow_nil?: false,
      public?: true,
      default: &Date.utc_today/0,
      writable?: false

    # :decimal for money — never :float (Iron Law).
    # Constraints: positive amount only, up to 2 decimal places.
    attribute :amount, :decimal,
      allow_nil?: false,
      public?: true,
      constraints: [min: Decimal.new("0.01")]

    attribute :note, :string, allow_nil?: true, public?: true, constraints: [max_length: 500]

    timestamps()
  end

  relationships do
    belongs_to :category, PersonalFinanceTracker.Expenses.Category,
      allow_nil?: false,
      public?: true,
      attribute_writable?: true
  end

  actions do
    defaults [:read, :destroy]

    create :log do
      # category_id is accepted directly — this is the right pattern for an AshPhoenix.Form
      # select input. The form renders a <select> of category IDs; the user picks one;
      # the changeset receives :category_id. No manage_relationship needed because we are
      # associating with an EXISTING category, not creating/updating one.
      accept [:amount, :note, :category_id]

      # :date is NOT in accept — it must not be user-supplied. The attribute default handles it.
      # writable?: false on the attribute also enforces this at the data layer level.

      validate present(:amount)
      validate present(:category_id)
      validate compare(:amount, greater_than: Decimal.new("0"))
    end
  end

  policies do
    # No auth yet on first feature — open read, open write.
    # Replace with actor-scoped policies when authentication is added.
    policy always() do
      authorize_if always()
    end
  end
end
```

**Design notes for the `log` action:**

- `accept [:amount, :note, :category_id]` — `category_id` is the FK attribute generated by
  `belongs_to` when `attribute_writable?: true`. This pairs naturally with an AshPhoenix.Form
  `<select>` control: the form field is `form[:category_id]`, the value is a UUID string, and
  Ash coerces it to the FK. No `manage_relationship` is needed here because we are attaching to
  an existing Category, not creating or updating one.
- `writable?: false` on `:date` provides defence-in-depth: even if someone constructs a raw
  Ash changeset accepting `:date`, Ash will reject it. The `default:` function fills it automatically.
- `:decimal` with `constraints: [min: Decimal.new("0.01")]` rejects zero and negative amounts
  at the framework level. The `compare` validation in the action is redundant safety — remove if
  noisy, keep if you want a user-facing error message before the constraint fires.
- The `Decimal.new("0.01")` calls are evaluated at compile time; no runtime allocation concern.

---

## Step 4: Domain Module with Code Interface

```elixir
defmodule PersonalFinanceTracker.Expenses do
  use Ash.Domain

  resources do
    resource PersonalFinanceTracker.Expenses.Category do
      define :create_category, action: :create, args: [:name]
      define :rename_category, action: :rename, args: [:id, :name]
      define :list_categories, action: :read
      define :get_category, action: :read, get_by: [:id]
    end

    resource PersonalFinanceTracker.Expenses.Expense do
      define :log_expense, action: :log, args: [:amount, :category_id]
      define :list_expenses, action: :read
      define :get_expense, action: :read, get_by: [:id]
      define :destroy_expense, action: :destroy, args: [:id]
    end
  end
end
```

**Usage examples:**

```elixir
# Log an expense
{:ok, expense} = PersonalFinanceTracker.Expenses.log_expense(
  Decimal.new("12.50"),
  "uuid-of-food-category",
  authorize?: false  # remove once auth is in place
)

# List all categories (for a <select> in the form)
{:ok, categories} = PersonalFinanceTracker.Expenses.list_categories(authorize?: false)

# Rename a category
{:ok, _} = PersonalFinanceTracker.Expenses.rename_category(category, "Groceries", authorize?: false)
```

---

## Step 5: Register the Domain in Application Config

In `config/config.exs`, update the `ash_domains` list:

```elixir
config :personal_finance_tracker,
  ecto_repos: [PersonalFinanceTracker.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [PersonalFinanceTracker.Expenses]
```

---

## Step 6: Seed Default Categories (Idempotent)

File: `priv/repo/seeds.exs`

```elixir
# Seeds are idempotent: use upsert-style logic via the identity.
# Since Ash 3.x create actions raise on identity conflict, we check existence first.
# The domain code interface is used — no direct Repo calls.

alias PersonalFinanceTracker.Expenses

default_categories = ["Food", "Rent", "Electricity", "Transport", "Healthcare", "Entertainment", "Other"]

Enum.each(default_categories, fn name ->
  normalized = name |> String.trim() |> String.downcase()
  case Expenses.list_categories(filter: [name: normalized], authorize?: false) do
    {:ok, []} ->
      {:ok, _} = Expenses.create_category(name, authorize?: false)
      IO.puts("Created category: #{name}")
    {:ok, [_existing | _]} ->
      IO.puts("Category already exists (skipped): #{name}")
    {:error, reason} ->
      IO.warn("Failed to seed category #{name}: #{inspect(reason)}")
  end
end)
```

**Why this approach:** `Expenses.list_categories/1` with a name filter is safe to run repeatedly.
The `:unique_name` identity would cause a conflict error on duplicate inserts, so the existence
check makes it idempotent. An alternative is to use `Ash.Changeset.for_create` with
`upsert?: true, upsert_identity: :unique_name` if you add an `:upsert_or_ignore` action later —
that removes the round-trip read. For a first feature, the read-then-create pattern is clearest.

---

## Step 7: LiveVue.Encoder Coverage

Both resources use `@derive {LiveVue.Encoder, only: [...]}`. The `only:` list is intentionally
narrow to avoid leaking internal fields to Vue props.

```elixir
# Category
@derive {LiveVue.Encoder, only: [:id, :name]}

# Expense
@derive {LiveVue.Encoder, only: [:id, :date, :amount, :note, :category_id]}
```

**`Ash.CiString` is not in play** — by choosing plain `:string` with a downcase change instead
of `:ci_string`, no `Ash.CiString` struct values will appear in the encoded output. The
`Ash.CiString` encoder concern documented in CLAUDE.md is therefore moot for this design.
If `:ci_string` is ever adopted later, the existing `live_vue_helpers.ex` will need a
`defimpl LiveVue.Encoder, for: Ash.CiString` (handle it once there, globally, as CLAUDE.md
describes — not per-resource).

**`:decimal` encoding:** `Decimal.t()` values serialize to strings via `Jason` (the project's
`:json_library`). This is correct for Euro amounts — Vue receives `"12.50"` as a string, which
is suitable for display. When sending back from a form, the string `"12.50"` is accepted by Ash's
`:decimal` type coercion. No additional encoder work needed.

---

## Step 8: Built-ins Used vs Custom

| Slot | Built-in | Custom considered? |
|------|----------|-------------------|
| Date default to today | `default: &Date.utc_today/0` on the attribute | No — exact fit |
| Amount type | `:decimal` | No — Iron Law prohibits `:float`; `:decimal` is correct |
| Amount positive constraint | `constraints: [min: Decimal.new("0.01")]` | No — built-in |
| Name required | `allow_nil?: false` on attribute | No — exact fit |
| Category required | `allow_nil?: false` on `belongs_to` | No — exact fit |
| Category presence check | `validate present(:category_id)` | No — built-in |
| Name length | `validate string_length(:name, min: 1, max: 80)` | No — built-in |
| Case normalisation | Anonymous fn change (downcase + trim) | Consider extracting to `Changes.DowncaseName` if it recurs |
| Uniqueness | `identity :unique_name, [:name], eager_check?: true` | No — exact fit |

---

## Step 9: Custom Modules (None Required)

No custom change/validation/check modules are needed for this feature. The anonymous function
change for downcasing is acceptable for a single resource. If `rename_category` and
`create_category` both grow more normalisation logic, extract to:

```
lib/personal_finance_tracker/expenses/changes/normalise_category_name.ex
```

---

## Step 10: Policies & Relationships Summary

**Policies:** Both resources currently use `policy always() do authorize_if always() end` —
a deliberate placeholder for a feature with no authentication yet. Ash is fail-closed, so an
explicit bypass is required even for "open" resources. When auth arrives, replace with:

```elixir
# Category — admin manages, all authenticated users can read
policies do
  bypass actor_attribute_equals(:role, :admin) do
    authorize_if always()
  end
  policy action_type(:read) do
    authorize_if actor_present()
  end
  policy action_type([:create, :update]) do
    authorize_if actor_attribute_equals(:role, :admin)
  end
end

# Expense — user owns their own expenses
policies do
  bypass actor_attribute_equals(:role, :admin) do
    authorize_if always()
  end
  policy action_type(:read) do
    authorize_if relates_to_actor_via(:user)
  end
  policy action_type([:create, :destroy]) do
    authorize_if actor_present()
  end
end
```

**Relationships:**

- `Expense belongs_to Category` — FK `category_id` on the `expenses` table. `allow_nil?: false`
  enforces referential integrity. AshPostgres generates the FK constraint automatically.
- No `has_many :expenses, Expense` is added to `Category` in this design — it is not needed for
  the "log expense" feature and would require an additional read to load. Add it when a
  "view expenses by category" feature is designed.

---

## Post-Design Commands (run in this exact order)

```bash
# 1. Generate domain and resources (scaffolds the files; do not skip)
mix ash.gen.domain PersonalFinanceTracker.Expenses --yes
mix ash.gen.resource PersonalFinanceTracker.Expenses.Category --domain PersonalFinanceTracker.Expenses --yes
mix ash.gen.resource PersonalFinanceTracker.Expenses.Expense --domain PersonalFinanceTracker.Expenses --yes

# 2. After filling in the generated files with the design above:
mix ash.codegen add_expenses_domain

# 3. Run migrations (never mix ecto.migrate for Ash resources)
mix ash.migrate

# 4. Seed defaults
mix run priv/repo/seeds.exs
```

No `Repo.installed_extensions` change is needed before step 2.

---

## Open Questions

1. **Authentication timing** — the open-policy placeholder must be replaced before the app is
   user-accessible. Is auth (e.g. AshAuthentication) planned for the next feature? If so, the
   `Expense` resource will likely need a `belongs_to :user` relationship and user-scoped policies.
2. **Amount precision** — the design uses `:decimal` with no `scale`/`precision` constraint at
   the DB level (AshPostgres defaults to `numeric` without bounds). If you want to enforce
   exactly 2 decimal places in the DB column, add `constraints: [precision: 10, scale: 2]` to
   the attribute. The Ash-level `min: Decimal.new("0.01")` check does not enforce scale.
3. **Category seed normalisation** — the seeds pass the display-case name (e.g. `"Food"`) to
   `create_category/2`, which the change will downcase to `"food"`. Decide if you prefer to
   display categories in title case in the UI (computed in Vue from `"food"`) or store them in
   title case and only normalise on identity check. The current design stores lowercase, which
   is the simpler invariant.
4. **Expense listing/pagination** — `list_expenses` uses the default `:read` action with no
   pagination. For a personal tracker this is fine initially, but if a user logs many expenses,
   add `pagination do keyset? true end` to the `:read` action and switch the LiveView to
   streams with cursor-based loading.

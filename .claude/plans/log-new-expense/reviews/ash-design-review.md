# Ash Design Review — Expense-Logging Feature

Reviewed files:
- `lib/personal_finance_tracker/expenses/category.ex`
- `lib/personal_finance_tracker/expenses/expense.ex`
- `lib/personal_finance_tracker/expenses/changes/normalise_name.ex`
- `lib/personal_finance_tracker/expenses.ex`

---

## Finding 1 — MEDIUM: Eager identity check runs BEFORE `NormaliseName`, so "Food" vs "food" can slip past it

**File:** `category.ex:64` (identity) + `category.ex:31–32` / `35–37` (change ordering)

### What happens

`eager_check?: true` fires at changeset-build time against the **raw** user input (before any
changes run). `NormaliseName` is a `change` — it transforms the attribute value during the
change pipeline, which runs **after** eager identity checks.

Timeline:
1. User submits "Food".
2. Ash builds the changeset. `eager_check?` queries the DB for `name == "Food"`. If the stored
   value is `"food"` (normalised), the equality check finds **no match** → no conflict raised.
3. `NormaliseName` runs, producing `"food"`.
4. The DB insert fires and hits the unique index on `"food"` → `Ash.Error.Changes.StaleRecord`
   / Postgres `unique_violation` bubbles up as an **internal error**, not a clean form validation
   error.

So the guarantee that `eager_check?` surfaces a user-friendly changeset error before the DB
round-trip is broken. The uniqueness is still enforced at the DB level, but the UX is degraded
and the error may appear as a 500 instead of a field error in the form.

### Severity

MEDIUM — correctness is maintained (the DB index never allows the duplicate through), but the
stated benefit of `eager_check?` (real-time form feedback) is defeated for case-variant inputs.
It will appear as a cryptic DB error rather than a field-level validation message.

### Options to fix (pick one)

**Option A — Use `:ci_string` + `citext` extension (preferred Ash way)**

Switch the `:name` attribute to `:ci_string`. Postgres `citext` does case-insensitive equality
natively, so the unique index enforces the constraint and `eager_check?` queries against the
`citext` column — "Food" and "food" are treated as equal at both layers. The `NormaliseName`
change and the manual downcase in `seed_default_categories/0` become unnecessary.

Requires: add `"citext"` to `PersonalFinanceTracker.Repo.installed_extensions/0` **before**
running `mix ash.codegen` (see CLAUDE.md warning about extension order).

```elixir
# repo.ex
def installed_extensions, do: ["ash-functions", "citext"]

# category.ex
attribute :name, :ci_string do
  allow_nil? false
  public? true
  constraints min_length: 1, max_length: 80
end

# Remove NormaliseName change from both actions.
# Remove manual downcase in seed_default_categories/0.
```

Note: `Ash.CiString` is a struct. If `Category` is passed as a Vue prop, the LiveVue encoder
already derives `only: [:id, :name]`, but the `:name` value will be an `Ash.CiString` struct,
which has no `LiveVue.Encoder` impl and will crash SSR. Per CLAUDE.md, a targeted impl is
needed in `live_vue_helpers.ex`:

```elixir
defimpl LiveVue.Encoder, for: Ash.CiString do
  def encode(%Ash.CiString{} = cs, _opts), do: Ash.CiString.value(cs)
end
```

**Option B — Keep `:string` + `NormaliseName`, add a pre-normalisation eager check**

Move the normalisation into a `before_action` hook or run it as a `prepare` so it fires before
the identity check. This is non-trivial with the current architecture because `change` hooks run
after eager checks. An alternative is to convert `NormaliseName` to a validation that also
mutates the changeset (fragile) or to add a second, manual uniqueness query in a custom
validation that operates on the already-normalised value. This is significantly more complex than
Option A and is not idiomatic.

**Option C — Accept DB-level enforcement only (lowest effort)**

Remove `eager_check?: true` from the identity and document that uniqueness is enforced by the
DB unique index, with a rescue/error-translation layer in the LiveView or form handler. This
trades UX quality for simplicity. Only acceptable if forms are not user-facing.

---

## Finding 2 — LOW: `require_atomic? false` on `rename` is correct but the reason is implicit

**File:** `category.ex:36`

### Observation

`require_atomic? false` is needed because `NormaliseName` implements only `change/3` (not
`atomic/3`). The annotation is correct — without it Ash would raise at runtime if an atomic
data layer is used. No fix required, but the comment in the file does not explain this, which
may confuse future maintainers.

### Suggested comment (documentation only, no code change needed)

```elixir
update :rename do
  accept [:name]
  # NormaliseName only implements change/3, not atomic/3, so Ash cannot
  # execute this action atomically. require_atomic? false suppresses the
  # runtime warning; safe here because there is no concurrent rename concern.
  require_atomic? false
  change {PersonalFinanceTracker.Expenses.Changes.NormaliseName, []}
end
```

---

## Finding 3 — CONFIRMED OK: `:amount` decimal constraints correctly reject nil/0/negative

**File:** `expense.ex:57–61`

```elixir
attribute :amount, :decimal do
  allow_nil? false          # rejects nil
  public? true
  constraints min: Decimal.new("0.01")  # rejects 0 and negative
end
```

- `allow_nil? false` — nil is rejected at the attribute level before constraints run.
- `constraints min: Decimal.new("0.01")` — Ash's built-in decimal constraint rejects 0 and any
  value below 0.01.
- No `:float` anywhere — Iron Law #4 is satisfied.

No issues found.

---

## Finding 4 — CONFIRMED OK: `:date` with `writable?: false` correctly prevents user override

**File:** `expense.ex:49–54`

```elixir
attribute :date, :date do
  allow_nil? false
  public? true
  default &Date.utc_today/0
  writable? false
end
```

`writable?: false` means `Ash.Changeset.change_attribute/3` will refuse to set the field even
if a caller tries. The `:log` action `accept` list (`[:amount, :note, :category_id]`) also
omits `:date`, so there is no route for a caller to supply a custom date through the action
interface. The default `&Date.utc_today/0` is called at changeset-build time, yielding today's
date in UTC. This is correct and intentional.

One minor note: `Date.utc_today/0` uses the server's UTC clock. If the app ever needs
user-local date semantics, this would need to change — but for the current single-user design
this is appropriate.

No issues found.

---

## Finding 5 — CONFIRMED OK: Code interface correctness

**File:** `expenses.ex:10–21`

### `log_expense` args

```elixir
define :log_expense, action: :log, args: [:amount, :category_id]
```

The `:log` action `accept` list is `[:amount, :note, :category_id]`. Listing `:amount` and
`:category_id` in `args` makes them positional parameters of the generated function. `:note` is
optional (nil-able) and is correctly omitted from `args` — callers pass it as a keyword option
(`note: "..."`) or omit it. This is correct Ash code-interface usage.

### `destroy_expense` with no args

```elixir
define :destroy_expense, action: :destroy
```

The generated function signature will be `destroy_expense(expense_or_id, opts \\ [])` — Ash
injects the record or primary key as the first argument for destroy actions automatically. No
`args:` annotation is needed or expected. Correct.

### `get_by`

```elixir
define :get_category, action: :read, get_by: [:id]
define :get_expense,  action: :read, get_by: [:id]
```

`get_by: [:id]` generates a function that raises `Ash.Error.Query.NotFound` when no record
matches and returns `{:ok, record}` on success. Both are correct.

No issues found.

---

## Finding 6 — CONFIRMED OK: `on_delete: :restrict` for the category FK is appropriate

**File:** `expense.ex:19`

```elixir
references do
  reference :category, on_delete: :restrict
end
```

`Category` deliberately has no `:destroy` action (see `category.ex:6–8`). `:restrict` at the
DB level is a correct defence-in-depth measure: even if a destroy were called bypassing Ash
policies (e.g. via `authorize?: false` in a seed or admin escape hatch), the DB would refuse to
orphan expense rows. The combination of no-destroy action + DB restrict is the correct pattern
for a reference-data table that must remain stable.

No issues found.

---

## Finding 7 — LOW: `seed_default_categories/0` duplicates normalisation logic

**File:** `expenses.ex:49`

```elixir
normalised = name |> String.trim() |> String.downcase()
unless MapSet.member?(existing, normalised) do
```

The normalisation logic (`String.trim |> String.downcase`) is duplicated from `NormaliseName`.
If normalisation rules ever change (e.g. collapse internal spaces), the seed function will
silently diverge. This is low risk now but becomes a maintenance footgun.

If Option A (`:ci_string`) from Finding 1 is adopted, this manual normalisation becomes
unnecessary entirely. If staying on `:string` + `NormaliseName`, extract a shared
`NormaliseName.normalise/1` public function and call it from both places.

---

## Priority Summary

| # | Severity | Finding |
|---|----------|---------|
| 1 | MEDIUM   | `eager_check?` fires before `NormaliseName` — case variants bypass form-level uniqueness error, fall through to a DB exception |
| 7 | LOW      | Seed function duplicates normalisation logic; will diverge if rules change |
| 2 | LOW      | `require_atomic? false` is correct but comment omits the reason (not `atomic/3`) |
| 3 | OK       | `:amount` decimal constraints correctly reject nil/zero/negative; no `:float` |
| 4 | OK       | `:date` with `writable?: false` + absent from `accept` correctly prevents user override |
| 5 | OK       | All code interface definitions (`log_expense`, `destroy_expense`, `get_by`) are correct |
| 6 | OK       | `on_delete: :restrict` is appropriate given no `:destroy` action on `Category` |

The only actionable issue requiring a code change before go-live is **Finding 1**. The
recommended fix is Option A (`:ci_string` + `citext` extension), which eliminates the
problem at the type level, removes the custom change module, and aligns with Ash built-in
conventions — at the cost of one extra setup step (registering the Postgres extension before
codegen).

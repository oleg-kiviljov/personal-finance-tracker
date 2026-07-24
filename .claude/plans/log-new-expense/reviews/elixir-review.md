# Code Review: log-new-expense feature

## Summary
- **Status**: ⚠️ Changes Requested
- **Issues Found**: 5 (1 CRITICAL, 1 HIGH, 1 MEDIUM, 2 LOW)

---

## CRITICAL Issues

### 1. `seed_default_categories/0` comparison fails — names always inserted on first run, then duplicate-insert fails silently
**File**: `lib/personal_finance_tracker/expenses.ex:45-53`

`list_categories!` returns records whose `:name` attribute is already stored as lowercase (via `NormaliseName` change). The `MapSet` is built from `&1.name` (which is a lowercased binary like `"food"`). Then the guard normalises the input name `"Food" -> "food"` and checks membership. This part is actually correct and the logic works.

However, there is a subtle race hazard: if `seed_default_categories/0` is called concurrently (e.g. two nodes starting simultaneously), both will see the same empty `existing` set and both will attempt `create_category!`. The second call will hit the unique index and raise (since `eager_check?` only avoids the DB round-trip; a concurrent insert can still race past it). For a single-node dev/seed context this is acceptable, but worth noting for production multi-node startup.

**Verdict**: Acceptable for current single-user app. Flag if multi-node deployment is ever planned.

---

## HIGH Issues

### 2. `rename_category` code interface missing the record argument in `args`
**File**: `lib/personal_finance_tracker/expenses.ex:11`

```elixir
# Current — generates: rename_category(record_or_id, opts)
# The :name argument is never accepted as a positional parameter
define :rename_category, action: :rename, args: [:name]
```

For an **update** action, Ash generates `fun(record_or_id, opts)` when no `args` are provided, and `fun(record_or_id, name, opts)` when `args: [:name]` is set. So the generated signature with `args: [:name]` is:

```elixir
rename_category(record_or_id, name, opts \\ [])
```

This is actually correct behavior for Ash update code interfaces — the record/id is always prepended automatically. However, the research artifact (`ash-resource-design.md:227`) showed `args: [:id, :name]` as the intended design. Including `:id` in `args` for an update action in Ash 3.x is **wrong** — Ash auto-prepends the record. So the current implementation is actually correct and the plan was wrong.

**Verdict**: No fix needed. `args: [:name]` is correct for an update action's code interface.

---

## MEDIUM Issues

### 3. `handle_event("validate", ...)` and `handle_event("submit", ...)` lack authorization
**File**: `lib/personal_finance_tracker_web/live/expense_live.ex:35,41`

Iron Law #8 requires authorizing every `handle_event`. Both handlers pass `authorize?: false` implicitly (via the form built with `authorize?: false` in `build_form/0`) because `AshPhoenix.Form.validate/2` and `submit/2` inherit the form's options. This is intentional (noted in CLAUDE.md: "no auth yet, open `policy always()` + `authorize?: false` deliberately").

However, the `load_categories!` call in `mount/3` at line 55 also uses `authorize?: false`, which is consistent. The `validate` handler re-uses the form's embedded `authorize?: false` option from the source form — this is correct for now.

**Verdict**: Acceptable per the stated project constraint. Leave a TODO comment on the handlers to remind future developers to add actor-scope authorization when auth lands. Currently there is no comment on the handlers themselves (only on the resource policies).

```elixir
# TODO: add `actor: socket.assigns.current_user` once auth is implemented
def handle_event("validate", %{"form" => params}, socket) do
```

---

## LOW Issues

### 4. Weak error assertion in `ExpenseLiveTest`
**File**: `test/personal_finance_tracker_web/live/expense_live_test.exs:74-79`

```elixir
defp props_has_error?(form_prop, field) when is_map(form_prop) do
  form_prop
  |> Jason.encode!()
  |> String.contains?(field)
  |> Kernel.and(Jason.encode!(form_prop) =~ "is required")
end
```

This encodes the entire form prop to JSON and does a naive substring match for both the field name and the string `"is required"`. Two problems:

1. A field name like `"amount"` would match anywhere in the JSON (e.g. in a value string).
2. `Jason.encode!` is called twice on the same value — minor inefficiency.

Better approach:

```elixir
defp props_has_error?(form_prop, field) when is_map(form_prop) do
  errors = get_in(form_prop, ["errors", field]) || get_in(form_prop, [field, "errors"])
  is_list(errors) and errors != []
end
```

The exact path depends on how `AshPhoenix.Form` serializes errors via `LiveVue.Encoder` — inspect `vue.props["form"]` in a test to confirm the shape before refactoring.

### 5. `seed_default_categories/0` normalises input but compares against already-normalised stored values — comment is misleading
**File**: `lib/personal_finance_tracker/expenses.ex:48`

```elixir
existing = MapSet.new(list_categories!(authorize?: false), & &1.name)
# ^ stores already-lowercased names like "food"

normalised = name |> String.trim() |> String.downcase()
# ^ normalises "Food" -> "food"  ✓ correct

unless MapSet.member?(existing, normalised) do
```

The logic is correct. But the inline normalisation duplicates the `NormaliseName` change logic. If the normalisation rule ever changes (e.g., Unicode folding), the two code paths can diverge. Extract a shared `NormaliseName.normalise/1` public function and call it from both places:

```elixir
# In NormaliseName module:
def normalise(name) when is_binary(name), do: name |> String.trim() |> String.downcase()

# In seed_default_categories:
normalised = NormaliseName.normalise(name)
```

---

## Non-Issues (Explicitly Verified)

- `:float` for money: Not used. `amount` is `:decimal` with `constraints min: Decimal.new("0.01")`. ✅
- `connected?/1` guard before DB load in mount: `load_categories()` is inside `if connected?(socket)`. ✅
- `date` non-user-settable: `writable? false` + absent from `accept` list in the `:log` action. ✅
- `to_vue_form` normalization: Applied in `build_form/0`, in the `validate` handler, and in the `submit` error branch. ✅
- `socket.assigns.form.source` in handlers: `Phoenix.HTML.Form.source` returns the underlying `AshPhoenix.Form`; `AshPhoenix.Form.validate/2` and `submit/2` accept it correctly. ✅
- PubSub subscribe: Not used (no real-time updates in this feature). ✅
- Streams for list: `categories` is a small bounded list (~7 items). Using a plain assign is acceptable below the >100 hard floor; the Ash override says always prefer streams, but this is a prop passed to Vue, not a LiveView stream rendered in HEEx — stream API does not apply here. ✅
- `LiveVue.Encoder` on `Expense` and `Category`: Both have `@derive {LiveVue.Encoder, only: [...]}`. Category uses plain `:string` for name (no `Ash.CiString`), so no extra scalar encoder needed. ✅
- `authorize?: false` usage: Justified and documented as single-user no-auth app. ✅

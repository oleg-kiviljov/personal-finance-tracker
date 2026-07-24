# Plan — Log a new expense

**Feature:** Let the user record a purchase by entering an amount, choosing a category, and
optionally adding a note. The expense is saved permanently with today's date.

**Complexity:** MEDIUM (3–6). Full-stack: new Ash domain (2 resources) + LiveVue form.

**Discovery note:** Fresh scaffold — `config :ash, ash_domains: []`, no existing Ash resources.
The `codebase-patterns` and `hex-library-researcher` planning agents were **skipped**: there is no
existing domain to analyze and no new Hex dependency is required (Ash/AshPhoenix/AshPostgres/LiveVue
are already in `mix.exs`). The two design agents that *do* have material to work with were run:
`ash-resource-designer` → `research/ash-resource-design.md`, `livevue-ui-architect` →
`research/livevue-ui-design.md`.

## Architecture summary

- **Domain** `PersonalFinanceTracker.Expenses` with two resources:
  - **Category** — `:string` name (downcased on write, unique identity — NO citext, avoids the
    extension-ordering footgun), no `:destroy` action (categories cannot be deleted), `create` +
    `rename` actions.
  - **Expense** — `:date` (default `&Date.utc_today/0`, `writable?: false`), `:decimal` amount
    (`min: 0.01`, never `:float` — Iron Law #4), optional `:string` note, `belongs_to :category`
    (required, `attribute_writable?: true` so `category_id` is form-settable). `:log` create action
    accepting `[:amount, :note, :category_id]`.
- Both resources `@derive {LiveVue.Encoder, only: [...]}`. No `Ash.CiString` in play (plain string).
- Default categories seeded idempotently via the domain code interface in `seeds.exs`.
- **Frontend:** single `assets/vue/ExpenseForm.vue` (clone of `ExampleForm.vue`) with Nuxt UI
  `UInput` (€ `#leading` slot, `inputmode="decimal"`, money stays a string), `USelect`
  (`value-key="id"` `label-key="name"` → binds `category_id` string), `UTextarea` (note),
  `UButton`. `useLiveForm` validate/submit round-trip. `<UApp>` root.
- **LiveView** `PersonalFinanceTrackerWeb.ExpenseLive` at `/`, backed by `AshPhoenix.Form.for_create`
  normalized via `to_vue_form/1`; categories loaded under `connected?/1` guard. Replaces the example
  page (delete `ExampleLive` + `ExampleForm.vue`, repoint route `/`).

## Tasks

### Backend (Ash)
- [x] T1. Generate domain + resources (`mix ash.gen.domain`, `mix ash.gen.resource` ×2).
- [x] T2. Write `Category` resource (name, downcase change, unique identity, create+rename, no destroy, policies, LiveVue.Encoder derive).
- [x] T3. Write `Expense` resource (date default+writable?:false, decimal amount min 0.01, note, belongs_to category, `:log` action, policies, LiveVue.Encoder derive).
- [x] T4. Write domain `Expenses` with code interfaces (`log_expense`, `list_categories`, `create_category`, `rename_category`, etc.).
- [x] T5. Register domain in `config/config.exs` (`ash_domains: [...]`).
- [x] T6. `mix ash.codegen add_expenses_domain` && `mix ash.migrate`.
- [x] T7. Seed default categories idempotently in `priv/repo/seeds.exs`; run it.

### Frontend (LiveVue)
- [x] T8. Create `assets/vue/ExpenseForm.vue` (amount/category/note fields via useLiveForm + Nuxt UI).
- [x] T9. Create `PersonalFinanceTrackerWeb.ExpenseLive` (mount/render/validate/submit).
- [x] T10. Repoint route `/` → `ExpenseLive`; delete `ExampleLive` + `ExampleForm.vue`.

### Tests & verification
- [x] T11. Domain tests (`test/personal_finance_tracker/expenses_test.exs`) — one per acceptance criterion at the Ash layer.
- [x] T12. LiveView/LiveVue tests (`test/personal_finance_tracker_web/live/expense_live_test.exs`) — form present, validate errors, successful submit, defaults available (via `LiveVue.Test.get_vue`).
- [x] T13. `mix assets.build` (client + SSR) passes.
- [x] T14. `mix precommit` passes (compile-w-a-e, format, credo --strict, sobelow, deps.audit, test).

## Acceptance criteria → test mapping
| Criterion | Test |
|---|---|
| Submit w/ amount+category saves permanently, available between sessions | domain: `log_expense` persists + reload from DB |
| Date auto-set to today | domain: logged expense `.date == Date.utc_today()` |
| Optional note accepted | domain: log with and without note both succeed |
| Amount treated as EUR (decimal) | domain: amount stored as `Decimal`, `:float` never used |
| No amount → rejected, prompt | domain + LiveView: submit blank amount → error on `amount` |
| No category → rejected, prompt | domain + LiveView: submit blank category → error on `category_id` |
| A few default categories available | domain: seeds create N categories; LiveView: `categories` prop non-empty |

---
title: Full-stack Ash + LiveVue "create form" feature pattern
tags: [ash, livevue, ashphoenix-form, phoenix-liveview, nuxt-ui, decimal-money]
problem: How to build a create form as a LiveVue island backed by an Ash resource in this app.
date: 2026-07-24
feature: log-new-expense
---

# Ash + LiveVue create-form feature (reference pattern)

The first real feature in this scaffold. Captures the seams that recur in every full-stack
Ash + LiveVue form, so the next one is a copy-edit.

## Backend (Ash)

- **Money is `:decimal`**, never `:float` (Iron Law #4). `constraints: [min: Decimal.new("0.01")]`
  rejects nil/0/negative at the framework level. `Decimal.t()` JSON-encodes to a string — keep it a
  string end-to-end on the client too (see below).
- **Auto "today" date that users can't set:** `attribute :date, :date, default: &Date.utc_today/0,
  writable?: false` and leave `:date` out of the action's `accept`. Two layers: not accepted +
  not writable. Test it with `Ash.Resource.Info.action(Res, :action).accept`.
- **belongs_to as a form select:** `belongs_to :category, ..., attribute_writable?: true` exposes
  `category_id`; put it in `accept`. The `<select>` emits the id string straight into `category_id`.
  No `manage_relationship` (that's for creating/replacing related rows, not pointing at an existing one).
- **"cannot be deleted":** omit `:destroy` from `defaults` and define none — Ash is fail-closed.
  Pair with `references do reference :category, on_delete: :restrict end` on the FK side.
- **Case-insensitive unique name without citext:** a `change` that trims+downcases + a plain
  `identity [:name]`. DB uniqueness is correct. Caveat: `eager_check?: true` runs on RAW input
  before the change, so case-variant dupes only fail at the DB index, not as a clean form error.
  Switch to `:ci_string` + `"citext"` in `Repo.installed_extensions` (BEFORE codegen — ordering
  footgun, see CLAUDE.md) when you need the eager check to be case-insensitive too.
- **No auth yet:** `policy always() do authorize_if always() end` + `authorize?: false` on calls.
  Ash is fail-closed, so the explicit open policy is required. Comment every `authorize?: false`.

## Frontend (LiveVue)

- **LiveView shape** mirrors the (now-deleted) `ExampleLive`: `connected?/1`-guarded DB load in
  mount, `<Layouts.app flash={@flash}>` wrapping `<.vue v-component="ExpenseForm" .../>`,
  `validate`/`submit` handlers backed by `AshPhoenix.Form.validate/2` + `submit/2`.
- **Always `to_vue_form/1`** at every point a form becomes a prop (mount, validate, submit-error).
  A create form has `data: nil` → LiveVue SSR `BadMapError` without it. (The permanent
  `LiveVue.Encoder` impl for `AshPhoenix.Form` in `live_vue_helpers.ex` is belt-and-suspenders.)
- **Categories prop:** map resources to plain `%{id, name}` maps in the LiveView (smallest prop, no
  field leak) OR `@derive {LiveVue.Encoder, only: [...]}` on the resource. Did both here.
- **Nuxt UI:** `UInput` with a `#leading` `€` slot + `inputmode="decimal"` (NOT `UInputNumber` —
  it binds a JS number and risks float rounding on money). `USelect` with `value-key="id"`
  `label-key="name"` so `model-value` is the category id string. All wrapped in one `<UApp>`.
- **useLiveForm:** `field.value.value` is a writable computed; `@update:model-value="field.value.value = String($event ?? '')"`
  keeps every field a string.

## Testing (the non-obvious part)

- Set `config :live_vue, enable_props_diff: false` in `config/test.exs` (already set) so
  `LiveVue.Test.get_vue/2` sees full props.
- **Serialized form-prop error shape:** `vue.props["form"]["errors"]` is a **field-keyed map**,
  `%{"amount" => ["is required"], ...}` after the JSON round-trip. Assert on the specific field's
  list — do NOT substring-search the whole JSON blob (a different field's "is required" gives a
  false positive):
  ```elixir
  defp field_error?(form_prop, field, msg),
    do: (get_in(form_prop, ["errors", field]) || []) |> Enum.any?(&(&1 =~ msg))
  ```
- Drive events with `render_hook(view, "validate"|"submit", %{"form" => params})`. Don't
  `assert render_hook(...)` (any HTML string is truthy — asserts nothing); assert the real outcome
  (`has_element?(view, "#flash-info", "...")`, DB persistence, or the errors prop).
- Flash element id is `flash-#{kind}` (e.g. `#flash-info`).

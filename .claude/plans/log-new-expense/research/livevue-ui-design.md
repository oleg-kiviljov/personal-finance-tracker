# Frontend design — "Log a new expense" (LiveVue UI Architect)

First feature. Direct clone of the existing reference pattern:
`assets/vue/ExampleForm.vue` + `lib/personal_finance_tracker_web/live/example_live.ex`
(both marked DELETE-ME). This feature replaces them. Route `/` should point at the new
`ExpenseLive` and the example files should be deleted.

Authority applied: **LiveVue guardrails > nuxt-ui skill > generic Vue**. Server owns state;
the Vue island is a reactive view of `AshPhoenix.Form` + a categories list, both LiveView assigns.

---

## 1. Component breakdown

| File | Location | Role |
|------|----------|------|
| `ExpenseForm.vue` | `assets/vue/ExpenseForm.vue` | Single leaf/page component. Renders the whole form (amount, category, note) inside `<UApp>`. Direct analog of `ExampleForm.vue`. |

One component is sufficient — no nested/reusable sub-components. No persistent layout / `v-inject`
needed (single-surface form), so the standard `<.vue>` island applies. Not client-only, so **no**
`v-ssr={false}` — it must SSR (create-form normalization gotcha below is why `to_vue_form/1` matters).

---

## 2. Nuxt UI components — verified via nuxt-ui MCP + docs

All wrapped in a single `<UApp>` root (provider context for the select's popover/overlay).

### Amount — `UInput` with a `#leading` € adornment (NOT `UInputNumber`)

- **Verified `UInput` props:** `type`, `placeholder`, `modelValue`/`v-model`, `name`, `leadingIcon`.
- **Verified `#leading` slot** exists (docs example uses it for a `https://` prefix). Use it for `€`.
- **Decision — `UInput` over `UInputNumber`:** `UInputNumber` binds a **JS `number`** via
  `v-model`, which (a) fights the string-in/string-out contract of `useLiveForm` fields, and
  (b) risks binary-float rounding on a money value before it ever reaches Ash's `:decimal`.
  Money stays a **string** end-to-end; Ash casts the decimal server-side. Use
  `type="text"` + `inputmode="decimal"` so mobile shows a numeric keypad without number coercion.
  (Iron Law: no `:float` for money — keeping it a string upholds this on the client too.)

```vue
<UFormField
  label="Amount"
  required
  :error="amountField.isTouched.value ? amountField.errorMessage.value : undefined"
>
  <UInput
    :model-value="amountField.value.value"
    :name="amountField.inputAttrs.value.name"
    inputmode="decimal"
    placeholder="0.00"
    class="w-full"
    @update:model-value="amountField.value.value = String($event ?? '')"
  >
    <template #leading>
      <span class="text-muted">€</span>
    </template>
  </UInput>
</UFormField>
```

### Category — `USelect` (NOT `USelectMenu`)

- **Decision — `USelect` over `USelectMenu`:** a few seeded default categories, no search / no
  create-on-the-fly needed → the simple native-style `USelect` is correct. `USelectMenu` is the
  searchable combobox; reserve it for large/async lists.
- **Verified props:** `items` (array of objects with `label`/`value` or custom keys), `value-key`
  (defaults `"value"`), `label-key` (defaults `"label"`), `modelValue`/`v-model`, `placeholder`,
  `name`.
- **Binding a category id string through a useLiveForm field:** categories arrive as
  `{ id, name }` maps. Set `label-key="name"` and `value-key="id"` so the model-value is the
  **`id` string** — exactly what the form field holds and what Ash expects for `category_id`.

```vue
<UFormField
  label="Category"
  required
  :error="categoryField.isTouched.value ? categoryField.errorMessage.value : undefined"
>
  <USelect
    :model-value="categoryField.value.value"
    :name="categoryField.inputAttrs.value.name"
    :items="props.categories"
    label-key="name"
    value-key="id"
    placeholder="Select a category"
    class="w-full"
    @update:model-value="categoryField.value.value = String($event ?? '')"
  />
</UFormField>
```

> Note: with `value-key="id"`, `update:model-value` emits the scalar id (string), not the object.
> `String($event ?? '')` keeps the field value a string and empty-safe.

### Note — `UTextarea` (unchanged from ExampleForm)

```vue
<UFormField label="Note" hint="Optional">
  <UTextarea
    :model-value="noteField.value.value"
    :name="noteField.inputAttrs.value.name"
    :rows="3"
    autoresize
    placeholder="What was this for?"
    class="w-full"
    @update:model-value="noteField.value.value = String($event ?? '')"
  />
</UFormField>
```

### Submit — `UButton` (unchanged from ExampleForm)

`type="submit"`, `color="primary"`, `block`, `:loading="submitting"`, `:disabled="submitting"`,
`icon="i-lucide-receipt"` (verify icon name at build; any `i-lucide-*` is fine).

### UFormField — verified

`label`, `required` (renders the `*`), `error` (**`string | boolean | undefined`** — pass the
string message; renders below the control with `text-error`), `hint`, `help`, `description`, `name`.
Pattern: only surface the error once touched — `field.isTouched.value ? field.errorMessage.value : undefined`.

Use semantic color tokens only (`text-muted`, `text-default`, `text-error`) — no raw Tailwind palette.

---

## 3. LiveVue integration contract

### Props (LiveView → Vue)

```ts
type ExpenseFormFields = { amount: string; category_id: string; note: string }

const props = defineProps<{
  form: Form<ExpenseFormFields>            // AshPhoenix.Form normalized via to_vue_form/1
  categories: { id: string; name: string }[]
}>()
```

- `form` — the `AshPhoenix.Form` for `Expense :create`, passed through `to_vue_form/1`.
- `categories` — a **separate prop**, a plain list of `%{id, name}` maps. The Ash `Category`
  resource must `@derive {LiveVue.Encoder, only: [:id, :name]}` (or the LiveView maps it to plain
  maps before passing — either satisfies the encoder). Field names must match the `value-key`/
  `label-key` used above (`id`, `name`).

### useLiveForm wiring (client → server events)

Identical shape to `ExampleForm.vue`:

```ts
const form = useLiveForm(() => props.form, {
  changeEvent: "validate",
  submitEvent: "submit",
  debounceInMiliseconds: 300,
})

const amountField   = form.field("amount")
const categoryField = form.field("category_id")
const noteField     = form.field("note")

const submitting = ref(false)
async function onSubmit() {
  submitting.value = true
  try { await form.submit() } finally { submitting.value = false }
}
```

- `field.value.value` is a writable computed: reading renders current state; assigning fires the
  debounced `"validate"`. All three fields carry **strings**.
- `<form @submit.prevent="onSubmit">` triggers `"submit"`.
- **No** Nuxt UI `UForm` / Zod client validation — validation is server-side Ash (LiveVue guardrail).
- **No** vue-router, **no** `onMounted` fetch, **no** Pinia. Categories come from props.

### Server → client

Nothing custom needed. Flash confirmation on success is handled by the `<Layouts.app flash={@flash}>`
shell (LiveView flash, per the guardrail "toasts → LiveView flash"). No `useLiveEvent` required.

### `<UApp>` placement

`<UApp>` is the single root of `ExpenseForm.vue`'s `<template>` (as in `ExampleForm.vue`), so the
`USelect` popover has provider context. `colorMode: false` / `router: false` are already set on the
Nuxt UI Vite plugin — nothing to change.

---

## 4. LiveView shape — `PersonalFinanceTrackerWeb.ExpenseLive`

Mirrors `example_live.ex` but backed by `AshPhoenix.Form`. Route `/` → `ExpenseLive`.

```elixir
def mount(_params, _session, socket) do
  # Iron Law #1: no DB in disconnected mount. Load categories + build form only when connected.
  socket =
    if connected?(socket) do
      categories =
        PersonalFinanceTracker.Expenses.list_categories!()   # code interface; returns %Category{}
        |> Enum.map(&%{id: &1.id, name: &1.name})             # plain maps → encoder-safe prop

      socket
      |> assign(:categories, categories)
      |> assign(:form, build_form())
    else
      socket
      |> assign(:categories, [])
      |> assign(:form, build_form())   # form has no DB dependency; safe in both branches
    end

  {:ok, socket}
end

def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash}>
    <.vue v-component="ExpenseForm" form={@form} categories={@categories} />
  </Layouts.app>
  """
end

def handle_event("validate", %{"form" => params}, socket) do
  form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
  {:noreply, assign(socket, :form, to_vue_form(form))}
end

def handle_event("submit", %{"form" => params}, socket) do
  # AUTHORIZE here (Iron Law #8) — pass actor/tenant into submit as the backend contract defines.
  case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
    {:ok, _expense} ->
      {:noreply,
       socket
       |> assign(:form, build_form())            # reset to a fresh blank create form
       |> put_flash(:info, "Expense logged.")}

    {:error, form} ->
      {:noreply, assign(socket, :form, to_vue_form(form))}   # re-wrap — surfaces inline errors
  end
end

defp build_form do
  to_vue_form(
    AshPhoenix.Form.for_create(PersonalFinanceTracker.Expenses.Expense, :create,
      domain: PersonalFinanceTracker.Expenses,
      as: "form"
    )
  )
end
```

Notes for `/phx:work`:
- `to_vue_form/1` already exists in `lib/personal_finance_tracker_web/live_vue_helpers.ex` and is
  imported into LiveViews via the web `:live_view` block (as `example_live.ex` uses it unqualified).
- The **date is not a form field** — the Ash `:create` action sets `date` to today server-side
  (e.g. a `change set_attribute(:date, &Date.utc_today/0)` or default). No client input for it.
- `category_id` is the belongs_to foreign key; the create action must accept it as an argument/
  attribute so the `USelect`'s id string maps straight through.
- Amount arrives as a string; Ash casts to `:decimal` (Iron Law #4 — never `:float` for money).

---

## 5. LiveVue guardrail gotchas (call these out in the work tasks)

1. **Create-form `data: nil` crashes SSR.** `AshPhoenix.Form.for_create/3` yields `data: nil`;
   the LiveVue form encoder `BadMapError`s during SSR. **Always** pass the form through
   `to_vue_form/1` — at `mount`, in `validate`, and in the `submit` error branch. Never assign a
   raw `AshPhoenix.Form` to `:form`. (The helper module already handles the encoder + normalization;
   just never bypass it.)
2. **`LiveVue.Encoder` on the categories prop.** Passing `%Category{}` structs directly requires
   `@derive {LiveVue.Encoder, only: [:id, :name]}` on the resource, or map to plain `%{id, name}`
   maps in the LiveView (recommended above — smallest prop, no accidental field leakage). Do one
   of the two, not neither → otherwise `Protocol.UndefinedError`.
3. **`Ash.CiString` in a prop.** If `Category.name` is a `:ci_string` attribute, its value is an
   `%Ash.CiString{}` with no encoder → `Protocol.UndefinedError` at render/SSR. Two options:
   the permanent `Ash.CiString` encoder impl lives in `live_vue_helpers.ex` (per CLAUDE.md), OR the
   explicit `Enum.map(&%{id: &1.id, name: to_string(&1.name)})` in mount sidesteps it. If mapping
   to maps, `to_string/1` the name to be safe.
4. **Select value must be a string id.** `value-key="id"` + `String($event ?? '')` guarantees the
   field holds a plain string that matches Ash's `category_id`. Do not bind the whole option object.
5. **Empty-state race.** In the disconnected branch `categories` is `[]`, so the `USelect` renders
   empty on first paint, then fills on connect — expected and fine; the form still SSRs because the
   form assign has no DB dependency and is built in both branches.

---

## Tools `/phx:work` will need

- **nuxt-ui MCP** — `get-component-metadata` for `USelect`/`UInput`/`UFormField` if any prop is
  in doubt during implementation (verified here: items/value-key/label-key/model-value/name;
  UInput `#leading` slot + type/inputmode; UFormField error `string|boolean|undefined`).
- **`nuxt-ui` skill** — component selection + form recipe references.
- **`vue-best-practices` skill** — `<script setup lang="ts">` authoring (load before editing the `.vue`).
- **LiveVue guardrails** (`deps/live_vue/usage-rules.md`) — form/encoder/nav rules.
- Verify build: `mix assets.build` (client + SSR) in addition to `mix precommit`.

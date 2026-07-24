defmodule PersonalFinanceTrackerWeb.LiveVueHelpers do
  @moduledoc """
  Small helpers for driving Vue islands from LiveView. Imported into every LiveView/component via
  `PersonalFinanceTrackerWeb.html_helpers/0`.

  This module is **permanent infrastructure** — keep it even after you delete the example page.
  """

  @doc """
  Normalize a `Phoenix.HTML.Form` so it can be handed to a Vue island as a prop.

  **Why this exists:** an `AshPhoenix.Form` for a *create* action has `data: nil`
  (`AshPhoenix.Form.for_create(...) |> to_form()` → `%Phoenix.HTML.Form{data: nil}`). LiveVue's
  `Phoenix.HTML.Form` encoder does `Map.merge(hidden, form.data)` during SSR, which raises
  `(BadMapError) Map.merge(_, nil)` — and this hits prod SSR (QuickBEAM), not just tests. Coercing
  `data` to `%{}` fixes it. For non-nil `data` (update forms, plain `to_form(params)`) it's a no-op,
  so it is always safe to call.

  Use it at **every** point you assign a form that will become a Vue prop:

      # mount / rebuild
      assign(socket, :form, to_vue_form(AshPhoenix.Form.for_create(Expense, :create, as: "form")))

      # handle_event("validate", ...) — validate/2 returns a bare %AshPhoenix.Form{}, re-wrap it
      form = AshPhoenix.Form.validate(socket.assigns.form.source, params)
      assign(socket, :form, to_vue_form(form))

  Pair with `config :live_vue, enable_props_diff: false` in `config/test.exs` so
  `LiveVue.Test.get_vue/2` sees full props in tests (already set in this template).

  > With the `LiveVue.Encoder` implementation for `AshPhoenix.Form` below, calling `to_vue_form/1`
  > is belt-and-suspenders: a raw `AshPhoenix.Form` now encodes safely even if it reaches a Vue prop
  > un-normalized. Still prefer the store-normalized pattern above — it keeps the render boundary
  > obvious — but you no longer get a `Protocol.UndefinedError` if you slip.
  """
  @spec to_vue_form(Phoenix.HTML.Form.t() | AshPhoenix.Form.t()) :: Phoenix.HTML.Form.t()
  def to_vue_form(%Phoenix.HTML.Form{} = form), do: %{form | data: form.data || %{}}
  def to_vue_form(form), do: to_vue_form(to_form(form))

  # `to_form/1` is imported from Phoenix.Component into html_helpers; reference it explicitly here
  # since this module doesn't `use` the web macros.
  defp to_form(form), do: Phoenix.Component.to_form(form)
end

# A raw %AshPhoenix.Form{} has NO LiveVue.Encoder, so if one ever reaches the encoder LiveVue raises
# `Protocol.UndefinedError`. This bites in a non-obvious place: LiveVue's props-diff
# (`enable_props_diff`, ON by default in dev/prod, but OFF in this template's config/test.exs) encodes
# the form ASSIGN to compute a minimal patch. So a LiveView that stores the raw form in an assign and
# normalizes only at render (`form={to_vue_form(@form)}`) passes every test, then crashes at preview
# on the first `validate` — the diff encodes the un-normalized assign, bypassing to_vue_form entirely.
#
# Implement the encoder by delegating to the form's Phoenix.HTML.Form conversion (the `data: nil`
# coercion guards the same create-form BadMapError to_vue_form/1 guards). Now a raw ash form encodes
# identically to its normalized form, so BOTH the store-raw and store-normalized patterns are safe —
# the whole class of "a raw AshPhoenix.Form reached the encoder" crash is gone, regardless of how the
# LiveView is written. Purely additive: this only ever fires on a value that previously always crashed.
defimpl LiveVue.Encoder, for: AshPhoenix.Form do
  def encode(form, opts) do
    form
    |> Phoenix.Component.to_form()
    |> then(&%{&1 | data: &1.data || %{}})
    |> LiveVue.Encoder.encode(opts)
  end
end

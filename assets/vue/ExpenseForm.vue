<script setup lang="ts">
// Log a new expense. LiveView owns the state (an AshPhoenix.Form for Expense :log); this island is
// a reactive view. Fields bind to `useLiveForm` — money stays a *string* end to end (Ash casts the
// :decimal server-side; never a JS number, to avoid float rounding on currency).
import { ref } from "vue"
import { useLiveForm, type Form } from "live_vue"

type ExpenseFormFields = { amount: string; category_id: string; note: string }

const props = defineProps<{
  form: Form<ExpenseFormFields>
  categories: { id: string; name: string }[]
}>()

const form = useLiveForm(() => props.form, {
  changeEvent: "validate",
  submitEvent: "submit",
  debounceInMiliseconds: 300,
})

const amountField = form.field("amount")
const categoryField = form.field("category_id")
const noteField = form.field("note")

const submitting = ref(false)
async function onSubmit() {
  submitting.value = true
  try {
    await form.submit()
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <UApp>
    <div class="mx-auto max-w-lg space-y-8 px-4 py-16">
      <header class="space-y-1">
        <h1 class="text-xl font-semibold text-default">Log an expense</h1>
        <p class="text-sm text-muted">Record a purchase — it's saved with today's date.</p>
      </header>

      <form class="space-y-4" @submit.prevent="onSubmit">
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

        <UButton
          type="submit"
          label="Log expense"
          icon="i-lucide-receipt"
          color="primary"
          block
          :loading="submitting"
          :disabled="submitting"
        />
      </form>
    </div>
  </UApp>
</template>

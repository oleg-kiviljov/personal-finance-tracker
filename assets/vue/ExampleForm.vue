<script setup lang="ts">
// ⚠️  EXAMPLE COMPONENT — DELETE ME (together with lib/.../live/example_live.ex).
//
// Reference for the ONE pattern you'll repeat in every feature: binding Nuxt UI inputs to a
// `useLiveForm` form that LiveView owns. Copy the field wiring; delete the file when you build
// your real page.
//
// The key idea: Nuxt UI inputs speak v-model (`model-value` in, `update:model-value` out).
// `field.value` from useLiveForm is a *writable computed* — reading it renders the current value,
// assigning it (`field.value.value = ...`) updates form state and fires the debounced "validate".
import { ref } from "vue"
import { useLiveForm, type Form } from "live_vue"

type ExampleForm = { name: string; message: string }

const props = defineProps<{
  form: Form<ExampleForm>
  status: string
}>()

const form = useLiveForm(() => props.form, {
  changeEvent: "validate",
  submitEvent: "submit",
  debounceInMiliseconds: 300,
})

const nameField = form.field("name")
const messageField = form.field("message")

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
        <h1 class="text-xl font-semibold text-default">LiveVue + Nuxt UI starter</h1>
        <p class="text-sm text-muted">
          Delete <code>ExampleForm.vue</code> and <code>example_live.ex</code>, then build your
          feature. Status: {{ status }}
        </p>
      </header>

      <form class="space-y-4" @submit.prevent="onSubmit">
        <UFormField
          label="Name"
          required
          :error="nameField.isTouched.value ? nameField.errorMessage.value : undefined"
        >
          <UInput
            :model-value="nameField.value.value"
            :name="nameField.inputAttrs.value.name"
            placeholder="Ada Lovelace"
            class="w-full"
            @update:model-value="nameField.value.value = String($event ?? '')"
          />
        </UFormField>

        <UFormField label="Message" hint="Optional">
          <UTextarea
            :model-value="messageField.value.value"
            :name="messageField.inputAttrs.value.name"
            :rows="3"
            autoresize
            placeholder="Say something…"
            class="w-full"
            @update:model-value="messageField.value.value = String($event ?? '')"
          />
        </UFormField>

        <UButton
          type="submit"
          label="Submit"
          icon="i-lucide-send"
          color="primary"
          block
          :loading="submitting"
          :disabled="submitting"
        />
      </form>
    </div>
  </UApp>
</template>

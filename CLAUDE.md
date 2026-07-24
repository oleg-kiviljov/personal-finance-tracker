# Elixir / Phoenix / Ash / LiveVue / Nuxt UI — Conventions

This is a web application written using the Phoenix web framework, with Ash on the backend and
LiveVue + Vue + Nuxt UI on the frontend. The sections below are the durable stack conventions for
this app. They govern all code in this repo.

## SKILL EXECUTION ENFORCEMENT

These rules govern ALL `/phx:*` command execution — including headless builds (`claude --print`).
Violations invalidate the session output.

1. **Skills are PROCEDURES, not suggestions.** Every numbered step MUST execute. Do not skip, reorder, or "optimize away" steps.
2. **Agent spawning is MANDATORY when a skill says "spawn" or "always run".** Zero agents spawned when the skill requires them = skill failure.
3. **Every skill MUST produce its required artifact file** (`.claude/plans/{slug}/`, `.claude/plans/{slug}/reviews/`, etc.). Chat-only output without the artifact = skill failure.
4. **"Already implemented" is a FINDING, not an exit.** If investigation reveals the feature exists, document that finding in the required artifact. Do not bail out of the workflow.
5. **Read the SKILL.md BEFORE executing.** Parse the workflow steps and execute them sequentially. Do not improvise a different workflow.
6. **No unauthorized judgment calls.** If the skill does not define an early-exit condition, there is no early exit.
7. **Agent output MUST be saved to `.claude/plans/{slug}/research/`.** If an agent completes, write its findings to `.claude/plans/{slug}/research/{agent-name}-report.md` before synthesizing into the plan.

## IRON LAWS — STOP if violated

If code would violate ANY of these, STOP, show the problematic code, show the correct pattern, and
ask permission to apply the fix.

**LiveView**:
1. NO DB queries in disconnected mount → use `assign_async` / `start_async` (or `connected?/1` guard)
2. Use streams for lists >100 items
3. Check `connected?/1` before PubSub subscribe

**Ecto**:
4. NO `:float` for money → `:decimal` or `:integer` (cents)
5. Pin values with `^` in queries — never interpolate
6. Separate queries for `has_many`, JOIN for `belongs_to`

**Security**:
7. NO `String.to_atom(user_input)` — atom exhaustion attack
8. AUTHORIZE every `handle_event` — mount auth is not enough
9. NO `raw/1` with untrusted content — XSS vulnerability

**OTP**:
10. NO process without runtime reason — processes are for concurrency/state/isolation

## Ash Framework

This project uses Ash Framework. Before writing ANY Ash code:

1. Load the `ash-framework` skill — it owns all Ash patterns and Iron Laws
2. Research: `mix usage_rules.search_docs "<topic>" -p ash -p ash_phoenix -p ash_postgres -p ash_oban`
3. Module lookup: `mix usage_rules.docs Ash.Resource`
4. Generators: `mix ash.gen.resource`, `mix ash.codegen`, `mix ash.gen.domain`

Ash is a complement to Phoenix/Ecto — LiveView, security, and OTP Iron Laws still apply. For data
access, prefer Ash actions via domain code interfaces over direct `Repo` calls.

After changing any Ash resource, run `mix ash.codegen <name> && mix ash.migrate` (migrations are
generated from snapshots — never hand-write them; never edit `priv/resource_snapshots/`).

**Postgres extension types require declaring the extension FIRST.** If a resource uses a type
backed by a Postgres extension — most commonly `:ci_string` (needs `citext`) — you MUST add the
extension to the repo's `installed_extensions/0` (`lib/personal_finance_tracker/repo.ex`, e.g.
`["ash-functions", "citext"]`) **before** running `mix ash.codegen`. Skipping this generates a
table migration that references the missing type; it fails mid-run without a transaction, leaves
partial tables, and recovery is painful because `mix ecto.drop`/`ecto.reset` are blocked by a
safety hook. Order matters: the extension migration must be generated so it runs before the table
migration. If you already ran a broken migration, don't bundle the fix `rm` in the same `&&` chain
as a blocked `ecto.drop` — the block aborts the whole compound command and the `rm` never runs.

## Feature build contract — full-stack (governs `/phx:plan`, `/phx:work`, `/phx:full`)

The stack is **Phoenix + Ash** (backend) and **LiveView + LiveVue + Vue + Nuxt UI** (frontend).
A feature with any user-facing surface is **full-stack** — it is not planned or done until its UI
and tooling are accounted for.

### Planning (`/phx:plan`, or the plan phase of `/phx:full`)

Write the plan to `.claude/plans/{slug}/plan.md`. When the feature has any client surface, the plan
MUST include a **Frontend** section alongside the backend/Ash tasks:

1. **Component breakdown** — the `.vue` components to build (PascalCase), where each lives
   (`assets/vue/` or colocated under `lib/personal_finance_tracker_web/`), and its role
   (layout / page / leaf).
2. **Nuxt UI components** — the exact `U*` components to use, **verified via the `nuxt-ui` MCP**
   (`search-components` / `get-component-metadata`). Never guess component names or props.
3. **LiveVue integration** — props/events contract, `LiveVue.Encoder` for any struct/Ash-resource
   props, navigation (`useLiveNavigation`/`<Link>`), forms (`useLiveForm` + server changeset /
   `AshPhoenix.Form`), `UApp` placement, and `v-inject` if it composes into a persistent layout.
4. **Tools the work phase will use** — the `nuxt-ui` MCP, the `vue-best-practices` / `nuxt-ui`
   skills, and the LiveVue guardrails.

**MUST spawn the `livevue-ui-architect` agent** (defined in `.claude/agents/`) during planning for
any UI surface — it designs the Vue/LiveVue layer and selects Nuxt UI components via the MCP (the
frontend analog of the plugin's `phoenix-patterns-analyst`). A plan that omits the UI for a UI
feature is incomplete.

### Implementation (`/phx:work`, or the work phase of `/phx:full`)

- Implements **both** backend and frontend tasks from the plan.
- Before touching any `.vue` file: load `vue-best-practices` (and `nuxt-ui` for Nuxt UI
  components); consult the `nuxt-ui` MCP for component props.
- Apply the **LiveVue guardrails** and the **Nuxt UI skill overrides** (forms → `useLiveForm`,
  overlays → declarative `<UModal>`, nav → LiveView, `colorMode: false`, toasts → LiveView flash).
- Verify the frontend like the backend: `mix assets.build` must pass (client + SSR) in addition
  to `mix precommit`.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues. It is the
  final gate (compile with warnings-as-errors, format, credo, sobelow, deps.audit, test).
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid**
  `:httpoison`, `:tesla`, and `:httpc`. Req is the preferred HTTP client for Phoenix apps.

### Ash overrides — where Ash and the generic Phoenix/Ecto rules disagree, Ash wins

- **Forms**: build forms with `AshPhoenix.Form` (`AshPhoenix.Form.for_create/for_update`, or
  `form_to_*` code interfaces), never from raw `Ecto.Changeset`. The changeset-driven form rules in
  the Phoenix LiveView section apply **only** to escape-hatch plain Ecto schemas.
- **Streams**: "always use streams for collections" is the rule; the Iron Law's ">100 items" is the
  hard floor, not a license to use plain assigns for smaller lists.
- **`authorize?: false`** is an admin/seed escape hatch, not a convenience — every use must be justified.

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all
  inner content.
- The `PersonalFinanceTrackerWeb.Layouts` module is aliased in `personal_finance_tracker_web.ex`, so you
  can use it without aliasing it again.
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden**
  from calling `<.flash_group>` outside of the `layouts.ex` module.
- **Icons:** heroicons has been **removed** from this project. Icons come from Nuxt UI (Iconify,
  e.g. `<UIcon name="i-lucide-…" />`) inside Vue components. The HEEx `<.icon>` helper in
  `core_components.ex` is **dormant** (no plugin backs `hero-*` classes) — do **not** add new
  `<.icon name="hero-…">` in HEEx.
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when
  building plain-HEEx forms. (On Vue surfaces, inputs come from `useLiveForm()` — see LiveVue guardrails.)

### Frontend build stack — Phoenix + LiveVue + Vite

This app does **not** use the default `phx.new` esbuild + tailwind-CLI pipeline. Assets are built by
**Vite** (via `phoenix_vite`), and Vue components render inside LiveView via **LiveVue**.

- **Toolchain:** Vite + `@vitejs/plugin-vue` + `@tailwindcss/vite` + `@nuxt/ui/vite` +
  `live_vue/vitePlugin`, configured in `assets/vite.config.mjs`. There is **no** `:esbuild`/`:tailwind`
  Hex dep and **no** `tailwind.config.js`. Node/npm is a hard dev dependency.
- **Layout:** Vue SFCs live in `assets/vue/` (PascalCase `.vue`), may be colocated under
  `lib/personal_finance_tracker_web/`; JS entry `assets/vue/index.ts`, app entry `assets/js/app.js`,
  CSS entry `assets/css/app.css`, SSR entry `assets/js/server.js`.
- **Dev = two servers:** `mix phx.server` runs Phoenix on **:4000** plus a Vite dev server on
  **:5173**. `root.html.heex` emits asset tags via `<PhoenixVite.Components.assets>` reading the Vite
  manifest (`priv/static/.vite/manifest.json`).
- **Prod:** `mix assets.deploy` → `assets.build` runs **two** Vite builds (client bundle + SSR
  `js/server.js`). Vue is server-rendered via **`LiveVue.SSR.QuickBEAM`**. There is **no** `phx.digest` step.
- **Commands:** `mix assets.setup` (npm install), `mix assets.build`, `mix assets.deploy`.
- **`~H` is overridden:** `lib/personal_finance_tracker_web.ex` swaps `Phoenix.Component.sigil_H` for
  `LiveVue.SharedPropsView.sigil_H` (injects shared props into `<.vue>` tags) — every
  LiveView/component uses the LiveVue sigil, not the stock one.

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive interfaces.
- Tailwind v4 **no longer needs a tailwind.config.js**. Here Tailwind runs as a **Vite plugin**
  (`@tailwindcss/vite`), not the standalone CLI. Maintain the `@source`/`@import` syntax already in
  `assets/css/app.css` — note it includes `@source "../vue"` and pulls Nuxt UI via `@import "@nuxt/ui"`.
- **Never** use `@apply` when writing raw css.
- **Always** manually write your own Tailwind-based components for a unique, world-class design.
- **Vendor deps are npm packages** imported into `assets/js/app.js` / `assets/css/app.css`; Vite
  bundles and serves them. Do **not** reference an external script `src` or link `href` in the
  layouts, and **never write inline `<script>` tags within templates** (use colocated hooks).

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design.
- Implement **subtle micro-interactions** (button hover effects, smooth transitions).
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look.
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions.

### Vue work — load the `vue-best-practices` skill (MANDATORY)

The `vue-best-practices` skill auto-activates only by keyword/prefix. Treat its trigger as living
here:

- **Before writing or editing ANY `.vue` file or Vue component** (under `assets/vue/`, or colocated
  `*.vue` in `lib/personal_finance_tracker_web/`), **load the `vue-best-practices` skill**, then apply
  the *LiveVue guardrails* below (LiveVue wins on conflict).
- Component authoring (`<script setup lang="ts">`, reactivity, composables) → follow the skill;
  state / data / navigation → follow LiveVue guardrails.

### LiveVue guardrails — these OVERRIDE the `vue-best-practices` skill on conflict

This app renders Vue components inside Phoenix LiveView via LiveVue. The generic Vue skill assumes a
client-owned SPA; LiveVue does not. **When they disagree, LiveVue wins.** Full rules:
`deps/live_vue/usage-rules.md`.

- **LiveView holds the source of truth.** Vue components are reactive *views* of server state.
  Component-internal client state (open/closed, hover, draft input) is fine.
- **NO Pinia/Vuex for app state.** App state lives in LiveView assigns, pushed down as props.
- **NO data fetching in Vue** (`onMounted` + `fetch`/`$fetch`/`useFetch`). Pass everything as props
  from the LiveView; send changes back via events.
- **Navigation:** use LiveVue's `<Link navigate=… patch=… />` / `useLiveNavigation()`, **not Vue Router**.
- **Events:** client→server `useLiveVue().pushEvent()` / `$live.pushEvent()`; server→client
  `useLiveEvent()`. Handle on the server in `handle_event/3`.
- **Forms:** `useLiveForm()` backed by a server-side `to_form` (or `AshPhoenix.Form`).
- **Structs as props MUST implement `LiveVue.Encoder`** (`@derive {LiveVue.Encoder, only: […]}`), or
  you get `Protocol.UndefinedError`. Applies to **Ash resources** passed as props. A **create**
  `AshPhoenix.Form` has `data: nil`, which crashes the LiveVue form encoder during SSR — normalize
  with a `to_vue_form/1` helper (`%{to_form(form) | data: form.data || %{}}`), and re-wrap the
  results of `AshPhoenix.Form.validate/2` and `submit/2` with `to_form` every time.
- **Ash scalar wrapper types crossing into a prop also need an `Encoder` impl.** Deriving the
  encoder on the resource is not enough when a *field's value* is itself a struct — notably
  `Ash.CiString` (from a `:ci_string` attribute), which has no `LiveVue.Encoder` and raises
  `Protocol.UndefinedError` at render/SSR. Add a targeted impl once in the permanent
  `live_vue_helpers.ex` (encode `Ash.CiString` as its underlying string), not per-feature.
- **Components:** PascalCase `.vue` files in `assets/vue/`; `<script setup lang="ts">`.
- **HEEx-component mandates don't apply inside Vue.** On a Vue-rendered surface, inputs come from
  `useLiveForm()`'s `inputAttrs`, icons are Nuxt UI `<UIcon name="i-lucide-…" />`. Those HEEx
  mandates still hold for plain-HEEx LiveViews. The `<Layouts.app>` shell still wraps the hosting
  LiveView regardless.
- **Testing:** integration via `LiveVue.Test.get_vue/2` + `render_hook` in ExUnit — not
  Vitest/Playwright. For LiveVue tests set `config :live_vue, enable_props_diff: false` so
  `LiveVue.Test.get_vue/2` sees full props.
- **Persistent layout = `v-inject` into a sticky layout LiveView** (one shared `UApp`). Two
  non-obvious requirements: (1) every `v-inject` island needs a **stable, unique `id`** — sharing
  one blanks the slot on navigation; (2) `assets/vue/index.ts` setup MUST render
  `h(component, props, { ...slots })` (spread) — the LiveVue default `h(component, props, slots)`
  never reads `.default`, so the injected slot **freezes on the SSR-composed first page** after live
  navigation.

### Nuxt UI skill overrides

**Before using any Nuxt UI `U*` component** (new usage, or changing props/slots of an existing
one), **load the `nuxt-ui` skill** (same MANDATORY status as `vue-best-practices`) — its
references (`.claude/skills/nuxt-ui/references/`) are the offline source of truth for component
selection, conventions, and form/overlay recipes. Use the `nuxt-ui` MCP (`search-components` /
`get-component-metadata`) for exact prop/slot verification when it's connected; the skill's
`references/components.md` is the fallback when it isn't — never guess. On conflict with the
LiveVue guardrails, LiveVue wins:

- **Forms** → `useLiveForm()` + server changeset / `AshPhoenix.Form` (not Nuxt UI client validation).
- **Overlays** (modal/slideover/popover) → declarative `<UModal>` etc. with `v-model:open`.
- **Navigation** → LiveView (`useLiveNavigation` / `<Link>`), not Vue Router.
- **`colorMode: false`** and **`router: false`** are set on the Nuxt UI Vite plugin (LiveView owns
  navigation; colorMode uses SSR-unsafe browser APIs).
- **Toasts** → prefer LiveView flash over client-only toasts for server-driven messages.
- Wrap Nuxt UI islands in `<UApp>` so overlays/tooltips have their provider context.

### Authority (on conflict)

LiveVue guardrails **>** `nuxt-ui` / `vue-best-practices` skills **>** generic Vue advice; and
Ash **>** generic Phoenix/Ecto. **Server owns state** — Vue components are reactive views.

<!-- usage-rules-start -->
<!-- phoenix:elixir-start -->
## phoenix:elixir usage
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages


<!-- phoenix:elixir-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>

<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items
  along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- Edit mode --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide an unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors, 1) colocated js hooks for "inline" scripts defined inside HEEx,
and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

#### Inline colocated js hooks

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView.
Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`)
when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

#### External phx-hook

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the
LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events between client and server

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle.
**Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset

<!-- phoenix:liveview-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it

<!-- phoenix:phoenix-end -->
<!-- phoenix:ecto-start -->
## phoenix:ecto usage
[phoenix:ecto usage rules](deps/phoenix/usage-rules/ecto.md)
<!-- phoenix:ecto-end -->
<!-- live_vue-start -->
## live_vue usage
_E2E reactivity for Vue and LiveView_

[live_vue usage rules](deps/live_vue/usage-rules.md)
<!-- live_vue-end -->
<!-- ash_oban-start -->
## ash_oban usage
_The extension for integrating Ash resources with Oban._

[ash_oban usage rules](deps/ash_oban/usage-rules.md)
<!-- ash_oban-end -->
<!-- ash_oban:best_practices-start -->
## ash_oban:best_practices usage
[ash_oban:best_practices usage rules](deps/ash_oban/usage-rules/best_practices.md)
<!-- ash_oban:best_practices-end -->
<!-- ash_oban:debugging_and_error_handling-start -->
## ash_oban:debugging_and_error_handling usage
[ash_oban:debugging_and_error_handling usage rules](deps/ash_oban/usage-rules/debugging_and_error_handling.md)
<!-- ash_oban:debugging_and_error_handling-end -->
<!-- ash_oban:defining_triggers-start -->
## ash_oban:defining_triggers usage
[ash_oban:defining_triggers usage rules](deps/ash_oban/usage-rules/defining_triggers.md)
<!-- ash_oban:defining_triggers-end -->
<!-- ash_oban:multi_tenancy_support-start -->
## ash_oban:multi_tenancy_support usage
[ash_oban:multi_tenancy_support usage rules](deps/ash_oban/usage-rules/multi_tenancy_support.md)
<!-- ash_oban:multi_tenancy_support-end -->
<!-- ash_oban:scheduled_actions-start -->
## ash_oban:scheduled_actions usage
[ash_oban:scheduled_actions usage rules](deps/ash_oban/usage-rules/scheduled_actions.md)
<!-- ash_oban:scheduled_actions-end -->
<!-- ash_oban:setting_up_ash_oban-start -->
## ash_oban:setting_up_ash_oban usage
[ash_oban:setting_up_ash_oban usage rules](deps/ash_oban/usage-rules/setting_up_ash_oban.md)
<!-- ash_oban:setting_up_ash_oban-end -->
<!-- ash_oban:triggering_jobs_programmatically-start -->
## ash_oban:triggering_jobs_programmatically usage
[ash_oban:triggering_jobs_programmatically usage rules](deps/ash_oban/usage-rules/triggering_jobs_programmatically.md)
<!-- ash_oban:triggering_jobs_programmatically-end -->
<!-- ash_oban:working_with_actors-start -->
## ash_oban:working_with_actors usage
[ash_oban:working_with_actors usage rules](deps/ash_oban/usage-rules/working_with_actors.md)
<!-- ash_oban:working_with_actors-end -->
<!-- ash_phoenix-start -->
## ash_phoenix usage
_Utilities for integrating Ash and Phoenix_

[ash_phoenix usage rules](deps/ash_phoenix/usage-rules.md)
<!-- ash_phoenix-end -->
<!-- ash_phoenix:best_practices-start -->
## ash_phoenix:best_practices usage
[ash_phoenix:best_practices usage rules](deps/ash_phoenix/usage-rules/best_practices.md)
<!-- ash_phoenix:best_practices-end -->
<!-- ash_phoenix:debugging_form_submissions-start -->
## ash_phoenix:debugging_form_submissions usage
[ash_phoenix:debugging_form_submissions usage rules](deps/ash_phoenix/usage-rules/debugging_form_submissions.md)
<!-- ash_phoenix:debugging_form_submissions-end -->
<!-- ash_phoenix:error_handling-start -->
## ash_phoenix:error_handling usage
[ash_phoenix:error_handling usage rules](deps/ash_phoenix/usage-rules/error_handling.md)
<!-- ash_phoenix:error_handling-end -->
<!-- ash_phoenix:form_integration-start -->
## ash_phoenix:form_integration usage
[ash_phoenix:form_integration usage rules](deps/ash_phoenix/usage-rules/form_integration.md)
<!-- ash_phoenix:form_integration-end -->
<!-- ash_phoenix:nested_forms-start -->
## ash_phoenix:nested_forms usage
[ash_phoenix:nested_forms usage rules](deps/ash_phoenix/usage-rules/nested_forms.md)
<!-- ash_phoenix:nested_forms-end -->
<!-- ash_phoenix:union_forms-start -->
## ash_phoenix:union_forms usage
[ash_phoenix:union_forms usage rules](deps/ash_phoenix/usage-rules/union_forms.md)
<!-- ash_phoenix:union_forms-end -->
<!-- ash_postgres-start -->
## ash_postgres usage
_The PostgreSQL data layer for Ash Framework_

[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)
<!-- ash_postgres-end -->
<!-- ash_postgres:advanced_features-start -->
## ash_postgres:advanced_features usage
[ash_postgres:advanced_features usage rules](deps/ash_postgres/usage-rules/advanced_features.md)
<!-- ash_postgres:advanced_features-end -->
<!-- ash_postgres:best_practices-start -->
## ash_postgres:best_practices usage
[ash_postgres:best_practices usage rules](deps/ash_postgres/usage-rules/best_practices.md)
<!-- ash_postgres:best_practices-end -->
<!-- ash_postgres:check_constraints-start -->
## ash_postgres:check_constraints usage
[ash_postgres:check_constraints usage rules](deps/ash_postgres/usage-rules/check_constraints.md)
<!-- ash_postgres:check_constraints-end -->
<!-- ash_postgres:configuration-start -->
## ash_postgres:configuration usage
[ash_postgres:configuration usage rules](deps/ash_postgres/usage-rules/configuration.md)
<!-- ash_postgres:configuration-end -->
<!-- ash_postgres:custom_indexes-start -->
## ash_postgres:custom_indexes usage
[ash_postgres:custom_indexes usage rules](deps/ash_postgres/usage-rules/custom_indexes.md)
<!-- ash_postgres:custom_indexes-end -->
<!-- ash_postgres:custom_sql_statements-start -->
## ash_postgres:custom_sql_statements usage
[ash_postgres:custom_sql_statements usage rules](deps/ash_postgres/usage-rules/custom_sql_statements.md)
<!-- ash_postgres:custom_sql_statements-end -->
<!-- ash_postgres:foreign_keys-start -->
## ash_postgres:foreign_keys usage
[ash_postgres:foreign_keys usage rules](deps/ash_postgres/usage-rules/foreign_keys.md)
<!-- ash_postgres:foreign_keys-end -->
<!-- ash_postgres:migrations-start -->
## ash_postgres:migrations usage
[ash_postgres:migrations usage rules](deps/ash_postgres/usage-rules/migrations.md)
<!-- ash_postgres:migrations-end -->
<!-- ash_postgres:multitenancy-start -->
## ash_postgres:multitenancy usage
[ash_postgres:multitenancy usage rules](deps/ash_postgres/usage-rules/multitenancy.md)
<!-- ash_postgres:multitenancy-end -->
<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- ash:authorization-start -->
## ash:authorization usage
[ash:authorization usage rules](deps/ash/usage-rules/authorization.md)
<!-- ash:authorization-end -->
<!-- ash:code_interfaces-start -->
## ash:code_interfaces usage
[ash:code_interfaces usage rules](deps/ash/usage-rules/code_interfaces.md)
<!-- ash:code_interfaces-end -->
<!-- ash:code_structure-start -->
## ash:code_structure usage
[ash:code_structure usage rules](deps/ash/usage-rules/code_structure.md)
<!-- ash:code_structure-end -->
<!-- ash:migrations-start -->
## ash:migrations usage
[ash:migrations usage rules](deps/ash/usage-rules/migrations.md)
<!-- ash:migrations-end -->
<!-- ash:actions-start -->
## ash:actions usage
[ash:actions usage rules](deps/ash/usage-rules/actions.md)
<!-- ash:actions-end -->
<!-- ash:relationships-start -->
## ash:relationships usage
[ash:relationships usage rules](deps/ash/usage-rules/relationships.md)
<!-- ash:relationships-end -->
<!-- ash:calculations-start -->
## ash:calculations usage
[ash:calculations usage rules](deps/ash/usage-rules/calculations.md)
<!-- ash:calculations-end -->
<!-- ash:aggregates-start -->
## ash:aggregates usage
[ash:aggregates usage rules](deps/ash/usage-rules/aggregates.md)
<!-- ash:aggregates-end -->
<!-- ash:testing-start -->
## ash:testing usage
[ash:testing usage rules](deps/ash/usage-rules/testing.md)
<!-- ash:testing-end -->
<!-- ash:data_layers-start -->
## ash:data_layers usage
[ash:data_layers usage rules](deps/ash/usage-rules/data_layers.md)
<!-- ash:data_layers-end -->
<!-- ash:exist_expressions-start -->
## ash:exist_expressions usage
[ash:exist_expressions usage rules](deps/ash/usage-rules/exist_expressions.md)
<!-- ash:exist_expressions-end -->
<!-- ash:query_filter-start -->
## ash:query_filter usage
[ash:query_filter usage rules](deps/ash/usage-rules/query_filter.md)
<!-- ash:query_filter-end -->
<!-- ash:querying_data-start -->
## ash:querying_data usage
[ash:querying_data usage rules](deps/ash/usage-rules/querying_data.md)
<!-- ash:querying_data-end -->
<!-- ash:generating_code-start -->
## ash:generating_code usage
[ash:generating_code usage rules](deps/ash/usage-rules/generating_code.md)
<!-- ash:generating_code-end -->
<!-- usage-rules-end -->

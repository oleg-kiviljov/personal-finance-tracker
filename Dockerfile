# syntax=docker/dockerfile:1
#
# One multi-stage Dockerfile, one shared `base` stage = the single source of truth for the
# toolchain (Elixir/OTP/Node/PG). `.tool-versions` derives from the ARGs below. Three targets:
#
#   base     — Elixir/OTP/Node/git/PostgreSQL + system deps (no app, no claude). Shared by all.
#   builder  — base + pinned `claude` + the harness plugins + the `invoker-build` entrypoint.
#              This is the dev/agent container: Invoker `msb exec`s `invoker-build` in a VM booted
#              from it; a human can boot the same image to develop. (Moved from invoker's images/.)
#   preview  — base + the compiled app, booted for human review (in-container Postgres → migrate →
#              seed → serve on :4000). No claude.
#   release  — base + a slim `mix release` prod artifact.
#
# Build a specific target (match the msb host arch — Apple Silicon = arm64):
#   podman build --target builder --platform linux/arm64 -t app:builder .
#   podman build --target preview --platform linux/arm64 -t app:preview .
#   podman build --target release -t app:release .

# Elixir 1.20 (OTP 28) — matches the dev/host toolchain and the invoker build sandbox, so the app
# compiles the same everywhere. (1.18.4 + OTP 27 broke on Elixir-1.19.3+ syntax like the `~r"…"E`
# :export sigil this template uses in config/dev.exs.)
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=28.5.0.2
# Date-stamped Debian slim tag. hexpm/elixir PRUNES old date stamps — `bookworm-20250630-slim` no
# longer resolves (manifest unknown). Use a currently-published stamp and digest-pin it below so
# future pruning can't break the build. Verify a stamp still exists with:
#   curl -s 'https://hub.docker.com/v2/repositories/hexpm/elixir/tags/?page_size=100&name=1.20.2-erlang-28.5.0.2-debian-bookworm'
ARG DEBIAN_VERSION=bookworm-20260623-slim
ARG NODE_MAJOR=26

# ─────────────────────────────────────────────────────────────────────────────────────────────
# base — shared toolchain (single source of truth)
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Digest-pinned for reproducibility: the `:tag` stays human-readable (driven by the ARGs above) but
# the `@sha256` is authoritative, so a future re-tag/prune of the date stamp can't change the layer.
# This is a MULTI-ARCH (manifest list) digest so the same pin resolves on arm64 (local msb) and
# amd64 (CI). Re-capture after any ELIXIR/OTP/DEBIAN bump:
#   podman manifest inspect hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}@sha256:4293e0742c2dc7cabe7f9fc163d0bd91571d5cb8ccf5dd27ebfe20e334388312 AS base

# OCI label — `image.source` is what makes GHCR link the package to the repo (visibility inheritance
# + a "Repository" link). Override SOURCE_URL via --build-arg if the repo moves.
ARG SOURCE_URL=https://github.com/oleg-kiviljov/personal_finance_tracker
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.title="personal-finance-tracker-base" \
      org.opencontainers.image.description="Elixir/OTP + Node + PostgreSQL toolchain base (no app, no claude)."

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MIX_HOME=/root/.mix \
    HEX_HOME=/root/.hex \
    DEBIAN_FRONTEND=noninteractive

ARG NODE_MAJOR

# System deps: git, curl, gnupg (verify the apt keys), build tools (native deps), Postgres
# (the in-image dev/preview loop needs a DB), inotify (live reload), locales.
#
# Postgres comes from the PGDG apt repo (same keyring pattern as nodesource), NOT Debian bookworm's
# suite: bookworm ships PG 15, but the generated app declares `min_pg_version` 18.x and AshPostgres
# implements `upsert?` via `MERGE ... RETURNING`, which PG <17 rejects — a sandbox on bookworm's PG
# silently breaks a canonical Ash pattern. PG_MAJOR tracks the scaffold's declared min version.
# (contrib modules ship inside postgresql-NN since PG 14 — no separate contrib package needed.)
#
# Node comes from the nodesource apt repo via its GPG keyring (NOT `curl … | bash -`, which runs an
# unverified remote script as root): fetch the signing key to /usr/share/keyrings, write a
# `signed-by` apt source pinned to NODE_MAJOR, install nodejs through apt — auditable + integrity-checked.
#
# Cache mount: /var/cache/apt persists downloaded .debs across rebuilds. Those .debs live in the
# mount, never in the layer, so `apt-get clean` is dropped; the apt index IS in the layer and removed.
#
# KNOWN LIMITATION — system deps are NOT self-healing across a feature build. A feature can freely add
# pure-Elixir/hex deps (the agent's `mix deps.get` + the preview image's `app-build` stage both
# re-resolve mix.lock, and C-only NIFs compile against `build-essential` above). But a dep needing a
# NEW system package or toolchain (libvips, imagemagick, ffmpeg, a Rust NIF, a shelled-out binary)
# must be added to THIS list by hand: the build agent runs inside an already-built `builder` image, so
# editing this Dockerfile mid-build does NOT re-provision its live container — `mix precommit` fails on
# the missing lib and the feature blocks. Add the package here, then rebuild the builder (merge to main
# → CI rebuilds `:builder`; locally `mix invoker.image`). Features may not bootstrap their own OS-level
# deps. If this bites often, fatten this list proactively rather than per-feature.
ARG PG_MAJOR=18
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git build-essential inotify-tools locales jq \
 && install -d -m 0755 /usr/share/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends nodejs "postgresql-${PG_MAJOR}" \
 && rm -rf /var/lib/apt/lists/*

# Hex + rebar baked so the build/preview loops don't fetch them at runtime.
RUN mix local.hex --force && mix local.rebar --force

# Shared helper: start a local Postgres (used by both the builder and preview entrypoints).
COPY bin/start-postgres.sh /usr/local/bin/start-postgres
RUN chmod +x /usr/local/bin/start-postgres

WORKDIR /workspace

# ─────────────────────────────────────────────────────────────────────────────────────────────
# builder — base + claude + harness plugins + the agent build entrypoint
# ─────────────────────────────────────────────────────────────────────────────────────────────
FROM base AS builder

LABEL org.opencontainers.image.title="personal-finance-tracker-builder" \
      org.opencontainers.image.description="Dev/agent container: base + claude CLI + the elixir-phoenix & vue harness plugins + the invoker-build entrypoint."

# Claude Code CLI (the `claude` binary the build entrypoint drives). Pinned: unpinned `latest` means
# a CLI flag / output-format / permission-mode change silently breaks entrypoint-build.sh
# (`--output-format stream-json`, `--permission-mode acceptEdits`) with no Dockerfile-level signal.
# Bump deliberately; keep in lockstep with the contract Invoker asserts (see invoker images/README).
# The npm cache mount persists the download across rebuilds.
#
# HARD CEILING — do NOT bump to >= 2.1.216 without first renaming the build's slash command.
# The build is driven by the `/phx:full` slash command (see entrypoint-build.sh: the prompt LITERALLY
# starts with "/phx:full ..."). That command comes from the elixir-phoenix plugin's skills, whose
# frontmatter declares `name: phx:full`. Claude Code <= 2.1.215 honored that name, registering the
# skill as `/phx:full`. 2.1.216 changed it (framed as a bug fix): plugin skills are now namespaced by
# PLUGIN name, so the only valid invocation became `/elixir-phoenix:full` and `/phx:full` returns
# "Unknown command" — which, as the first token of the headless prompt, silently fails every build.
# To move past 2.1.215 you MUST, in the same change: rename `/phx:full` -> `/elixir-phoenix:full` in
# entrypoint-build.sh, and update the stale `/phx:*` references in CLAUDE.md and
# .claude/agents/livevue-ui-architect.md. There is also no DISABLE_AUTOUPDATER guard here, so if the
# sandbox ever gets network egress at run time a self-update could jump this pin on its own.
ARG CLAUDE_CODE_VERSION=2.1.183
RUN --mount=type=cache,target=/root/.npm \
    npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Harness plugins baked as user-level installs (/root/.claude) so they load headless via the
# generated repo's committed `.claude/settings.json` enabledPlugins — NO `--plugin-dir` at runtime.
# The `claude plugin list` greps assert the plugins actually installed — if this RUN fails, that IS
# the signal (a silent miss = builds run without the conventions / Iron Laws).
ARG ELIXIR_PHOENIX_MARKETPLACE="oliver-kriska/claude-elixir-phoenix"
ARG VUE_SKILLS_MARKETPLACE="vuejs-ai/skills"
RUN claude plugin marketplace add "${ELIXIR_PHOENIX_MARKETPLACE}" \
 && claude plugin marketplace add "${VUE_SKILLS_MARKETPLACE}" \
 && claude plugin install elixir-phoenix@oliver-kriska \
 && claude plugin install vue-best-practices@vue-skills \
 && claude plugin install create-adaptable-composable@vue-skills \
 && claude plugin install vue-debug-guides@vue-skills \
 && claude plugin list | grep -qi "elixir-phoenix" \
 && claude plugin list | grep -qi "vue-best-practices"

# Build entrypoint on PATH as `invoker-build` (the worker's command). Scaffolding (template fetch +
# rename + repo creation + initial push) happens on the Invoker HOST, not here — so the image stays
# lean (toolchain + claude) and clones the already-scaffolded repo at runtime.
COPY bin/entrypoint-build.sh /usr/local/bin/invoker-build
RUN chmod +x /usr/local/bin/invoker-build

# QA-polish scan entrypoint on PATH as `invoker-polish` (Invoker.Polish.ScanWorker's command). Same
# builder image (it needs the full toolchain + claude + plugins the finders use); runs the read-only
# finder set on the `iteration/<id>` branch and emits the invoker_findings/invoker_polish_report lines.
COPY bin/entrypoint-polish.sh /usr/local/bin/invoker-polish
RUN chmod +x /usr/local/bin/invoker-polish

# ─────────────────────────────────────────────────────────────────────────────────────────────
# app-build — compile the app + assets once (shared by preview and release)
# ─────────────────────────────────────────────────────────────────────────────────────────────
FROM base AS app-build
ENV MIX_ENV=prod
WORKDIR /app

# Layer order tuned so a feature-build push (app code changed, lockfiles untouched) pays only
# `assets.deploy + mix compile` — not a full dep + npm recompile. Each COPY introduces the NARROWEST
# input its following RUN needs, so an app-code change (the final `COPY . .`) can't bust the
# dep/asset-install layers above it. The two build-time hazards (documented on the last RUN) touch
# ONLY that RUN: local spikes confirmed `mix deps.compile` and `mix assets.setup` do NOT evaluate
# config/runtime.exs (so they need no DATABASE_URL placeholder and no seeded manifest).

# 1) Elixir deps — cached on the lockfiles alone.
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# 2) Compile deps — some read `Application.compile_env`, so give them the compile-time config first
# (config.exs/prod.exs, NOT runtime.exs); layer stays keyed on lockfiles + config, app-code-independent.
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# 3) npm deps via phoenix_vite — cached on the JS lockfiles alone.
COPY package.json package-lock.json ./
RUN mix assets.setup

# 4) App code — the layer that actually changes per feature build. Everything below reruns each push;
# the expensive dep/npm installs above are cache hits.
COPY . .

# Build assets (client + SSR bundles, prod) + compile. TWO build-time-only hazards in prod
# `config/runtime.exs`, which THESE tasks evaluate (unlike deps.compile / assets.setup above):
#   1. it RAISES on missing DATABASE_URL/SECRET_KEY_BASE → pass throwaway placeholders inline on this
#      RUN only (never persisted as image ENV; the real values come from the runtime entrypoint);
#   2. `PhoenixVite.cache_static_manifest_latest/1` READS the Vite manifest — but the manifest is
#      *built by* `mix assets.deploy` (a mix task), so the first task to run would crash on the not-
#      yet-built manifest (chicken-and-egg). Seed a placeholder `{}` manifest so that first eval
#      succeeds; `assets.deploy` overwrites it with the real one, and the server re-evaluates
#      runtime.exs at boot against the real manifest.
# Then drop node_modules (~400 MB) in the SAME layer: assets are compiled into priv/static and SSR
# runs in-BEAM (LiveVue QuickBEAM), so neither `preview` nor `release` needs node_modules at runtime
# (release-build copies only the release dir). Same RUN = the fat dir never ships in a layer.
RUN mkdir -p priv/static/.vite && printf '{}' > priv/static/.vite/manifest.json
RUN DATABASE_URL="ecto://postgres:postgres@127.0.0.1:5432/build_placeholder" \
    SECRET_KEY_BASE="build0only0placeholder0secret0key0base0not0used0at0runtime0xxxxxxxxxxxx" \
    sh -c 'mix assets.deploy && mix compile' \
 && rm -rf node_modules assets/node_modules

# ─────────────────────────────────────────────────────────────────────────────────────────────
# preview — base + compiled app, booted as a running server for human review
# ─────────────────────────────────────────────────────────────────────────────────────────────
FROM app-build AS preview

LABEL org.opencontainers.image.title="personal-finance-tracker-preview" \
      org.opencontainers.image.description="The app booted for on-demand human review (in-container Postgres → migrate → seed → serve on :4000). No claude."

COPY bin/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

ENV PORT=4000
EXPOSE 4000
ENTRYPOINT ["entrypoint"]

# ─────────────────────────────────────────────────────────────────────────────────────────────
# release — slim production artifact (`mix release`)
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Compile the release in the fat app-build stage, then copy ONLY the self-contained release into a
# slim runtime (no Elixir/Node/build tools — the release bundles ERTS). Postgres is NOT in the
# runtime: production points DATABASE_URL at a managed DB.
FROM app-build AS release-build
RUN mix release --overwrite

FROM debian:${DEBIAN_VERSION} AS release
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libstdc++6 libncurses6 locales openssl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=release-build /app/_build/prod/rel/personal_finance_tracker ./
ENV PHX_SERVER=true PORT=4000
EXPOSE 4000
ENTRYPOINT ["/app/bin/personal_finance_tracker"]
CMD ["start"]

#!/usr/bin/env bash
# Preview/run entrypoint: start Postgres → migrate → seed (if present) → serve.
# The app is already compiled with assets built at image-build time (MIX_ENV=prod).
#
# Env (all optional — sensible local-preview defaults):
#   PORT            (default 4000)
#   SECRET_KEY_BASE (generated if absent)
#   DATABASE_URL    (defaults to the in-container Postgres below)
#   PHX_HOST        (default localhost)
set -euo pipefail

PORT="${PORT:-4000}"
export MIX_ENV=prod

# prod runtime.exs RAISES without these. The preview talks to the in-container Postgres that
# start-postgres boots (postgres/postgres @ 127.0.0.1:5432); point DATABASE_URL at it by default so
# the preview is self-contained. A real deployment overrides DATABASE_URL with a managed DB.
export DATABASE_URL="${DATABASE_URL:-ecto://postgres:postgres@127.0.0.1:5432/preview}"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(mix phx.gen.secret)}"
export PHX_HOST="${PHX_HOST:-localhost}"

log() { printf '\n=== %s ===\n' "$1"; }

log "starting postgres"
start-postgres

log "setting up database"
mix ash.setup || mix ecto.setup

# Seed the database. `mix ash.setup`/`ecto.setup` above only migrate — `ash.setup` succeeds so the
# `|| ecto.setup` fallback (which would run seeds.exs) never fires. Run the standard seed file
# explicitly, since that's where Ecto/Phoenix convention (and generated apps) put seed data.
if [ -f priv/repo/seeds.exs ]; then
  log "seeding database"
  mix run priv/repo/seeds.exs || true
fi

# Optional preview/demo overlay on top of the base seeds.
if [ -f priv/repo/demo_seeds.exs ]; then
  log "seeding demo data"
  mix run priv/repo/demo_seeds.exs || true
fi

log "starting server on :${PORT}"
exec env PORT="$PORT" PHX_SERVER=true mix phx.server

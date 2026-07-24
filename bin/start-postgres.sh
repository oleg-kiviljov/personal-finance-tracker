#!/usr/bin/env bash
# Start a local PostgreSQL inside the container for the preview/run loop. Idempotent.
# Generated Phoenix/Ash apps default to postgres/postgres @ 127.0.0.1:5432.
set -euo pipefail

PGBIN="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -n1)"
PGDATA="${PGDATA:-/var/lib/postgresql/data}"
PGPORT="${PGPORT:-5432}"
PGPASSWORD_VAL="${POSTGRES_PASSWORD:-postgres}"

install -d -o postgres -g postgres "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  su postgres -c "$PGBIN/initdb -D '$PGDATA' --auth-local=trust --auth-host=md5 -U postgres"
fi

# Already running? (re-entrancy)
if su postgres -c "$PGBIN/pg_ctl -D '$PGDATA' status" >/dev/null 2>&1; then
  exit 0
fi

# `-l <logfile>` is REQUIRED, not cosmetic: without it, pg_ctl starts the postgres daemon inheriting
# this script's stdout/stderr — i.e. the `msb exec` pipe when this runs in the build sandbox. The
# long-lived server then holds that pipe open, so after the build entrypoint exits the pipe never
# reaches EOF and `msb exec` never reports the process exit (the build worker wedges until the 30-min
# watchdog). Redirecting the server log to a file detaches it from the exec pipe → clean exit.
su postgres -c "$PGBIN/pg_ctl -D '$PGDATA' -w -l '$PGDATA/server.log' -o '-c listen_addresses=127.0.0.1 -p $PGPORT' start"

# Ensure the superuser password matches the app's default config.
su postgres -c "psql -v ON_ERROR_STOP=1 --username postgres --port $PGPORT \
  -c \"ALTER USER postgres WITH PASSWORD '${PGPASSWORD_VAL}';\""

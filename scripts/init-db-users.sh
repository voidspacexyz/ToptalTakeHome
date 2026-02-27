#!/usr/bin/env bash
# =============================================================================
# scripts/init-db-users.sh
#
# One-time post-provision script: creates the app_rw and app_ro PostgreSQL
# roles and grants appropriate permissions on the application database.
#
# Run ONCE after `tofu apply` completes, from any host that can reach the
# PostgreSQL private endpoint (e.g. an Azure VM in the VNet, a bastion host,
# or a self-hosted CI runner attached to the VNet).
#
# Prerequisites:
#   - az CLI logged in with permissions to read Key Vault secrets
#   - psql client installed (apt install postgresql-client / brew install libpq)
#   - Network route to node--prod--postgres.postgres.database.azure.com:5432
#
# Usage:
#   export KEY_VAULT_NAME=node-prod-kv       # or pass as first argument
#   bash scripts/init-db-users.sh
#
#   # Override individual values via env vars if not using Key Vault:
#   export PG_HOST=node--prod--postgres.postgres.database.azure.com
#   export PG_DB=appdb
#   export PG_ADMIN_USER=pgadmin
#   export PG_ADMIN_PASS=<value>
#   export APP_RW_PASS=<value>
#   export APP_RO_PASS=<value>
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override via env vars or Key Vault
# ---------------------------------------------------------------------------

KEY_VAULT_NAME="${KEY_VAULT_NAME:-${1:-}}"
PG_HOST="${PG_HOST:-}"
PG_DB="${PG_DB:-}"
PG_PORT="${PG_PORT:-5432}"
PG_ADMIN_USER="${PG_ADMIN_USER:-}"
PG_ADMIN_PASS="${PG_ADMIN_PASS:-}"
APP_RW_USER="app_rw"
APP_RW_PASS="${APP_RW_PASS:-}"
APP_RO_USER="app_ro"
APP_RO_PASS="${APP_RO_PASS:-}"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

log()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
err()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] ERROR: $*" >&2; exit 1; }

kv_secret() {
  local name="$1"
  az keyvault secret show \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "${name}" \
    --query value \
    --output tsv 2>/dev/null \
  || err "Failed to read Key Vault secret '${name}' from vault '${KEY_VAULT_NAME}'"
}

# ---------------------------------------------------------------------------
# Fetch credentials from Key Vault (unless already set via env vars)
# ---------------------------------------------------------------------------

if [[ -n "${KEY_VAULT_NAME}" ]]; then
  log "Fetching credentials from Key Vault: ${KEY_VAULT_NAME}"
  [[ -z "${PG_HOST}" ]]        && PG_HOST="$(az postgres flexible-server show \
      --resource-group "$(az keyvault show --name "${KEY_VAULT_NAME}" --query resourceGroup --output tsv)" \
      --name "$(az postgres flexible-server list --query "[?contains(name,'prod--postgres')].name | [0]" --output tsv 2>/dev/null || true)" \
      --query fullyQualifiedDomainName --output tsv 2>/dev/null || true)"
  [[ -z "${PG_DB}" ]]          && PG_DB="appdb"
  [[ -z "${PG_ADMIN_USER}" ]]  && PG_ADMIN_USER="$(kv_secret pg-admin-username)"
  [[ -z "${PG_ADMIN_PASS}" ]]  && PG_ADMIN_PASS="$(kv_secret pg-admin-password)"
  [[ -z "${APP_RW_PASS}" ]]    && APP_RW_PASS="$(kv_secret app-rw-password)"
  [[ -z "${APP_RO_PASS}" ]]    && APP_RO_PASS="$(kv_secret app-ro-password)"
fi

# ---------------------------------------------------------------------------
# Validate required values
# ---------------------------------------------------------------------------

[[ -z "${PG_HOST}" ]]       && err "PG_HOST is not set. Pass KEY_VAULT_NAME or set PG_HOST explicitly."
[[ -z "${PG_DB}" ]]         && err "PG_DB is not set."
[[ -z "${PG_ADMIN_USER}" ]] && err "PG_ADMIN_USER is not set."
[[ -z "${PG_ADMIN_PASS}" ]] && err "PG_ADMIN_PASS is not set."
[[ -z "${APP_RW_PASS}" ]]   && err "APP_RW_PASS is not set."
[[ -z "${APP_RO_PASS}" ]]   && err "APP_RO_PASS is not set."

log "Target: ${PG_HOST}:${PG_PORT}/${PG_DB}"
log "Admin user: ${PG_ADMIN_USER}"

# ---------------------------------------------------------------------------
# Execute SQL over a single psql session
# Use PGPASSWORD so no .pgpass file is needed
# ---------------------------------------------------------------------------

export PGPASSWORD="${PG_ADMIN_PASS}"

run_sql() {
  psql \
    --host="${PG_HOST}" \
    --port="${PG_PORT}" \
    --username="${PG_ADMIN_USER}" \
    --dbname="${PG_DB}" \
    --no-password \
    --set ON_ERROR_STOP=1 \
    "$@"
}

log "Creating roles and granting permissions..."

run_sql <<SQL
-- ── Read-Write role ─────────────────────────────────────────────────────────
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${APP_RW_USER}') THEN
    CREATE ROLE ${APP_RW_USER} WITH LOGIN PASSWORD '${APP_RW_PASS}';
    RAISE NOTICE 'Role ${APP_RW_USER} created.';
  ELSE
    -- Rotate password on re-run (idempotent credential refresh)
    ALTER ROLE ${APP_RW_USER} WITH PASSWORD '${APP_RW_PASS}';
    RAISE NOTICE 'Role ${APP_RW_USER} already exists — password updated.';
  END IF;
END
\$\$;

-- ── Read-Only role ───────────────────────────────────────────────────────────
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${APP_RO_USER}') THEN
    CREATE ROLE ${APP_RO_USER} WITH LOGIN PASSWORD '${APP_RO_PASS}';
    RAISE NOTICE 'Role ${APP_RO_USER} created.';
  ELSE
    ALTER ROLE ${APP_RO_USER} WITH PASSWORD '${APP_RO_PASS}';
    RAISE NOTICE 'Role ${APP_RO_USER} already exists — password updated.';
  END IF;
END
\$\$;

-- ── Database-level grants ────────────────────────────────────────────────────
GRANT CONNECT ON DATABASE ${PG_DB} TO ${APP_RW_USER}, ${APP_RO_USER};

-- ── Schema-level grants ──────────────────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO ${APP_RW_USER}, ${APP_RO_USER};

-- ── Table grants — existing tables ──────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${APP_RW_USER};
GRANT SELECT                          ON ALL TABLES IN SCHEMA public TO ${APP_RO_USER};

-- ── Sequence grants — existing sequences ────────────────────────────────────
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${APP_RW_USER};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${APP_RO_USER};

-- ── Default privileges — tables created in the future ───────────────────────
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${APP_RW_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO ${APP_RO_USER};

-- ── Default privileges — sequences created in the future ────────────────────
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO ${APP_RW_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO ${APP_RO_USER};
SQL

unset PGPASSWORD

log "Done. Roles created and grants applied."
log ""
log "Summary:"
log "  ${APP_RW_USER}  — CONNECT + full DML on all tables/sequences in ${PG_DB}.public"
log "  ${APP_RO_USER}  — CONNECT + SELECT on all tables/sequences in ${PG_DB}.public"
log ""
log "Helm deploy command (replace <ns> with your namespace):"
log "  helm upgrade --install node-api ./k8s/helm/api \\"
log "    -n <ns> \\"
log "    -f k8s/helm/values-prod.yaml \\"
log "    --set dbSecret.user=${APP_RW_USER} \\"
log "    --set dbSecret.password='\${APP_RW_PASS}'"

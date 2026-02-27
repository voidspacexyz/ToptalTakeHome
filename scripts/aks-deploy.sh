#!/usr/bin/env bash
# =============================================================================
# scripts/aks-deploy.sh
#
# Deploy node-api and node-web Helm charts to the Azure Kubernetes Service
# cluster (node--prod--aks).
#
# What this script does:
#   1. Validates prerequisites (az, kubectl, helm)
#   2. Authenticates kubectl to AKS via `az aks get-credentials`
#   3. Applies namespace + RBAC manifests (idempotent)
#   4. Creates / refreshes the ACR image-pull secret
#   5. Fetches runtime secrets from Azure Key Vault
#   6. Runs `helm upgrade --install` for the API chart
#   7. Runs `helm upgrade --install` for the Web chart
#   8. Waits for both rollouts to complete
#   9. Prints a summary with pod status
#
# Prerequisites:
#   - az CLI, kubectl, and helm ≥ 3 installed
#   - az CLI logged in (az login / service principal / federated identity)
#   - Network access to the AKS API server
#
# Usage:
#   # Minimal — all secrets fetched from Key Vault automatically:
#   export KEY_VAULT_NAME=node-prod-kv
#   bash scripts/aks-deploy.sh
#
#   # Override the image tag (defaults to "latest"):
#   IMAGE_TAG=v1.2.3 bash scripts/aks-deploy.sh
#
#   # Override individual secrets if Key Vault is unreachable:
#   export APP_RW_PASS=<secret>
#   export REDIS_ACCESS_KEY=<secret>
#   bash scripts/aks-deploy.sh
#
# Environment variables (all optional if KEY_VAULT_NAME is set):
#   KEY_VAULT_NAME     Azure Key Vault name (default: node-prod-kv)
#   RESOURCE_GROUP     Azure Resource Group  (default: RamToptal)
#   AKS_CLUSTER_NAME   AKS cluster name      (default: node--prod--aks)
#   NAMESPACE          Kubernetes namespace   (default: node--prod--ns)
#   IMAGE_TAG          Docker image tag       (default: latest)
#   APP_RW_PASS        app_rw DB password     (fetched from KV if not set)
#   REDIS_ACCESS_KEY   Redis primary key      (fetched from KV if not set)
#   PG_HOST            PostgreSQL FQDN        (fetched from KV if not set)
#   PG_DB              PostgreSQL database name (default: appdb)
#   INGRESS_HOST       Hostname for Ingress   (optional, leave blank to skip)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults — override via environment variables
# ---------------------------------------------------------------------------

KEY_VAULT_NAME="${KEY_VAULT_NAME:-node-prod-kv}"
RESOURCE_GROUP="${RESOURCE_GROUP:-RamToptal}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-node--prod--aks}"
NAMESPACE="${NAMESPACE:-node--prod--ns}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# PostgreSQL connection details
PG_HOST="${PG_HOST:-}"
PG_DB="${PG_DB:-appdb}"
PG_PORT="${PG_PORT:-5432}"

# App user created by scripts/init-db-users.sh (role name is fixed)
APP_RW_USER="app_rw"
APP_RW_PASS="${APP_RW_PASS:-}"

# Redis
REDIS_ACCESS_KEY="${REDIS_ACCESS_KEY:-}"

# Ingress hostname (leave empty to skip setting host in values)
INGRESS_HOST="${INGRESS_HOST:-}"

# ACR pull credentials (static token — rotate via Azure portal or `az acr token`)
ACR_REGISTRY="nodeprodacr.azurecr.io"
ACR_PULL_USER="${ACR_PULL_USER:-NodeACRPullTokken01}"
ACR_PULL_PASS="${ACR_PULL_PASS:-5KctAMG2KdZrpEKMyZ2gV51QGRl2rXPY80Yl14nGxqWNeVoonYrXJQQJ99CBACGhslBEqg7NAAABAZCRddby}"
ACR_SECRET_NAME="acr-pull-secret"

# Chart paths (relative to repo root; script can be run from anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELM_API_CHART="${REPO_ROOT}/k8s/helm/api"
HELM_WEB_CHART="${REPO_ROOT}/k8s/helm/web"
VALUES_PROD="${REPO_ROOT}/k8s/helm/values-prod.yaml"
MANIFEST_NAMESPACE="${REPO_ROOT}/k8s/manifests/namespace.yaml"
MANIFEST_RBAC="${REPO_ROOT}/k8s/manifests/rbac.yaml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
err()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] ERROR: $*" >&2; exit 1; }
ok()   { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] OK: $*"; }

require_cmd() {
  command -v "$1" &>/dev/null || err "Required command not found: $1 — please install it and re-run."
}

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
# 1. Validate prerequisites
# ---------------------------------------------------------------------------

log "=== Step 1: Validating prerequisites ==="
require_cmd az
require_cmd kubectl
require_cmd helm

# Confirm az is authenticated
az account show --query id --output tsv &>/dev/null \
  || err "az CLI is not authenticated. Run 'az login' or configure a service principal."

ok "All prerequisites satisfied."

# ---------------------------------------------------------------------------
# 2. Authenticate kubectl to AKS
# ---------------------------------------------------------------------------

log "=== Step 2: Fetching AKS credentials ==="
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER_NAME}" \
  --overwrite-existing

kubectl cluster-info --request-timeout=10s \
  || err "Cannot reach AKS API server. Check network connectivity and RBAC."

ok "kubectl is now configured for cluster '${AKS_CLUSTER_NAME}'."

# ---------------------------------------------------------------------------
# 3. Apply namespace and RBAC manifests (idempotent)
# ---------------------------------------------------------------------------

log "=== Step 3: Applying namespace and RBAC manifests ==="

[[ -f "${MANIFEST_NAMESPACE}" ]] \
  || err "Namespace manifest not found: ${MANIFEST_NAMESPACE}"
[[ -f "${MANIFEST_RBAC}" ]] \
  || err "RBAC manifest not found: ${MANIFEST_RBAC}"

kubectl apply -f "${MANIFEST_NAMESPACE}"
kubectl apply -f "${MANIFEST_RBAC}"

ok "Namespace '${NAMESPACE}' and RBAC resources applied."

# ---------------------------------------------------------------------------
# 4. Create / refresh ACR image-pull secret
# ---------------------------------------------------------------------------

log "=== Step 4: Creating ACR pull secret '${ACR_SECRET_NAME}' in '${NAMESPACE}' ==="

kubectl create secret docker-registry "${ACR_SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --docker-server="${ACR_REGISTRY}" \
  --docker-username="${ACR_PULL_USER}" \
  --docker-password="${ACR_PULL_PASS}" \
  --dry-run=client \
  --output=yaml \
| kubectl apply -f -

ok "ACR pull secret created/updated."

# ---------------------------------------------------------------------------
# 5. Fetch runtime secrets from Azure Key Vault
# ---------------------------------------------------------------------------

log "=== Step 5: Fetching runtime secrets from Key Vault '${KEY_VAULT_NAME}' ==="

# PostgreSQL FQDN — derive from Flexible Server if not provided
if [[ -z "${PG_HOST}" ]]; then
  log "PG_HOST not set — fetching from Flexible Server resource..."
  PG_HOST="$(az postgres flexible-server show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "node--prod--postgres" \
    --query fullyQualifiedDomainName \
    --output tsv 2>/dev/null)" \
  || err "Could not resolve PostgreSQL FQDN. Set PG_HOST explicitly."
fi

# app_rw password (created by scripts/init-db-users.sh)
if [[ -z "${APP_RW_PASS}" ]]; then
  log "APP_RW_PASS not set — reading from Key Vault secret 'app-rw-password'..."
  APP_RW_PASS="$(kv_secret app-rw-password)"
fi

# Redis primary access key
if [[ -z "${REDIS_ACCESS_KEY}" ]]; then
  log "REDIS_ACCESS_KEY not set — reading from Key Vault secret 'redis-primary-access-key'..."
  REDIS_ACCESS_KEY="$(kv_secret redis-primary-access-key)"
fi

# Construct the Redis URL (TLS, port 6380)
REDIS_HOST="$(az redis show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "node-prod-redis" \
  --query hostName \
  --output tsv 2>/dev/null)" \
|| err "Could not resolve Redis hostname. Ensure 'node-prod-redis' exists in '${RESOURCE_GROUP}'."

REDIS_URL="rediss://:${REDIS_ACCESS_KEY}@${REDIS_HOST}:6380/0"

ok "Secrets fetched."
log "  PG_HOST     : ${PG_HOST}"
log "  PG_DB       : ${PG_DB}"
log "  DB user     : ${APP_RW_USER}"
log "  Redis host  : ${REDIS_HOST}"

# ---------------------------------------------------------------------------
# 6. Deploy API Helm chart
# ---------------------------------------------------------------------------

log "=== Step 6: Deploying API chart (image tag: ${IMAGE_TAG}) ==="

HELM_API_EXTRA_ARGS=()
if [[ -n "${INGRESS_HOST}" ]]; then
  HELM_API_EXTRA_ARGS+=("--set" "ingress.host=${INGRESS_HOST}")
fi

helm upgrade --install node-api "${HELM_API_CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_PROD}" \
  --set image.repository="${ACR_REGISTRY}/node-api" \
  --set image.tag="${IMAGE_TAG}" \
  --set db.host="${PG_HOST}" \
  --set db.name="${PG_DB}" \
  --set db.port="${PG_PORT}" \
  --set dbSecret.user="${APP_RW_USER}" \
  --set dbSecret.password="${APP_RW_PASS}" \
  --wait \
  --timeout 5m \
  --history-max 5 \
  "${HELM_API_EXTRA_ARGS[@]}"

ok "API chart deployed."

# ---------------------------------------------------------------------------
# 7. Deploy Web Helm chart
# ---------------------------------------------------------------------------

log "=== Step 7: Deploying Web chart (image tag: ${IMAGE_TAG}) ==="

HELM_WEB_EXTRA_ARGS=()
if [[ -n "${INGRESS_HOST}" ]]; then
  HELM_WEB_EXTRA_ARGS+=("--set" "ingress.host=${INGRESS_HOST}")
fi

helm upgrade --install node-web "${HELM_WEB_CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_PROD}" \
  --set image.repository="${ACR_REGISTRY}/node-web" \
  --set image.tag="${IMAGE_TAG}" \
  --set app.apiHost="http://node--prod--svc--api:3000" \
  --set appSecret.redisUrl="${REDIS_URL}" \
  --rollback-on-failure \
  --wait \
  --timeout 5m \
  --history-max 5 \
  "${HELM_WEB_EXTRA_ARGS[@]}"

ok "Web chart deployed."

# ---------------------------------------------------------------------------
# 8. Wait for rollouts to be healthy
# ---------------------------------------------------------------------------

log "=== Step 8: Verifying rollout health ==="

kubectl rollout status deployment/node-api \
  --namespace "${NAMESPACE}" \
  --timeout=3m \
  && ok "node-api rollout complete."

kubectl rollout status deployment/node-web \
  --namespace "${NAMESPACE}" \
  --timeout=3m \
  && ok "node-web rollout complete."

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------

log ""
log "========================================================"
log " Deployment summary"
log "========================================================"
log " Cluster    : ${AKS_CLUSTER_NAME}"
log " Namespace  : ${NAMESPACE}"
log " Image tag  : ${IMAGE_TAG}"
log " PostgreSQL : ${PG_HOST}:${PG_PORT}/${PG_DB} (user: ${APP_RW_USER})"
log " Redis      : ${REDIS_HOST}:6380 (TLS)"
log "--------------------------------------------------------"
log " Pods:"
kubectl get pods -n "${NAMESPACE}" -o wide
log ""
log " Services:"
kubectl get svc -n "${NAMESPACE}"
log ""

# Print Application Gateway public IP if the ingress object exists
APPGW_IP="$(kubectl get ingress -n "${NAMESPACE}" \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
if [[ -n "${APPGW_IP}" ]]; then
  log " Application Gateway public IP : ${APPGW_IP}"
  log " Test end-to-end               : curl http://${APPGW_IP}/"
else
  log " Ingress IP not yet assigned — check again in a few minutes:"
  log "   kubectl get ingress -n ${NAMESPACE}"
fi

log "========================================================"
log " Deployment complete."
log "========================================================"

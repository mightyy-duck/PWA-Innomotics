#!/usr/bin/env bash
# Build the image and push it to the QA tenant's Azure Container Registry.
#
# Usage:
#   ACR_NAME=<qa-registry> [QA_TENANT_ID=<guid>] [QA_SUBSCRIPTION_ID=<guid>] \
#     ./scripts/push-image.sh [tag]
#
# ACR_NAME is the registry name (without .azurecr.io) in the QA tenant.
# Default tag: build-<utc timestamp>. Also pushes :latest.
set -eu

ACR_NAME="${ACR_NAME:-}"
IMAGE_NAME="${IMAGE_NAME:-pwa-innomotics}"
TAG="${1:-build-$(date -u +%Y.%m.%d-%H.%M.%S)-utc}"

fail() { echo "ABORT: $1" >&2; exit 1; }

[ -n "$ACR_NAME" ] || fail "ACR_NAME is not set (the QA tenant's registry name)."
docker info >/dev/null 2>&1 || fail "Docker daemon not running."

# Make sure we are signed in to the QA tenant, not the other one.
if [ -n "${QA_TENANT_ID:-}" ]; then
  current_tenant=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
  [ "$current_tenant" = "$QA_TENANT_ID" ] || fail "az is on tenant '${current_tenant:-none}', expected $QA_TENANT_ID. Run: az login --tenant $QA_TENANT_ID"
fi
[ -z "${QA_SUBSCRIPTION_ID:-}" ] || az account set --subscription "$QA_SUBSCRIPTION_ID"

az acr login --name "$ACR_NAME" >/dev/null || fail "az acr login --name $ACR_NAME failed."

LOGIN_SERVER="${ACR_NAME}.azurecr.io"
FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${TAG}"

echo "=== Building $FULL_IMAGE (linux/amd64) ==="
# amd64 explicitly: App Service runs amd64, Apple Silicon builds arm64 by default.
docker build --platform linux/amd64 -t "$FULL_IMAGE" -t "${LOGIN_SERVER}/${IMAGE_NAME}:latest" .

echo "=== Pushing ==="
docker push "$FULL_IMAGE"
docker push "${LOGIN_SERVER}/${IMAGE_NAME}:latest"

echo "Pushed: $FULL_IMAGE"

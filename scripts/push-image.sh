#!/usr/bin/env bash
# Build the image and push it to the QA tenant's Azure Container Registry.
#
# Usage:
#   ./scripts/push-image.sh [options] [tag]
#     tag             default: build-<utc timestamp>-<commit>. Also pushes :latest.
#     --check         preflight checks only, build nothing
#     --allow-dirty   build even with uncommitted changes (tag gets -dirty)
#     --verbose       stream the full docker output
#
# Defaults (override with env vars): ACR_NAME=pwaqa, IMAGE_NAME=pwa-innomotics,
# QA_TENANT_ID=8c66b612-f806-4e98-8ffb-dacca0235e16, optional QA_SUBSCRIPTION_ID.
# To build AND deploy in one go use ./scripts/release.sh.
set -eu
. "$(dirname "$0")/lib.sh"

CHECK_ONLY=false
TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check)       CHECK_ONLY=true; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --verbose)     VERBOSE=1; shift ;;
    -h|--help)     sed -n '2,13p' "$0"; exit 0 ;;
    -*)            die "Unknown option: $1 (see --help)" ;;
    *)             TAG="$1"; shift ;;
  esac
done
TAG="${TAG:-build-$(date -u +%Y.%m.%d-%H.%M.%S)-$(git_rev)}"

LOGIN_SERVER="${ACR_NAME}.azurecr.io"
FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${TAG}"
LATEST_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:latest"

if $CHECK_ONLY; then STAGE_TOTAL=1; else STAGE_TOTAL=5; fi

stage "Preflight checks (ACR: $ACR_NAME, tenant: $QA_TENANT_ID)"
check_docker
check_az
check_acr "$ACR_NAME"
check_git
preflight_done
if $CHECK_ONLY; then finish "Preflight passed. Ready to push."; exit 0; fi

stage "Signing in to registry $LOGIN_SERVER"
az acr login --name "$ACR_NAME" >/dev/null || die "az acr login --name $ACR_NAME failed."
ok "Signed in"

stage "Building $FULL_IMAGE (linux/amd64)"
info "Usually 1-3 minutes. Add --verbose to see the docker output."
# amd64 explicitly: App Service runs amd64, Apple Silicon builds arm64 by default.
# OCI labels let anyone see which commit an image came from (docker inspect).
run_quiet "building" docker build --platform linux/amd64 \
  --label "org.opencontainers.image.revision=$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --label "org.opencontainers.image.version=$TAG" \
  -t "$FULL_IMAGE" -t "$LATEST_IMAGE" . || die "docker build failed (see the log lines above)."
ok "Image built"

stage "Pushing :$TAG"
run_quiet "pushing" docker push "$FULL_IMAGE" || die "docker push $FULL_IMAGE failed."
ok "Pushed $FULL_IMAGE"

stage "Pushing :latest"
run_quiet "pushing" docker push "$LATEST_IMAGE" || die "docker push $LATEST_IMAGE failed."
ok "Pushed $LATEST_IMAGE"

finish "Push complete: $FULL_IMAGE"
[ -n "${RELEASE_RUN:-}" ] || info "Next, deploy it: ./scripts/deploy-webapp.sh --tag $TAG"

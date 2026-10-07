#!/usr/bin/env bash
# Point the App Service at an image in ACR (pulled with the app's managed identity),
# set port + startup command, restart, and wait until the app answers healthy.
#
# Usage:
#   ./scripts/deploy-webapp.sh [options]
#     --tag <tag>          image tag (default: latest; prefer an exact build-... tag)
#     --image <repo>       repository in the registry (default: pwa-innomotics)
#     --name <acr>         registry name (default: pwaqa)
#     --app <webapp>       App Service name (default: PWAQA)
#     --rg <group>         resource group (default: PWA-QA)
#     --port <port>        container port (default: 3000)
#     --startup "<cmd>"    startup command (default: none = image CMD)
#     --yes                don't ask for confirmation (CI / scripts)
#     --check              preflight checks only, change nothing
set -eu
. "$(dirname "$0")/lib.sh"

TAG=latest
PORT=3000
STARTUP=""
CHECK_ONLY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --tag)     TAG="$2"; shift 2 ;;
    --image)   IMAGE_NAME="$2"; shift 2 ;;
    --name|-n) ACR_NAME="$2"; shift 2 ;;
    --app)     WEBAPP_NAME="$2"; shift 2 ;;
    --rg)      RESOURCE_GROUP="$2"; shift 2 ;;
    --port)    PORT="$2"; shift 2 ;;
    --startup) STARTUP="$2"; shift 2 ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    --check)   CHECK_ONLY=true; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

case "$PORT" in ''|*[!0-9]*) die "--port must be a number, got '$PORT'." ;; esac
IMAGE="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${TAG}"

if $CHECK_ONLY; then STAGE_TOTAL=1; else STAGE_TOTAL=4; fi

stage "Preflight checks (app: $WEBAPP_NAME, image: $IMAGE)"
check_az
check_acr "$ACR_NAME"

fx="" main="" current_image="" current_port="" current_startup="" host=""
if $az_ready; then
  if fx=$(az webapp config show -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" --query linuxFxVersion -o tsv 2>/dev/null); then
    ok "Web app $WEBAPP_NAME found ($fx)"
    host=$(az webapp show -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" --query defaultHostName -o tsv)
  else
    bad "Web app $WEBAPP_NAME not found in $RESOURCE_GROUP" "Check --app / --rg, or the current subscription."
  fi

  # release.sh --check: the tag doesn't exist yet (release builds it), so skip.
  if [ -n "${RELEASE_RUN:-}" ]; then
    info "Image: release.sh builds and deploys a new exact tag"
  elif az acr repository show --name "$ACR_NAME" --image "${IMAGE_NAME}:${TAG}" >/dev/null 2>&1; then
    ok "Image ${IMAGE_NAME}:${TAG} exists"
  else
    bad "Image ${IMAGE_NAME}:${TAG} not in $ACR_NAME" "List images: ./scripts/list-images.sh --repo $IMAGE_NAME"
  fi
  [ "$TAG" != latest ] || [ -n "${RELEASE_RUN:-}" ] || warn "Deploying ':latest' - it moves with every push, so you can't tell later what's running" \
    "Prefer an exact tag: ./scripts/list-images.sh --repo $IMAGE_NAME"

  # The app pulls with its system-assigned identity; it needs AcrPull on the registry.
  principal=$(az webapp identity show -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" --query principalId -o tsv 2>/dev/null || echo "")
  acr_id=$(az acr show --name "$ACR_NAME" --query id -o tsv 2>/dev/null || echo "")
  if [ -z "$principal" ]; then
    bad "Web app has no system-assigned identity" "Run: az webapp identity assign -n $WEBAPP_NAME -g $RESOURCE_GROUP"
  elif [ -n "$acr_id" ]; then
    roles=$(az role assignment list --assignee "$principal" --scope "$acr_id" --include-inherited --query "[].roleDefinitionName" -o tsv 2>/dev/null || echo "")
    if echo "$roles" | grep -qiE '^(AcrPull|AcrPush|Contributor|Owner)$'; then ok "Web app identity can pull from $ACR_NAME"
    else info "Couldn't confirm AcrPull for the web app identity on $ACR_NAME (often just no permission to read roles). If the app fails to start, run:"
      echo "         az role assignment create --assignee $principal --role AcrPull --scope $acr_id"; fi
  fi
fi

preflight_done
if $CHECK_ONLY; then finish "Preflight passed. Ready to deploy."; exit 0; fi

stage "Current state of $WEBAPP_NAME"
if [ "$fx" = "sitecontainers" ]; then
  main=$(az webapp sitecontainers list -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" --query "[?isMain].name | [0]" -o tsv)
  [ -n "$main" ] || die "No main site container on $WEBAPP_NAME."
  read -r current_image current_port < <(az webapp sitecontainers show -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" \
    --container-name "$main" --query "[image, targetPort]" -o tsv | tr '\n' ' ')
  current_startup=$(az webapp sitecontainers show -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" --container-name "$main" --query startUpCommand -o tsv)
else
  current_image="${fx#DOCKER|}"
  current_port=$(az webapp config appsettings list -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" --query "[?name=='WEBSITES_PORT'].value | [0]" -o tsv)
  current_startup=$(az webapp config show -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" --query appCommandLine -o tsv)
fi
echo "            ${C_DIM}now${C_OFF}                                         ${C_DIM}after deploy${C_OFF}"
printf "  image    %-44s ${C_BOLD}%s${C_OFF}\n" "${current_image:-?}" "$IMAGE"
printf "  port     %-44s ${C_BOLD}%s${C_OFF}\n" "${current_port:-?}" "$PORT"
printf "  startup  %-44s ${C_BOLD}%s${C_OFF}\n" "${current_startup:-(image CMD)}" "${STARTUP:-(image CMD)}"
if [ "$current_image" = "$IMAGE" ] && [ "$TAG" != latest ]; then
  info "Already on this image; deploying again just restarts the app."
fi
if [ -n "$current_image" ] && [ "$current_image" != "$IMAGE" ]; then
  rb_repo="${current_image#*/}"
  info "To roll back later: ./scripts/deploy-webapp.sh --image ${rb_repo%%:*} --tag ${current_image##*:}${current_port:+ --port $current_port}"
fi
confirm "Deploy $IMAGE to $WEBAPP_NAME? The app restarts (brief downtime)."

stage "Updating $WEBAPP_NAME and restarting"
if [ "$fx" = "sitecontainers" ]; then
  # Sidecar model: settings live on the main site container.
  set -- --image "$IMAGE" --target-port "$PORT" --system-assigned-identity true
  [ -z "$STARTUP" ] || set -- "$@" --startup-cmd "$STARTUP"
  run_quiet "updating site container" az webapp sitecontainers update -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" \
    --container-name "$main" "$@" -o none || die "Updating site container '$main' failed."
  ok "Site container '$main' -> $IMAGE, port $PORT"
else
  # Classic single-container model.
  run_quiet "enabling managed-identity pull" az webapp config set -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" \
    --generic-configurations '{"acrUseManagedIdentityCreds": true}' -o none || die "Enabling managed-identity ACR pull failed."
  run_quiet "setting the image" az webapp config container set -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" \
    --container-image-name "$IMAGE" --container-registry-url "https://${ACR_NAME}.azurecr.io" -o none || die "Setting container image failed."
  run_quiet "setting WEBSITES_PORT" az webapp config appsettings set -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" \
    --settings "WEBSITES_PORT=$PORT" -o none || die "Setting WEBSITES_PORT failed."
  [ -z "$STARTUP" ] || run_quiet "setting the startup command" az webapp config set -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" \
    --startup-file "$STARTUP" -o none || die "Setting startup command failed."
  ok "Container -> $IMAGE, WEBSITES_PORT=$PORT"
fi
if [ -z "$STARTUP" ]; then info "Startup command: image default (CMD)"; else ok "Startup command: $STARTUP"; fi
run_quiet "restarting" az webapp restart -n "$WEBAPP_NAME" -g "$RESOURCE_GROUP" || die "Restart failed."
ok "Restart requested"

stage "Waiting for the app to come up healthy"
if ! health_check "https://$host$HEALTH_PATH" 300; then
  echo "  ${C_RED}[FAIL]${C_OFF} App didn't answer HTTP 200 on $HEALTH_PATH within 5 min."
  echo "         -> Logs: az webapp log tail -n $WEBAPP_NAME -g $RESOURCE_GROUP"
  [ -z "${rb_repo:-}" ] || echo "         -> Roll back: ./scripts/deploy-webapp.sh --image ${rb_repo%%:*} --tag ${current_image##*:} --yes"
  die "Deployed, but the app is not healthy."
fi

finish "Deployed $IMAGE and it's healthy"
info "Open: https://$host"

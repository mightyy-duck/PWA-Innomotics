#!/usr/bin/env bash
# One command release: build + push the image, then deploy that exact tag to
# the App Service and wait until it's healthy.
#
# Usage:
#   ./scripts/release.sh [options]
#     --yes            don't ask before deploying (CI / scripts)
#     --allow-dirty    release with uncommitted changes (tag gets -dirty)
#     --verbose        stream the full docker output
#     --port <port>, --startup "<cmd>"   passed to deploy-webapp.sh
#     --check          run both scripts' preflight checks only, change nothing
set -eu
dir="$(dirname "$0")"
. "$dir/lib.sh"

push_args=() deploy_args=()
CHECK_ONLY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)      deploy_args+=(--yes); shift ;;
    --allow-dirty) push_args+=(--allow-dirty); ALLOW_DIRTY=1; shift ;;
    --verbose)     push_args+=(--verbose); shift ;;
    --port|--startup) deploy_args+=("$1" "$2"); shift 2 ;;
    --check)       CHECK_ONLY=true; shift ;;
    -h|--help)     sed -n '2,11p' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

if $CHECK_ONLY; then
  # Run both so every problem shows up in one go.
  failed=0
  "$dir/push-image.sh" --check "${push_args[@]}" || failed=$((failed + 1))
  RELEASE_RUN=1 "$dir/deploy-webapp.sh" --check "${deploy_args[@]}" || failed=$((failed + 1))
  echo
  if [ "$failed" -gt 0 ]; then
    QUIET_EXIT=true
    echo "${C_RED}${C_BOLD}✗ Not ready to release: fix the [FAIL] items above.${C_OFF}" >&2
    exit 1
  fi
  echo "${C_GREEN}${C_BOLD}✓ Ready to release: ./scripts/release.sh${C_OFF}"
  exit 0
fi

TAG="build-$(date -u +%Y.%m.%d-%H.%M.%S)-$(git_rev)"
echo "${C_BOLD}Release $IMAGE_NAME:$TAG -> $WEBAPP_NAME${C_OFF}"
echo "${C_DIM}Part 1/2: build + push.  Part 2/2: deploy + health check.${C_OFF}"

echo; echo "${C_BOLD}===== Part 1/2: build + push =====${C_OFF}"
RELEASE_RUN=1 "$dir/push-image.sh" "${push_args[@]}" "$TAG" || { QUIET_EXIT=true; echo "${C_RED}${C_BOLD}✗ Release stopped in part 1 (build/push). Nothing was deployed.${C_OFF}" >&2; exit 1; }

echo; echo "${C_BOLD}===== Part 2/2: deploy =====${C_OFF}"
"$dir/deploy-webapp.sh" --tag "$TAG" "${deploy_args[@]}" || { QUIET_EXIT=true; echo "${C_RED}${C_BOLD}✗ Release stopped in part 2 (deploy). Image $TAG is pushed; retry: ./scripts/deploy-webapp.sh --tag $TAG${C_OFF}" >&2; exit 1; }

echo
echo "${C_GREEN}${C_BOLD}✓ Released $IMAGE_NAME:$TAG to $WEBAPP_NAME${C_OFF} ${C_DIM}(total $(elapsed "$script_started"))${C_OFF}"

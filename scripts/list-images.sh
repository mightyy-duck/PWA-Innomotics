#!/usr/bin/env bash
# List images (repositories + tags, newest first) in an Azure Container Registry.
#
# Usage:
#   ./scripts/list-images.sh                      # all repositories in pwaqa
#   ./scripts/list-images.sh --name <acr>         # another registry
#   ./scripts/list-images.sh --repo pwa-innomotics --top 5
set -eu
. "$(dirname "$0")/lib.sh"

REPO=""
TOP=10
while [ $# -gt 0 ]; do
  case "$1" in
    --name|-n) ACR_NAME="$2"; shift 2 ;;
    --repo|-r) REPO="$2"; shift 2 ;;
    --top)     TOP="$2"; shift 2 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

STAGE_TOTAL=3

stage "Preflight checks (ACR: $ACR_NAME, tenant: $QA_TENANT_ID)"
check_az
check_acr "$ACR_NAME"
preflight_done

stage "Finding repositories in $ACR_NAME"
repos=$REPO
[ -n "$repos" ] || repos=$(az acr repository list --name "$ACR_NAME" -o tsv) || die "Could not list repositories in $ACR_NAME."
if [ -z "$repos" ]; then
  warn "No repositories in $ACR_NAME" "Push one: ./scripts/push-image.sh"
  finish "Nothing to list."
  exit 0
fi
count=$(echo "$repos" | wc -w | tr -d ' ')
ok "$count repositor$( [ "$count" = 1 ] && echo y || echo ies)"

stage "Listing tags (newest $TOP per repository)"
failed=0
for repo in $repos; do
  echo
  echo "  ${C_BOLD}${ACR_NAME}.azurecr.io/${repo}${C_OFF}"
  if ! az acr repository show-tags --name "$ACR_NAME" --repository "$repo" \
      --detail --orderby time_desc --top "$TOP" \
      --query "[].{Tag:name, Updated:lastUpdateTime, Digest:digest}" -o table; then
    bad "Could not read tags for $repo" "Check you have AcrPull/Reader on $ACR_NAME."
    failed=$((failed + 1))
  fi
done

[ "$failed" -eq 0 ] || die "$failed repositor$( [ "$failed" = 1 ] && echo y || echo ies) could not be listed."
finish "Listed $count repositor$( [ "$count" = 1 ] && echo y || echo ies) in $ACR_NAME."

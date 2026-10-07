# Shared defaults, colored status output and preflight checks for the scripts
# in this folder. Source it: . "$(dirname "$0")/lib.sh"
# Run the scripts from Git Bash (Windows), WSL, macOS or Linux - not PowerShell/cmd.

ACR_NAME="${ACR_NAME:-pwaqa}"
QA_TENANT_ID="${QA_TENANT_ID:-8c66b612-f806-4e98-8ffb-dacca0235e16}"
IMAGE_NAME="${IMAGE_NAME:-pwa-innomotics}"
WEBAPP_NAME="${WEBAPP_NAME:-PWAQA}"
RESOURCE_GROUP="${RESOURCE_GROUP:-PWA-QA}"
HEALTH_PATH="${HEALTH_PATH:-/api/health}"

# az on Windows (Git Bash) ends lines with \r\n; a stray \r breaks names like
# "pwa\r" and comparisons like [ "$fx" = sitecontainers ]. Strip it everywhere.
az() {
  local out rc=0
  out=$(command az "$@") || rc=$?
  [ -z "$out" ] || printf '%s\n' "${out//$'\r'/}"
  return $rc
}

# --- Colors: on for a terminal, off when piped or NO_COLOR is set ------------
if { [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; } && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m' C_CYAN=$'\e[36m'
  C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_OFF=$'\e[0m'
else
  C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_BOLD="" C_DIM="" C_OFF=""
fi

ok()   { echo "  ${C_GREEN}[ok]${C_OFF}   $1"; }
bad()  { echo "  ${C_RED}[FAIL]${C_OFF} $1"; echo "         ${C_DIM}->${C_OFF} $2"; problems=$((problems + 1)); }
warn() { echo "  ${C_YELLOW}[warn]${C_OFF} $1"; [ -z "${2:-}" ] || echo "         ${C_DIM}->${C_OFF} $2"; }
info() { echo "  ${C_CYAN}[info]${C_OFF} $1"; }
die()  { echo "${C_RED}${C_BOLD}ABORT:${C_OFF} ${C_RED}$1${C_OFF}" >&2; exit 1; }

elapsed() { local s=$(( SECONDS - $1 )); [ "$s" -ge 60 ] && echo "$((s / 60))m$((s % 60))s" || echo "${s}s"; }

# --- Stages: "[2/4] Building image ..." then DONE (12s) / FAILED --------------
STAGE_TOTAL=0
stage_no=0
current_stage=""
stage_open=false
stage_started=0
script_started=$SECONDS

stage_end() {
  $stage_open || return 0
  echo "${C_GREEN}${C_BOLD}DONE${C_OFF}  ${C_DIM}[$stage_no/$STAGE_TOTAL]${C_OFF} $current_stage ${C_DIM}($(elapsed "$stage_started"))${C_OFF}"
  stage_open=false
}

stage() {
  stage_end
  stage_no=$((stage_no + 1))
  current_stage="$1"
  stage_open=true
  stage_started=$SECONDS
  echo
  echo "${C_BLUE}${C_BOLD}[$stage_no/$STAGE_TOTAL] $1${C_OFF}"
}

# Any non-zero exit (die, set -e, Ctrl+C) names the stage that failed.
QUIET_EXIT=false  # release.sh sets it: the child script already reported.
on_exit() {
  local code=$?
  [ "$code" -ne 0 ] && ! $QUIET_EXIT || return 0
  if $stage_open; then
    echo "${C_RED}${C_BOLD}FAILED${C_OFF} ${C_DIM}[$stage_no/$STAGE_TOTAL]${C_OFF} ${C_RED}$current_stage${C_OFF}" >&2
  fi
  echo >&2
  if [ "$stage_no" -gt 0 ]; then
    echo "${C_RED}${C_BOLD}✗ Not completed (exit $code). Nothing after the failed stage was run.${C_OFF}" >&2
  else
    echo "${C_RED}${C_BOLD}✗ Not started (exit $code).${C_OFF}" >&2
  fi
}
trap on_exit EXIT
trap 'exit 130' INT
# A command that fails under set -e would otherwise exit silently: name it.
set -E
trap 'echo "  ${C_RED}[FAIL]${C_OFF} Unexpected error at $(basename "${BASH_SOURCE[0]:-$0}"):$LINENO: $BASH_COMMAND" >&2' ERR

finish() {
  stage_end
  echo
  echo "${C_GREEN}${C_BOLD}✓ $1${C_OFF} ${C_DIM}(total $(elapsed "$script_started"))${C_OFF}"
}

# run_quiet "<what>" <cmd...>: run a slow command with a heartbeat every 15s so
# it never looks frozen. Output goes to a log; on failure the last 30 lines are
# shown. VERBOSE=1 streams the output instead.
LOG_DIR="${TMPDIR:-/tmp}"
run_quiet() {
  local what="$1"; shift
  if [ -n "${VERBOSE:-}" ]; then "$@"; return; fi
  local log="$LOG_DIR/pwa-$(date +%s)-$$.log" start=$SECONDS rc=0
  "$@" >"$log" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    [ $(( (SECONDS - start) % 15 )) -ne 0 ] || echo "  ${C_DIM}...  still $what ($(elapsed "$start"))${C_OFF}"
  done
  wait "$pid" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  ${C_RED}[FAIL]${C_OFF} $what failed. Last lines of the log ($log):"
    tail -n 30 "$log" | sed 's/^/         /'
  else
    rm -f "$log"
  fi
  return $rc
}

# confirm "<question>": asks y/N in a terminal; --yes (ASSUME_YES=1) skips it.
ASSUME_YES="${ASSUME_YES:-}"
confirm() {
  [ -z "$ASSUME_YES" ] || return 0
  [ -t 0 ] || die "Not a terminal, can't ask for confirmation. Re-run with --yes to proceed."
  local answer
  printf "  ${C_YELLOW}${C_BOLD}?${C_OFF} %s [y/N] " "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) die "Cancelled by user. Nothing was changed." ;; esac
}

# git_rev: short commit hash, plus "-dirty" when there are uncommitted changes.
git_rev() {
  git rev-parse --git-dir >/dev/null 2>&1 || { echo nogit; return; }
  local rev; rev=$(git rev-parse --short HEAD)
  [ -z "$(git status --porcelain)" ] || rev="$rev-dirty"
  echo "$rev"
}

# --- Preflight: run every check, report all problems at once -----------------
problems=0

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    bad "docker not installed" "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
  elif docker info >/dev/null 2>&1; then
    ok "Docker daemon running"
  else
    bad "Docker daemon not running" "Start Docker Desktop and wait until it says 'Engine running'."
  fi
}

# Sets az_ready=true when signed in to the QA tenant.
az_ready=false
check_az() {
  if ! command -v az >/dev/null 2>&1; then
    bad "Azure CLI (az) not installed" "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
    return
  fi
  info "Checking Azure sign-in (Azure CLI calls can take up to a minute each)..."
  local current_tenant
  current_tenant=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
  if [ -z "$current_tenant" ]; then
    bad "az not signed in" "Run: az login --tenant $QA_TENANT_ID"
  elif [ "$current_tenant" != "$QA_TENANT_ID" ]; then
    bad "az is on tenant $current_tenant" "Run: az login --tenant $QA_TENANT_ID"
  else
    ok "az signed in to QA tenant"
    az_ready=true
    [ -z "${QA_SUBSCRIPTION_ID:-}" ] || az account set --subscription "$QA_SUBSCRIPTION_ID"
  fi
}

# Needs check_az first.
check_acr() {
  $az_ready || return 0
  if az acr show --name "$1" --query name -o tsv >/dev/null 2>&1; then
    ok "Registry $1 reachable"
  else
    bad "Registry $1 not found in the current subscription" \
      "Pick the right subscription: az account set --subscription <id>  (or set QA_SUBSCRIPTION_ID)"
  fi
}

# Uncommitted changes fail the check (the image couldn't be traced back to a
# commit); ALLOW_DIRTY=1 / --allow-dirty turns it into a warning.
check_git() {
  git rev-parse --git-dir >/dev/null 2>&1 || { warn "Not a git repository" "The image tag won't carry a commit."; return 0; }
  if [ -z "$(git status --porcelain)" ]; then
    ok "Working tree clean (commit $(git rev-parse --short HEAD))"
  elif [ -n "${ALLOW_DIRTY:-}" ]; then
    warn "Uncommitted changes will be built into the image (--allow-dirty)" "The tag gets a '-dirty' suffix."
  else
    bad "Uncommitted changes" "Commit them first so the image matches a commit (git status), or pass --allow-dirty."
  fi
  git fetch --quiet 2>/dev/null || true
  local behind
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
  if [ "$behind" = "0" ]; then ok "Branch up to date with remote ($(git rev-parse --abbrev-ref HEAD))"
  else warn "Branch is $behind commit(s) behind its remote - you'd release old code" "Run: git pull"; fi
}

preflight_done() {
  [ "$problems" -eq 0 ] || die "$problems check(s) failed. Fix the [FAIL] items above and run again."
  echo "  ${C_GREEN}All required checks passed.${C_OFF}"
}

# health_check <url> [timeout seconds]: poll until HTTP 200; a fresh container
# typically needs 1-3 minutes on App Service.
health_check() {
  local url="$1" timeout="${2:-300}" start=$SECONDS code
  info "Polling $url (up to $((timeout / 60)) min; first start usually takes 1-3 min)"
  while :; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" 2>/dev/null || true)
    if [ "$code" = "200" ]; then ok "Healthy: HTTP 200 after $(elapsed "$start")"; return 0; fi
    [ $(( SECONDS - start )) -lt "$timeout" ] || return 1
    echo "  ${C_DIM}...  not up yet (HTTP ${code:-none}, $(elapsed "$start"))${C_OFF}"
    sleep 10
  done
}

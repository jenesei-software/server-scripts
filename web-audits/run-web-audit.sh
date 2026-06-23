#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE_INPUT="${1:-}"
URL_INPUT="${2:-}"
TEST_INPUT="${3:-}"
NODE_KEYRING="/etc/apt/keyrings/nodesource.gpg"
NODE_SOURCE_LIST="/etc/apt/sources.list.d/nodesource.list"
DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"
DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.list"
CHROME_KEYRING="/etc/apt/keyrings/google-chrome.gpg"
CHROME_SOURCE_LIST="/etc/apt/sources.list.d/google-chrome.list"
SUDO=()
DOCKER_CMD=()
LHCI_CMD=()
DOCKER_USED_IN_THIS_RUN=false
DOCKER_WAS_ACTIVE_BEFORE_RUN=true
REPORT_OWNER=""
REPORT_GROUP=""

LOG_COLOR='\033[1;36m'
LOG_RESET='\033[0m'

timestamp() { date '+%F %T'; }
log_line() {
  local level="$1"
  shift
  printf '%b[%s] %-7s%b %s\n' "$LOG_COLOR" "$(timestamp)" "$level" "$LOG_RESET" "$*"
}

log() { log_line "INFO" "$*"; }
warn() { log_line "WARN" "$*"; }
fail() { log_line "ERROR" "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Command not found: $1"; }

init_privileges() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    SUDO=()
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] && id "$SUDO_USER" >/dev/null 2>&1; then
      REPORT_OWNER="$SUDO_USER"
      REPORT_GROUP="$(id -gn "$SUDO_USER")"
    fi
    return
  fi

  REPORT_OWNER="$(id -un)"
  REPORT_GROUP="$(id -gn)"

  if command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  else
    SUDO=()
  fi
}

ensure_sudo() {
  local reason="$1"
  [[ ${EUID:-$(id -u)} -eq 0 ]] && return
  (( ${#SUDO[@]} > 0 )) || fail "$reason requires sudo, but sudo is not installed or not available for this user"

  if ! sudo -n true 2>/dev/null; then
    log "$reason requires sudo"
    sudo -v
  fi
}

run_apt_get() {
  ensure_sudo "Installing or updating system packages"
  "${SUDO[@]}" apt-get "$@"
}

run_systemctl() {
  ensure_sudo "Managing the Docker system service"
  "${SUDO[@]}" systemctl "$@"
}

docker_cmd() {
  if (( ${#DOCKER_CMD[@]} > 0 )); then
    "${DOCKER_CMD[@]}" "$@"
    return
  fi

  if docker info >/dev/null 2>&1; then
    docker "$@"
    return
  fi

  if (( ${#SUDO[@]} > 0 )); then
    "${SUDO[@]}" docker "$@"
    return
  fi

  docker "$@"
}

set_docker_command() {
  if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
  elif (( ${#SUDO[@]} > 0 )) && sudo docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo docker)
  else
    fail "Docker daemon is not reachable. Check Docker service status and permissions."
  fi
}

resolve_env_path() {
  local candidate="$1"
  local candidate_dir
  local candidate_base

  if [[ "$candidate" = /* ]]; then
    printf '%s\n' "$candidate"
  elif [[ -f "$candidate" ]]; then
    candidate_dir="$(cd -- "$(dirname -- "$candidate")" && pwd)"
    candidate_base="$(basename -- "$candidate")"
    printf '%s/%s\n' "$candidate_dir" "$candidate_base"
  elif [[ -f "$SCRIPT_DIR/$candidate" ]]; then
    candidate_dir="$(cd -- "$(dirname -- "$SCRIPT_DIR/$candidate")" && pwd)"
    candidate_base="$(basename -- "$SCRIPT_DIR/$candidate")"
    printf '%s/%s\n' "$candidate_dir" "$candidate_base"
  else
    printf '%s/%s\n' "$SCRIPT_DIR" "$candidate"
  fi
}

absolute_module_path() {
  local value="$1"
  local value_dir
  local value_base

  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  value_dir="$(cd -- "$SCRIPT_DIR/$(dirname -- "$value")" && pwd)"
  value_base="$(basename -- "$value")"
  printf '%s/%s\n' "$value_dir" "$value_base"
}

resolve_env_file() {
  if [[ -n "$ENV_FILE_INPUT" && "$ENV_FILE_INPUT" == *.env ]]; then
    ENV_FILE="$(resolve_env_path "$ENV_FILE_INPUT")"
    URL_INPUT="${2:-}"
    TEST_INPUT="${3:-}"
    return
  fi

  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    ENV_FILE="$SCRIPT_DIR/.env"
  else
    ENV_FILE=""
  fi

  URL_INPUT="${1:-}"
  TEST_INPUT="${2:-}"
}

load_env() {
  resolve_env_file "$@"

  if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
    log "Loading environment from $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  elif [[ -n "$ENV_FILE" ]]; then
    fail "Environment file not found: $ENV_FILE"
  else
    log "Environment file is optional for this module; using defaults"
  fi

  WEB_AUDIT_RESULTS_DIR="$(absolute_module_path "${WEB_AUDIT_RESULTS_DIR:-reports}")"
  WEB_AUDIT_DEFAULT_TEST="${WEB_AUDIT_DEFAULT_TEST:-all}"
  WEB_AUDIT_NODE_MAJOR="${WEB_AUDIT_NODE_MAJOR:-22}"
  WEB_AUDIT_LHCI_VERSION="${WEB_AUDIT_LHCI_VERSION:-latest}"
  WEB_AUDIT_LHCI_RUNS="${WEB_AUDIT_LHCI_RUNS:-3}"
  WEB_AUDIT_LHCI_CHROME_FLAGS="${WEB_AUDIT_LHCI_CHROME_FLAGS:---headless=new --no-sandbox --disable-dev-shm-usage}"
  WEB_AUDIT_LHCI_TIMEOUT="${WEB_AUDIT_LHCI_TIMEOUT:-10m}"
  WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD="${WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD:-45000}"
  WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP="${WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP:-30000}"
  WEB_AUDIT_SITESPEED_IMAGE="${WEB_AUDIT_SITESPEED_IMAGE:-sitespeedio/sitespeed.io:41.3.3}"
  WEB_AUDIT_SITESPEED_BROWSER="${WEB_AUDIT_SITESPEED_BROWSER:-chrome}"
  WEB_AUDIT_SITESPEED_RUNS="${WEB_AUDIT_SITESPEED_RUNS:-3}"
  WEB_AUDIT_SITESPEED_CONNECTIVITY="${WEB_AUDIT_SITESPEED_CONNECTIVITY:-native}"
  WEB_AUDIT_SITESPEED_DOCKER_SHM_SIZE="${WEB_AUDIT_SITESPEED_DOCKER_SHM_SIZE:-2g}"
  WEB_AUDIT_SITESPEED_TIMEOUT="${WEB_AUDIT_SITESPEED_TIMEOUT:-30m}"
  WEB_AUDIT_SITESPEED_EXTRA_ARGS="${WEB_AUDIT_SITESPEED_EXTRA_ARGS:-}"
  WEB_AUDIT_CREATE_ZIP="${WEB_AUDIT_CREATE_ZIP:-true}"
  WEB_AUDIT_STOP_DOCKER_AFTER_RUN="${WEB_AUDIT_STOP_DOCKER_AFTER_RUN:-true}"
}

validate_bool() {
  local name="$1"
  local value="$2"
  [[ "$value" == "true" || "$value" == "false" ]] || fail "$name must be true or false"
}

validate_positive_int() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$name must be numeric"
  (( value >= 1 )) || fail "$name must be greater than zero"
}

validate_env() {
  [[ "$WEB_AUDIT_DEFAULT_TEST" == "all" || "$WEB_AUDIT_DEFAULT_TEST" == "lighthouse" || "$WEB_AUDIT_DEFAULT_TEST" == "sitespeed" ]] || fail "WEB_AUDIT_DEFAULT_TEST must be all, lighthouse, or sitespeed"
  [[ "$WEB_AUDIT_NODE_MAJOR" =~ ^[0-9]+$ ]] || fail "WEB_AUDIT_NODE_MAJOR must be numeric"
  validate_positive_int WEB_AUDIT_LHCI_RUNS "$WEB_AUDIT_LHCI_RUNS"
  validate_positive_int WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD "$WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD"
  validate_positive_int WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP "$WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP"
  validate_positive_int WEB_AUDIT_SITESPEED_RUNS "$WEB_AUDIT_SITESPEED_RUNS"
  validate_bool WEB_AUDIT_CREATE_ZIP "$WEB_AUDIT_CREATE_ZIP"
  validate_bool WEB_AUDIT_STOP_DOCKER_AFTER_RUN "$WEB_AUDIT_STOP_DOCKER_AFTER_RUN"
  [[ -n "$WEB_AUDIT_SITESPEED_IMAGE" ]] || fail "WEB_AUDIT_SITESPEED_IMAGE must not be empty"
  [[ -n "$WEB_AUDIT_SITESPEED_BROWSER" ]] || fail "WEB_AUDIT_SITESPEED_BROWSER must not be empty"
}

docker_was_active_before_run() {
  if systemctl is-active --quiet docker 2>/dev/null; then
    DOCKER_WAS_ACTIVE_BEFORE_RUN=true
  else
    DOCKER_WAS_ACTIVE_BEFORE_RUN=false
  fi
}

stop_sitespeed_container_if_running() {
  [[ -n "${SITESPEED_CONTAINER_NAME:-}" ]] || return
  command -v docker >/dev/null 2>&1 || return

  if docker_cmd ps --format '{{.Names}}' 2>/dev/null | grep -qx "$SITESPEED_CONTAINER_NAME"; then
    warn "Stopping sitespeed.io container: $SITESPEED_CONTAINER_NAME"
    docker_cmd stop "$SITESPEED_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}

stop_docker_if_started_by_this_run() {
  [[ "${WEB_AUDIT_STOP_DOCKER_AFTER_RUN:-true}" == "true" ]] || return
  [[ "${DOCKER_USED_IN_THIS_RUN:-false}" == "true" ]] || return
  [[ "${DOCKER_WAS_ACTIVE_BEFORE_RUN:-true}" == "false" ]] || return
  command -v docker >/dev/null 2>&1 || return

  local running_count
  running_count="$(docker_cmd ps -q 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$running_count" == "0" ]]; then
    log "Stopping Docker service because it was started only for this audit run"
    run_systemctl stop docker.socket >/dev/null 2>&1 || true
    run_systemctl stop docker >/dev/null 2>&1 || true
  else
    warn "Docker was started by this audit run, but other containers are running; leaving Docker active"
  fi
}

chown_reports_if_needed() {
  [[ -n "$REPORT_OWNER" && -n "$REPORT_GROUP" ]] || return
  [[ -d "${REPORT_ROOT:-}" ]] || return
  (( ${#SUDO[@]} > 0 )) || return

  "${SUDO[@]}" chown -R "$REPORT_OWNER:$REPORT_GROUP" "$REPORT_ROOT" >/dev/null 2>&1 || true
  if [[ -n "${ARCHIVE_FILE:-}" && -f "$ARCHIVE_FILE" ]]; then
    "${SUDO[@]}" chown "$REPORT_OWNER:$REPORT_GROUP" "$ARCHIVE_FILE" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local exit_code=$?
  stop_sitespeed_container_if_running
  stop_docker_if_started_by_this_run
  return "$exit_code"
}

prompt_for_url() {
  local value="$URL_INPUT"
  if [[ -z "$value" ]]; then
    printf 'Domain or URL to test: '
    read -r value || value=""
  fi
  [[ -n "$value" ]] || fail "Domain or URL is required"
  TEST_URL="$(normalize_url "$value")"
}

prompt_for_test_type() {
  local value="$TEST_INPUT"
  if [[ -z "$value" ]]; then
    printf 'Test type [all/lighthouse/sitespeed] (default: %s): ' "$WEB_AUDIT_DEFAULT_TEST"
    read -r value || value=""
  fi
  TEST_TYPE="${value:-$WEB_AUDIT_DEFAULT_TEST}"
  [[ "$TEST_TYPE" == "all" || "$TEST_TYPE" == "lighthouse" || "$TEST_TYPE" == "sitespeed" ]] || fail "Test type must be all, lighthouse, or sitespeed"
}

normalize_url() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [[ "$value" != *" "* ]] || fail "URL must not contain spaces"

  if [[ "$value" != http://* && "$value" != https://* ]]; then
    value="https://$value"
  fi
  [[ "$value" =~ ^https?://[^/]+.*$ ]] || fail "URL must look like https://example.com"
  printf '%s\n' "$value"
}

url_slug() {
  local value="$1"
  value="${value#http://}"
  value="${value#https://}"
  value="${value%%#*}"
  value="${value%%\?*}"
  value="$(printf '%s' "$value" | sed -E 's#[^A-Za-z0-9._-]+#_#g; s#^_+##; s#_+$##')"
  [[ -n "$value" ]] || value="site"
  printf '%s\n' "$value"
}

install_base_packages() {
  log "Installing base packages for web audits"
  export DEBIAN_FRONTEND=noninteractive
  export UCF_FORCE_CONFFOLD=1
  export NEEDRESTART_MODE=a

  run_apt_get update
  run_apt_get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    install ca-certificates curl gnupg jq openssl tar zip
}

install_node_if_missing() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    log "Node.js and npm are already installed: $(node --version)"
    return
  fi

  log "Installing Node.js $WEB_AUDIT_NODE_MAJOR.x"
  ensure_sudo "Installing Node.js"
  export DEBIAN_FRONTEND=noninteractive
  export UCF_FORCE_CONFFOLD=1
  export NEEDRESTART_MODE=a

  run_apt_get update
  run_apt_get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    install ca-certificates curl gnupg

  "${SUDO[@]}" install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
    | "${SUDO[@]}" gpg --batch --yes --dearmor -o "$NODE_KEYRING"
  "${SUDO[@]}" chmod 0644 "$NODE_KEYRING"

  printf 'deb [signed-by=%s] https://deb.nodesource.com/node_%s.x nodistro main\n' "$NODE_KEYRING" "$WEB_AUDIT_NODE_MAJOR" \
    | "${SUDO[@]}" tee "$NODE_SOURCE_LIST" >/dev/null
  "${SUDO[@]}" chmod 0644 "$NODE_SOURCE_LIST"

  run_apt_get update
  run_apt_get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    install nodejs
}

install_chrome_if_missing() {
  if command -v google-chrome >/dev/null 2>&1 || command -v google-chrome-stable >/dev/null 2>&1; then
    log "Google Chrome is already installed"
    return
  fi

  [[ "$(dpkg --print-architecture)" == "amd64" ]] || fail "Google Chrome apt package is only configured here for amd64. Use sitespeed.io Docker or install a compatible Chromium manually."

  log "Installing Google Chrome stable"
  ensure_sudo "Installing Google Chrome"
  export DEBIAN_FRONTEND=noninteractive
  export UCF_FORCE_CONFFOLD=1
  export NEEDRESTART_MODE=a

  "${SUDO[@]}" install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://dl.google.com/linux/linux_signing_key.pub" \
    | "${SUDO[@]}" gpg --batch --yes --dearmor -o "$CHROME_KEYRING"
  "${SUDO[@]}" chmod 0644 "$CHROME_KEYRING"

  printf 'deb [arch=amd64 signed-by=%s] http://dl.google.com/linux/chrome/deb/ stable main\n' "$CHROME_KEYRING" \
    | "${SUDO[@]}" tee "$CHROME_SOURCE_LIST" >/dev/null
  "${SUDO[@]}" chmod 0644 "$CHROME_SOURCE_LIST"

  run_apt_get update
  run_apt_get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    install google-chrome-stable
}

install_lhci_if_missing() {
  if command -v lhci >/dev/null 2>&1; then
    log "Lighthouse CI CLI is already installed: $(lhci --version)"
    LHCI_CMD=(lhci)
    return
  fi

  local lhci_dir="$SCRIPT_DIR/.tools/lhci"
  local lhci_bin="$lhci_dir/node_modules/.bin/lhci"

  if [[ -x "$lhci_bin" ]]; then
    log "Using local Lighthouse CI CLI: $lhci_bin"
    LHCI_CMD=("$lhci_bin")
    return
  fi

  log "Installing Lighthouse CI CLI locally: @lhci/cli@$WEB_AUDIT_LHCI_VERSION"
  install -d -m 0755 "$lhci_dir"
  npm install --prefix "$lhci_dir" "@lhci/cli@$WEB_AUDIT_LHCI_VERSION"
  LHCI_CMD=("$lhci_bin")
}

install_docker_if_missing() {
  docker_was_active_before_run

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and Docker Compose are already installed"
    if ! docker info >/dev/null 2>&1 && ! { (( ${#SUDO[@]} > 0 )) && sudo docker info >/dev/null 2>&1; }; then
      run_systemctl enable --now docker
    fi
    DOCKER_USED_IN_THIS_RUN=true
    set_docker_command
    return
  fi

  log "Installing Docker Engine and Docker Compose plugin"
  ensure_sudo "Installing Docker"
  export DEBIAN_FRONTEND=noninteractive
  export UCF_FORCE_CONFFOLD=1
  export NEEDRESTART_MODE=a

  run_apt_get update
  run_apt_get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    install ca-certificates curl gnupg

  "${SUDO[@]}" install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" \
    | "${SUDO[@]}" gpg --batch --yes --dearmor -o "$DOCKER_KEYRING"
  "${SUDO[@]}" chmod 0644 "$DOCKER_KEYRING"

  # shellcheck disable=SC1091
  source /etc/os-release
  printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/ubuntu %s stable\n' "$(dpkg --print-architecture)" "$DOCKER_KEYRING" "$VERSION_CODENAME" \
    | "${SUDO[@]}" tee "$DOCKER_SOURCE_LIST" >/dev/null
  "${SUDO[@]}" chmod 0644 "$DOCKER_SOURCE_LIST"

  run_apt_get update
  run_apt_get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  run_systemctl enable --now docker
  DOCKER_USED_IN_THIS_RUN=true
  set_docker_command
}

pull_sitespeed_image_if_missing() {
  if docker_cmd image inspect "$WEB_AUDIT_SITESPEED_IMAGE" >/dev/null 2>&1; then
    log "sitespeed.io Docker image is already present: $WEB_AUDIT_SITESPEED_IMAGE"
    return
  fi

  log "Pulling sitespeed.io Docker image: $WEB_AUDIT_SITESPEED_IMAGE"
  docker_cmd pull "$WEB_AUDIT_SITESPEED_IMAGE"
}

prepare_report_dir() {
  SITE_SLUG="$(url_slug "$TEST_URL")"
  RUN_ID="$(date '+%Y%m%d-%H%M%S')"
  REPORT_ROOT="$WEB_AUDIT_RESULTS_DIR/$SITE_SLUG/$RUN_ID"
  LOG_DIR="$REPORT_ROOT/logs"

  install -d -m 0755 "$REPORT_ROOT" "$LOG_DIR"
}

write_metadata() {
  local status="$1"
  jq -n \
    --arg url "$TEST_URL" \
    --arg testType "$TEST_TYPE" \
    --arg runId "$RUN_ID" \
    --arg status "$status" \
    --arg createdAt "$(date -Iseconds)" \
    --arg lighthouseRuns "$WEB_AUDIT_LHCI_RUNS" \
    --arg sitespeedRuns "$WEB_AUDIT_SITESPEED_RUNS" \
    --arg sitespeedImage "$WEB_AUDIT_SITESPEED_IMAGE" \
    '{
      url: $url,
      testType: $testType,
      runId: $runId,
      status: $status,
      updatedAt: $createdAt,
      lighthouseRuns: ($lighthouseRuns | tonumber),
      sitespeedRuns: ($sitespeedRuns | tonumber),
      sitespeedImage: $sitespeedImage
    }' > "$REPORT_ROOT/metadata.json"
}

write_lhci_config() {
  local target_dir="$1"
  TEST_URL="$TEST_URL" \
  WEB_AUDIT_LHCI_RUNS="$WEB_AUDIT_LHCI_RUNS" \
  WEB_AUDIT_LHCI_CHROME_FLAGS="$WEB_AUDIT_LHCI_CHROME_FLAGS" \
  WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD="$WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD" \
  WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP="$WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP" \
    node <<'NODE' > "$target_dir/lighthouserc.json"
const config = {
  ci: {
    collect: {
      url: [process.env.TEST_URL],
      numberOfRuns: Number(process.env.WEB_AUDIT_LHCI_RUNS || 3),
      settings: {
        chromeFlags: process.env.WEB_AUDIT_LHCI_CHROME_FLAGS || '--headless=new --no-sandbox --disable-dev-shm-usage',
        maxWaitForLoad: Number(process.env.WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD || 45000),
        maxWaitForFcp: Number(process.env.WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP || 30000)
      }
    },
    upload: {
      target: 'filesystem',
      outputDir: './reports',
      reportFilenamePattern: '%%HOSTNAME%%-%%PATHNAME%%-%%DATETIME%%.report.%%EXTENSION%%'
    }
  }
};

process.stdout.write(`${JSON.stringify(config, null, 2)}\n`);
NODE
}

run_lighthouse_ci() {
  local target_dir="$REPORT_ROOT/lighthouse-ci"
  local log_file="$LOG_DIR/lighthouse-ci.log"

  install_node_if_missing
  install_chrome_if_missing
  install_lhci_if_missing

  install -d -m 0755 "$target_dir"
  write_lhci_config "$target_dir"

  log "Running Lighthouse CI for $TEST_URL"
  if ! (
    cd "$target_dir"
    timeout --foreground "$WEB_AUDIT_LHCI_TIMEOUT" "${LHCI_CMD[@]}" collect --config=lighthouserc.json
    timeout --foreground "$WEB_AUDIT_LHCI_TIMEOUT" "${LHCI_CMD[@]}" upload --config=lighthouserc.json
  ) 2>&1 | tee "$log_file"; then
    fail "Lighthouse CI failed or timed out after $WEB_AUDIT_LHCI_TIMEOUT. See log: $log_file"
  fi

  [[ -f "$target_dir/reports/manifest.json" ]] || fail "Lighthouse CI report manifest was not created: $target_dir/reports/manifest.json"
}

run_sitespeed() {
  local target_dir="$REPORT_ROOT/sitespeed"
  local log_file="$LOG_DIR/sitespeed.log"
  local extra_args=()

  install_docker_if_missing
  pull_sitespeed_image_if_missing

  install -d -m 0755 "$target_dir"
  SITESPEED_CONTAINER_NAME="web-audits-sitespeed-$RUN_ID"

  if [[ -n "$WEB_AUDIT_SITESPEED_EXTRA_ARGS" ]]; then
    # shellcheck disable=SC2206
    extra_args=($WEB_AUDIT_SITESPEED_EXTRA_ARGS)
  fi

  log "Running sitespeed.io for $TEST_URL"
  if ! timeout --foreground "$WEB_AUDIT_SITESPEED_TIMEOUT" "${DOCKER_CMD[@]}" run \
    --shm-size "$WEB_AUDIT_SITESPEED_DOCKER_SHM_SIZE" \
    --rm \
    --name "$SITESPEED_CONTAINER_NAME" \
    --label server-scripts.module=web-audits \
    --label server-scripts.tool=sitespeed \
    --label server-scripts.run-id="$RUN_ID" \
    -v "$target_dir:/sitespeed.io" \
    -v /etc/localtime:/etc/localtime:ro \
    "$WEB_AUDIT_SITESPEED_IMAGE" \
    -b "$WEB_AUDIT_SITESPEED_BROWSER" \
    -n "$WEB_AUDIT_SITESPEED_RUNS" \
    -c "$WEB_AUDIT_SITESPEED_CONNECTIVITY" \
    "${extra_args[@]}" \
    "$TEST_URL" 2>&1 | tee "$log_file"; then
    fail "sitespeed.io failed or timed out after $WEB_AUDIT_SITESPEED_TIMEOUT. See log: $log_file"
  fi

  SITESPEED_CONTAINER_NAME=""
  chown_reports_if_needed
}

create_zip_archive() {
  [[ "$WEB_AUDIT_CREATE_ZIP" == "true" ]] || return

  ARCHIVE_FILE="$WEB_AUDIT_RESULTS_DIR/$SITE_SLUG/$RUN_ID.zip"
  log "Creating zip archive: $ARCHIVE_FILE"
  (
    cd "$WEB_AUDIT_RESULTS_DIR/$SITE_SLUG"
    zip -qr "$RUN_ID.zip" "$RUN_ID"
  )
  chown_reports_if_needed
}

write_summary() {
  local summary_file="$REPORT_ROOT/summary.txt"
  local ssh_user_hint="${REPORT_OWNER:-root}"
  {
    printf 'URL: %s\n' "$TEST_URL"
    printf 'Test type: %s\n' "$TEST_TYPE"
    printf 'Run ID: %s\n' "$RUN_ID"
    printf 'Report directory: %s\n' "$REPORT_ROOT"
    if [[ -n "${ARCHIVE_FILE:-}" ]]; then
      printf 'Zip archive: %s\n' "$ARCHIVE_FILE"
    fi
    printf '\n'
    printf 'Download from Windows PowerShell:\n'
    printf 'scp %s@SERVER_IP:%s C:\\Users\\YOUR_USER\\Downloads\\\n' "$ssh_user_hint" "${ARCHIVE_FILE:-$REPORT_ROOT}"
    printf '\n'
    printf 'If SSH uses a custom port:\n'
    printf 'scp -P PORT %s@SERVER_IP:%s C:\\Users\\YOUR_USER\\Downloads\\\n' "$ssh_user_hint" "${ARCHIVE_FILE:-$REPORT_ROOT}"
  } > "$summary_file"
}

main() {
  trap cleanup EXIT INT TERM

  init_privileges
  load_env "$@"
  validate_env
  prompt_for_url
  prompt_for_test_type
  install_base_packages
  require_cmd jq
  require_cmd timeout
  prepare_report_dir
  write_metadata "running"

  case "$TEST_TYPE" in
    all)
      run_lighthouse_ci
      run_sitespeed
      ;;
    lighthouse)
      run_lighthouse_ci
      ;;
    sitespeed)
      run_sitespeed
      ;;
  esac

  write_metadata "complete"
  create_zip_archive
  write_summary

  log "Web audit complete"
  log "Report directory: $REPORT_ROOT"
  if [[ -n "${ARCHIVE_FILE:-}" ]]; then
    log "Zip archive: $ARCHIVE_FILE"
  fi
}

main "$@"

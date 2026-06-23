#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE_INPUT="${1:-}"
DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"
DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.list"
NODE_KEYRING="/etc/apt/keyrings/nodesource.gpg"
NODE_SOURCE_LIST="/etc/apt/sources.list.d/nodesource.list"
CHROME_KEYRING="/etc/apt/keyrings/google-chrome.gpg"
CHROME_SOURCE_LIST="/etc/apt/sources.list.d/google-chrome.list"

LOG_COLOR='\033[1;36m'
LOG_RESET='\033[0m'

timestamp() { date '+%F %T'; }
log_line() {
  local level="$1"
  shift
  printf '%b[%s] %-7s%b %s\n' "$LOG_COLOR" "$(timestamp)" "$level" "$LOG_RESET" "$*"
}

ok() { log_line "OK" "$*"; }
warn() { log_line "WARN" "$*"; }
err() { log_line "ERROR" "$*"; }
info() { log_line "INFO" "$*"; }
section() { echo; log_line "SECTION" "$*"; }
fail() { log_line "ERROR" "$*" >&2; exit 1; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Run as root: cd ~/server-scripts/web-audits && bash check-setup.sh"; }

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
  if [[ -n "$ENV_FILE_INPUT" ]]; then
    ENV_FILE="$(resolve_env_path "$ENV_FILE_INPUT")"
    return
  fi

  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    ENV_FILE="$SCRIPT_DIR/.env"
    return
  fi

  ENV_FILE=""
}

load_env() {
  resolve_env_file

  if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
    info "Loading environment from $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  elif [[ -n "$ENV_FILE" ]]; then
    warn "Environment file not found: $ENV_FILE"
  else
    info "Environment file is optional for this module; using defaults"
  fi

  WEB_AUDIT_RESULTS_DIR="$(absolute_module_path "${WEB_AUDIT_RESULTS_DIR:-reports}")"
  WEB_AUDIT_SITESPEED_IMAGE="${WEB_AUDIT_SITESPEED_IMAGE:-sitespeedio/sitespeed.io:41.3.3}"
}

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "Command found: $1"
  else
    err "Command not found: $1"
  fi
}

check_system() {
  section "Base system"
  check_cmd curl
  check_cmd jq
  check_cmd zip
  check_cmd tar
}

check_lighthouse_dependencies() {
  section "Lighthouse CI dependencies"
  check_cmd node
  check_cmd npm
  check_cmd lhci

  if command -v node >/dev/null 2>&1; then
    info "Node.js version: $(node --version)"
  fi
  if command -v npm >/dev/null 2>&1; then
    info "npm version: $(npm --version)"
  fi
  if command -v lhci >/dev/null 2>&1; then
    info "Lighthouse CI version: $(lhci --version)"
  fi

  if command -v google-chrome >/dev/null 2>&1; then
    ok "Google Chrome command found: google-chrome"
    info "$(google-chrome --version)"
  elif command -v google-chrome-stable >/dev/null 2>&1; then
    ok "Google Chrome command found: google-chrome-stable"
    info "$(google-chrome-stable --version)"
  else
    err "Google Chrome is not installed"
  fi

  [[ -f "$NODE_KEYRING" ]] && ok "NodeSource keyring is present" || warn "NodeSource keyring is missing: $NODE_KEYRING"
  [[ -f "$NODE_SOURCE_LIST" ]] && ok "NodeSource apt source is present" || warn "NodeSource apt source is missing: $NODE_SOURCE_LIST"
  [[ -f "$CHROME_KEYRING" ]] && ok "Google Chrome keyring is present" || warn "Google Chrome keyring is missing: $CHROME_KEYRING"
  [[ -f "$CHROME_SOURCE_LIST" ]] && ok "Google Chrome apt source is present" || warn "Google Chrome apt source is missing: $CHROME_SOURCE_LIST"
}

check_sitespeed_dependencies() {
  section "sitespeed.io dependencies"
  check_cmd docker

  if command -v docker >/dev/null 2>&1; then
    info "Docker version: $(docker --version)"
    if docker info >/dev/null 2>&1; then
      ok "Docker daemon is reachable"
    else
      err "Docker daemon is not reachable"
    fi

    if docker image inspect "$WEB_AUDIT_SITESPEED_IMAGE" >/dev/null 2>&1; then
      ok "sitespeed.io image is present: $WEB_AUDIT_SITESPEED_IMAGE"
    else
      warn "sitespeed.io image is not pulled yet: $WEB_AUDIT_SITESPEED_IMAGE"
    fi
  fi

  [[ -f "$DOCKER_KEYRING" ]] && ok "Docker keyring is present" || warn "Docker keyring is missing: $DOCKER_KEYRING"
  [[ -f "$DOCKER_SOURCE_LIST" ]] && ok "Docker apt source is present" || warn "Docker apt source is missing: $DOCKER_SOURCE_LIST"
}

check_reports() {
  section "Reports"
  if [[ -d "$WEB_AUDIT_RESULTS_DIR" ]]; then
    ok "Reports directory exists: $WEB_AUDIT_RESULTS_DIR"
    info "Recent report archives:"
    find "$WEB_AUDIT_RESULTS_DIR" -type f -name '*.zip' -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort -r | head -n 10 || true
  else
    warn "Reports directory does not exist yet: $WEB_AUDIT_RESULTS_DIR"
  fi
}

main() {
  require_root
  load_env
  check_system
  check_lighthouse_dependencies
  check_sitespeed_dependencies
  check_reports
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: reinstall_codex_plugin.sh [options]

Refresh the installed Codex plugin from the source repository and seed the
matching versioned cache directory.

Options:
  --dry-run                   Print planned actions without writing anything.
  --plugin-root PATH          Plugin repository root. Default: inferred from script location.
  --codex-home PATH           Codex home directory. Default: $HOME/.codex
  --cache-namespace NAME      Override cache namespace. Default: auto-detect from config.toml,
                              fallback to personal-local-plugins.
  --skip-cache                Refresh the installed plugin only.
  --help                      Show this help.
EOF
}

log() {
  printf '[reinstall-codex-plugin] %s\n' "$*"
}

fail() {
  printf '[reinstall-codex-plugin] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

PLUGIN_ROOT=""
CODEX_HOME="${HOME}/.codex"
CACHE_NAMESPACE=""
DRY_RUN=0
SKIP_CACHE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --plugin-root)
      [[ $# -ge 2 ]] || fail "--plugin-root requires a value"
      PLUGIN_ROOT="$2"
      shift 2
      ;;
    --codex-home)
      [[ $# -ge 2 ]] || fail "--codex-home requires a value"
      CODEX_HOME="$2"
      shift 2
      ;;
    --cache-namespace)
      [[ $# -ge 2 ]] || fail "--cache-namespace requires a value"
      CACHE_NAMESPACE="$2"
      shift 2
      ;;
    --skip-cache)
      SKIP_CACHE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ -z "${PLUGIN_ROOT}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
  PLUGIN_ROOT="$(cd "${PLUGIN_ROOT}" && pwd)"
fi

require_cmd rsync
require_cmd python3

MANIFEST_PATH="${PLUGIN_ROOT}/.codex-plugin/plugin.json"
[[ -f "${MANIFEST_PATH}" ]] || fail "missing manifest: ${MANIFEST_PATH}"

read_manifest_field() {
  local field="$1"
  python3 - "$MANIFEST_PATH" "$field" <<'PY'
import json
import sys

manifest_path, field = sys.argv[1], sys.argv[2]
with open(manifest_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
value = data.get(field)
if not isinstance(value, str) or not value:
    raise SystemExit(f"missing or invalid manifest field: {field}")
print(value)
PY
}

read_optional_manifest_field() {
  local field="$1"
  python3 - "$MANIFEST_PATH" "$field" <<'PY'
import json
import sys

manifest_path, field = sys.argv[1], sys.argv[2]
with open(manifest_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
value = data.get(field)
if isinstance(value, str) and value:
    print(value)
PY
}

PLUGIN_NAME="$(read_manifest_field name)"
PLUGIN_VERSION="$(read_manifest_field version)"
MCP_CONFIG_REL="$(read_optional_manifest_field mcpServers || true)"

detect_cache_namespace() {
  local config_path="${CODEX_HOME}/config.toml"
  local line namespace
  [[ -f "${config_path}" ]] || return 1
  line="$(grep -F "[plugins.\"${PLUGIN_NAME}@" "${config_path}" | head -n 1 || true)"
  [[ -n "${line}" ]] || return 1
  namespace="${line#*@}"
  namespace="${namespace%%\"*}"
  [[ -n "${namespace}" ]] || return 1
  printf '%s\n' "${namespace}"
}

if [[ -z "${CACHE_NAMESPACE}" ]]; then
  CACHE_NAMESPACE="$(detect_cache_namespace || true)"
fi
if [[ -z "${CACHE_NAMESPACE}" ]]; then
  CACHE_NAMESPACE="personal-local-plugins"
fi

CODEX_PLUGIN_DIR="${CODEX_HOME}/plugins/${PLUGIN_NAME}"
CACHE_VERSION_DIR="${CODEX_HOME}/plugins/cache/${CACHE_NAMESPACE}/${PLUGIN_NAME}/${PLUGIN_VERSION}"

validate_skill_frontmatter() {
  local file first_line found=0 invalid=0
  while IFS= read -r -d '' file; do
    found=1
    first_line="$(head -n 1 "${file}" || true)"
    if [[ "${first_line}" != "---" ]]; then
      log "invalid frontmatter: ${file}"
      invalid=1
    fi
  done < <(
    find "${PLUGIN_ROOT}" \
      \( -path "${PLUGIN_ROOT}/.git" -o -path "${PLUGIN_ROOT}/.codex" -o -path "${PLUGIN_ROOT}/scripts" \) -prune \
      -o -type f -name 'SKILL.md' -print0 | sort -z
  )

  [[ "${found}" -eq 1 ]] || fail "no SKILL.md files found under ${PLUGIN_ROOT}"
  [[ "${invalid}" -eq 0 ]] || fail "skill validation failed"
}

validate_mcp_config() {
  local mcp_path
  [[ -n "${MCP_CONFIG_REL}" ]] || return 0
  mcp_path="${PLUGIN_ROOT}/${MCP_CONFIG_REL#./}"
  [[ -f "${mcp_path}" ]] || fail "missing MCP config: ${mcp_path}"
  python3 - "${mcp_path}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    json.load(fh)
PY
}

run_cmd() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

log "plugin root: ${PLUGIN_ROOT}"
log "codex home: ${CODEX_HOME}"
log "plugin name: ${PLUGIN_NAME}"
log "plugin version: ${PLUGIN_VERSION}"
log "cache namespace: ${CACHE_NAMESPACE}"
log "installed plugin dir: ${CODEX_PLUGIN_DIR}"
if [[ "${SKIP_CACHE}" -eq 0 ]]; then
  log "cache version dir: ${CACHE_VERSION_DIR}"
fi

validate_skill_frontmatter
validate_mcp_config

run_cmd mkdir -p "${CODEX_PLUGIN_DIR}"
run_cmd rsync -a --exclude '.git' --exclude '.codex' --exclude '__pycache__' "${PLUGIN_ROOT}/" "${CODEX_PLUGIN_DIR}/"

if [[ "${SKIP_CACHE}" -eq 0 ]]; then
  run_cmd mkdir -p "${CACHE_VERSION_DIR}"
  run_cmd rsync -a --exclude '.git' --exclude '.codex' --exclude '__pycache__' "${PLUGIN_ROOT}/" "${CACHE_VERSION_DIR}/"
fi

log "refresh complete"

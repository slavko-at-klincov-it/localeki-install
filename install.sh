#!/usr/bin/env bash
set -euo pipefail

REPO="${LOKALEKI_GITHUB_REPO:-slavko-at-klincov-it/MasterKI-CrossPlatformIT-runtime}"
RELEASE_TAG="${LOKALEKI_RELEASE_TAG:-v0.3.0}"
PACKAGE_NAME="${LOKALEKI_PACKAGE_NAME:-localeki-customer-package-0.3.0.tgz}"
INSTALL_ROOT="${LOKALEKI_INSTALL_ROOT:-$HOME/LokaleKI}"
INSTALLER_ROOT="${LOKALEKI_INSTALLER_ROOT:-$INSTALL_ROOT/installer}"
ASSET_URL="${LOKALEKI_RELEASE_ASSET_URL:-https://api.github.com/repos/slavko-at-klincov-it/MasterKI-CrossPlatformIT-runtime/releases/assets/433885233}"
EXPECTED_SHA256="${LOKALEKI_PACKAGE_SHA256:-b50baa58cd0ed1be8fe530b1e91b58bcd35b5000ad8a256a20b205d60e508408}"
TOKEN="${LOKALEKI_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"

log() { printf '[lokaleki-install] %s\n' "$*"; }
fail() { printf '[lokaleki-install][error] %s\n' "$*" >&2; exit 1; }

has_interactive_tty() {
  [ -r /dev/tty ] && [ -w /dev/tty ] && command -v stty >/dev/null 2>&1 && (stty -a < /dev/tty) >/dev/null 2>&1
}

usage() {
  cat <<'USAGE'
LokaleKI quick installer

Customer Mac mini:
  curl -fsSL https://raw.githubusercontent.com/slavko-at-klincov-it/localeki-install/main/install.sh | bash

Optional non-interactive token:
  GITHUB_TOKEN=<token> bash -c "$(curl -fsSL https://raw.githubusercontent.com/slavko-at-klincov-it/localeki-install/main/install.sh)"

Environment overrides:
  LOKALEKI_GITHUB_REPO=owner/repo
  LOKALEKI_RELEASE_TAG=v0.3.0
  LOKALEKI_PACKAGE_NAME=localeki-customer-package-0.3.0.tgz
  LOKALEKI_INSTALL_ROOT=$HOME/LokaleKI
  LOKALEKI_RELEASE_ASSET_URL=https://api.github.com/repos/owner/repo/releases/assets/123
  LOKALEKI_PACKAGE_SHA256=<sha256>

The installer keeps everything under ~/LokaleKI:
  ~/LokaleKI/installer
  ~/LokaleKI/commissioning
  ~/LokaleKI/reports
  ~/LokaleKI/secrets
  ~/LokaleKI/docker-data
USAGE
}

auth_args() {
  if [ -n "$TOKEN" ]; then
    printf '%s\n' "-H"
    printf '%s\n' "Authorization: Bearer $TOKEN"
  fi
}

curl_json() {
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$1"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "$1"
  fi
}

curl_asset() {
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream" -o "$2" "$1"
  else
    curl -fsSL -H "Accept: application/octet-stream" -o "$2" "$1"
  fi
}

prompt_token_if_needed() {
  if [ -n "$TOKEN" ]; then
    return 0
  fi
  if ! has_interactive_tty; then
    fail "GitHub token required. Run from an interactive terminal or set GITHUB_TOKEN."
  fi
  { printf 'GitHub token (leer lassen, wenn das Release public ist): ' > /dev/tty; } 2>/dev/null || fail "GitHub token required. Run from an interactive terminal or set GITHUB_TOKEN."
  if command -v stty >/dev/null 2>&1; then (stty -echo < /dev/tty) >/dev/null 2>&1 || true; fi
  if ! TOKEN="$( { IFS= read -r token_line < /dev/tty && printf '%s' "$token_line"; } 2>/dev/null )"; then
    if command -v stty >/dev/null 2>&1; then (stty echo < /dev/tty) >/dev/null 2>&1 || true; fi
    printf '\n' >&2
    fail "GitHub token required. Run from an interactive terminal or set GITHUB_TOKEN."
  fi
  if command -v stty >/dev/null 2>&1; then (stty echo < /dev/tty) >/dev/null 2>&1 || true; fi
  { printf '\n' > /dev/tty; } 2>/dev/null || true
}

extract_asset_url_from_release_json() {
  awk -v target="$PACKAGE_NAME" '
    $0 ~ "\"name\"[[:space:]]*:[[:space:]]*\"" target "\"" {
      url=$0
      sub(/^.*"url"[[:space:]]*:[[:space:]]*"/, "", url)
      sub(/".*$/, "", url)
      if (url ~ /^https:\/\/api.github.com\/repos\/.*\/releases\/assets\//) print url
      digest=$0
      if (digest ~ /"digest"[[:space:]]*:[[:space:]]*"sha256:/) {
        sub(/^.*"digest"[[:space:]]*:[[:space:]]*"sha256:/, "", digest)
        sub(/".*$/, "", digest)
        print "sha256:" digest
      }
      exit
    }
  ' RS='},' "$1"
}

resolve_release_asset() {
  local release_json resolved first second
  if [ -n "$ASSET_URL" ]; then
    return 0
  fi
  release_json="$INSTALLER_ROOT/release-${RELEASE_TAG}.json"
  log "resolving release asset $REPO@$RELEASE_TAG"
  curl_json "https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG" > "$release_json"
  resolved="$(extract_asset_url_from_release_json "$release_json")"
  first="$(printf '%s\n' "$resolved" | sed -n '1p')"
  second="$(printf '%s\n' "$resolved" | sed -n '2p')"
  [ -n "$first" ] || fail "release asset not found: $PACKAGE_NAME"
  ASSET_URL="$first"
  if [ -z "$EXPECTED_SHA256" ] && [ "${second#sha256:}" != "$second" ]; then
    EXPECTED_SHA256="${second#sha256:}"
  fi
}

verify_sha256() {
  local file="$1"
  [ -n "$EXPECTED_SHA256" ] || fail "missing SHA256 for $PACKAGE_NAME; set LOKALEKI_PACKAGE_SHA256 or use a GitHub release with asset digest"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s  %s\n' "$EXPECTED_SHA256" "$file" | shasum -a 256 -c -
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$EXPECTED_SHA256" "$file" | sha256sum -c -
  else
    fail "need shasum or sha256sum to verify package"
  fi
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  umask 077
  command -v curl >/dev/null 2>&1 || fail "curl is required"
  command -v tar >/dev/null 2>&1 || fail "tar is required"
  mkdir -p "$INSTALLER_ROOT"

  prompt_token_if_needed
  resolve_release_asset

  cd "$INSTALLER_ROOT"
  log "using installer root $INSTALLER_ROOT"
  log "downloading $PACKAGE_NAME"
  curl_asset "$ASSET_URL" "$PACKAGE_NAME"
  verify_sha256 "$PACKAGE_NAME"

  rm -rf "${PACKAGE_NAME%.tgz}"
  tar -xzf "$PACKAGE_NAME"
  cd "${PACKAGE_NAME%.tgz}"
  log "starting customer launcher"
  ./lokale-ki-setup "$@"
}

main "$@"

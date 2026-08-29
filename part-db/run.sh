#!/usr/bin/env bash
# Home Assistant add-on launcher for the official Part-DB image.
# Reads /data/options.json, exports Part-DB env vars, persists data to /config
# (the app_config mount), then execs the upstream entrypoint.
#
# Persistent data lives under /config (the app_config folder) and NOT under
# /data: Home Assistant always deletes an app's /data on uninstall, but the
# app_config folder is preserved unless the user ticks "Also remove app data".
set -euo pipefail

OPTIONS=/data/options.json
DATA=/config

log() { echo "[part-db] $*"; }

# Read a string option (empty string if unset/null).
get() { jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"; }

# Read a boolean option as 1/0 (Part-DB expects 1/0 for several flags).
getbool01() {
  [ "$(jq -r --arg k "$1" '.[$k] // false' "$OPTIONS")" = "true" ] && echo 1 || echo 0
}

# Export NAME=VALUE only when VALUE is non-empty, so we never clobber an
# image default with a blank string.
setenv() { [ -n "${2:-}" ] && export "$1=$2" || true; }

# Move a Part-DB data directory onto the persistent /data volume and symlink
# it back. Seeds the persistent copy from the image on first run.
#
# The FrankenPHP image runs Part-DB from /app, so the real data lives in
# /app/uploads and /app/public/media (the /var/www/html/* VOLUMEs the image
# still declares are vestigial and unused). These /app paths are plain
# directories, so a symlink is enough and no bind mount / elevated privilege
# is required.
persist() {
  local target="$1" link="$2"
  mkdir -p "$target"
  if [ -d "$link" ] && [ ! -L "$link" ]; then
    if [ -z "$(ls -A "$target" 2>/dev/null)" ] && [ -n "$(ls -A "$link" 2>/dev/null)" ]; then
      cp -a "$link/." "$target/"
    fi
    rm -rf "$link"
  fi
  ln -sfn "$target" "$link"
}

# uploads/ holds attachments and (by default) the SQLite database (app.db).
persist "$DATA/uploads" /app/uploads
# public/media holds generated thumbnails and public media.
persist "$DATA/media"   /app/public/media

# --- Map add-on options to Part-DB environment variables ---
setenv DEFAULT_LANG                "$(get default_lang)"
setenv DEFAULT_TIMEZONE            "$(get default_timezone)"
setenv BASE_CURRENCY              "$(get base_currency)"
setenv INSTANCE_NAME             "$(get instance_name)"
setenv MAX_ATTACHMENT_FILE_SIZE "$(get max_attachment_file_size)"
setenv TRUSTED_PROXIES          "$(get trusted_proxies)"
setenv TRUSTED_HOSTS            "$(get trusted_hosts)"
export ALLOW_ATTACHMENT_DOWNLOADS="$(getbool01 allow_attachment_downloads)"
# Update check is not exposed as an option; always disable it.
export CHECK_FOR_UPDATES=0

# DB_AUTOMIGRATE must be the literal "true" to trigger the upstream migration.
[ "$(getbool01 db_automigrate)" = "1" ] && export DB_AUTOMIGRATE=true

# Optional external database. When empty, keep the image default
# (SQLite at uploads/app.db, which is persisted via ${DATA}/uploads).
setenv DATABASE_URL "$(get database_url)"

# Custom Environment Variables
ENV_VARS_COUNT=$(jq -r '(.env_vars // []) | length' "$OPTIONS")
if [ "$ENV_VARS_COUNT" -gt 0 ]; then
  log "Exporting custom environment variables..."
  for i in $(seq 0 $((ENV_VARS_COUNT - 1))); do
    ENV_NAME=$(jq -r ".env_vars[$i].name // empty" "$OPTIONS")
    ENV_VALUE=$(jq -r ".env_vars[$i].value // empty" "$OPTIONS")
    if [ -n "$ENV_NAME" ]; then
      export "$ENV_NAME=$ENV_VALUE"
    fi
  done
fi

# Header Authentication options
export HEADER_AUTH_ENABLED="$(getbool01 header_auth_enabled)"
export HEADER_AUTH_AUTO_CREATE="$(getbool01 header_auth_auto_create)"
export HEADER_AUTH_DISABLE_PASSWORD_EXPIRATION="$(getbool01 header_auth_disable_password_expiration)"
setenv HEADER_AUTH_HEADER_NAME "$(get header_auth_header_name)"
setenv HEADER_AUTH_DEFAULT_GROUP "$(get header_auth_default_group)"

# APP_SECRET: Symfony uses it for CSRF tokens, signed URLs and remember-me
# cookies. The image ships a well-known default, so generate a unique value on
# first start and persist it on /config. Keeping it stable across restarts and
# updates avoids invalidating sessions and signed URLs; a per-build value (e.g.
# generated in the Dockerfile) would change on every add-on update.
SECRET_FILE="$DATA/app_secret"
if [ ! -s "$SECRET_FILE" ]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
  log "Generated a new APP_SECRET (stored at ${SECRET_FILE})"
fi
export APP_SECRET="$(cat "$SECRET_FILE")"

# Make Caddy serve plain HTTP on port 80 (mapped to the host by config.yaml).
# The image default SERVER_NAME=localhost would enable auto-HTTPS and bind only
# to localhost, which is unreachable from the Home Assistant host.
export SERVER_NAME=:80

# The image sets XDG_CONFIG_HOME=/config, which is now the persistent
# app_config mount. Redirect Caddy's own config state to the ephemeral /data
# volume so it does not clutter (or leak into) Part-DB's persistent data.
export XDG_CONFIG_HOME=/data/caddy-config

# Home Assistant Ingress support. HA embeds the UI in an iframe and proxies it
# under a random base path, passing that path in the X-Ingress-Path header.
#   1. Copy X-Ingress-Path into X-Forwarded-Prefix so Symfony (which trusts that
#      header from TRUSTED_PROXIES, and the HA range is covered by the default)
#      generates all URLs/assets under the Ingress base path. Empty for direct
#      port access, so normal root serving is unaffected.
#   2. Strip Part-DB's X-Frame-Options: SAMEORIGIN, which would otherwise block
#      the Ingress iframe. HA fronts authentication for Ingress traffic.
export CADDY_SERVER_EXTRA_DIRECTIVES='request_header X-Forwarded-Prefix {http.request.header.X-Ingress-Path}
header -X-Frame-Options'

log "Starting Part-DB (lang=${DEFAULT_LANG:-} tz=${DEFAULT_TIMEZONE:-} currency=${BASE_CURRENCY:-} db=${DATABASE_URL:-sqlite})"

# Hand over to Part-DB's own FrankenPHP entrypoint (installs deps, runs
# migrations, fixes permissions) and the frankenphp server it runs as CMD.
cd /app
exec /usr/local/bin/docker-entrypoint frankenphp run --config /etc/caddy/Caddyfile

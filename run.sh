#!/usr/bin/with-contenv bashio
# EverRise Auto Updater — polls the backend bridge repo on GitHub on a
# schedule and deploys whatever's new, straight from inside the client's own
# box. This container pulls FROM GitHub outward, so unlike the provisioner
# tool's own "Add more" push, there's no dependency on Hakim's Mac (or
# Tailscale) being reachable for an update to land — the only requirement
# is this box's own normal internet access, same as any other add-on
# already needs.
#
# Backend only, as of this version — the everrise_dashboard custom
# component's real source repo needs its custom_components/<domain>/
# subtree extracted specifically (same convention the provisioner's own
# customComponentInstaller.js uses for the initial install, so both
# mechanisms treat this repo identically), and needs one Core restart
# afterward, since Core only scans custom_components/ at startup.
#
# Frontend deploys used to run from here too (a straight rsync into
# www/<folder>/ on the same POLL_INTERVAL, no restart needed). Removed
# because the bridge integration itself now ships its own frontend Update
# entity (update.dashboard_frontend, see update.py in the bridge repo) that
# polls every 15 minutes — much tighter than this add-on's hourly default —
# and having both meant every frontend build was being fetched twice on two
# independent schedules for no benefit. The bridge's own entity is now the
# single frontend update path; this add-on only ever touches the backend.
#
# frontend_repo/frontend_folder are kept in config.yaml's schema (unused
# here) purely so existing clients whose options already set them don't hit
# a schema-validation error on upgrade — bashio::config still reads them
# below for the same reason, they're just never acted on.
#
# [CONFIRMED via developers.home-assistant.io/docs/apps/communication]
# SUPERVISOR_TOKEN is injected into every add-on's environment automatically
# — no credential ever needs to be configured here for the restart call.
set -euo pipefail

FRONTEND_REPO=$(bashio::config 'frontend_repo')       # unused — see header comment
FRONTEND_FOLDER=$(bashio::config 'frontend_folder')    # unused — see header comment
BACKEND_REPO=$(bashio::config 'backend_repo')
BACKEND_DOMAIN=$(bashio::config 'backend_domain')
POLL_INTERVAL=$(bashio::config 'poll_interval_seconds')

# /data is every add-on's own persistent storage, provided automatically —
# no map: entry needed for it. Used here just to remember the last commit
# hash actually deployed for each repo, so an unchanged repo is a no-op
# instead of a needless re-copy (and, for the backend, a needless restart)
# every single poll.
STATE_DIR=/data
# [CONFIRMED via developers.home-assistant.io/docs/apps/configuration,
# and the official Configurator add-on's own config.yaml] homeassistant_config
# mounts HA's real config folder at /homeassistant inside the container —
# NOT /config, which is reserved for an add-on's own private settings.
HA_CONFIG=/homeassistant

restart_core() {
  bashio::log.info "Restarting Home Assistant Core to load new ${BACKEND_DOMAIN} code..."
  curl -sf -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    http://supervisor/core/api/services/homeassistant/restart >/dev/null 2>&1 || true

  local waited=0
  local status
  while [ "$waited" -lt 120 ]; do
    sleep 3
    waited=$((waited + 3))
    status=$(curl -s -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
      http://supervisor/core/api/ 2>/dev/null || echo "000")
    if [ "$status" = "200" ] || [ "$status" = "401" ]; then
      bashio::log.info "Restart confirmed — Home Assistant Core is back up."
      return
    fi
  done
  bashio::log.warning "Home Assistant didn't answer again within 120s of the restart call — check Settings > System > Restart by hand if the new ${BACKEND_DOMAIN} code doesn't seem to have taken effect."
}

# $1 name (for logging)   $2 repo URL   $3 marker file   $4 destination dir
# $5 subfolder to extract from the clone (empty = repo root itself)
# $6 "true"/"false" — restart Core after deploying
check_and_pull() {
  local name="$1" repo_url="$2" marker_file="$3" dest_dir="$4" subfolder="$5" needs_restart="$6"

  local tmp_dir
  tmp_dir=$(mktemp -d)
  if ! git clone --depth 1 --quiet "$repo_url" "$tmp_dir" 2>/tmp/everrise-clone-err; then
    bashio::log.warning "${name}: couldn't reach ${repo_url} — $(cat /tmp/everrise-clone-err 2>/dev/null || echo 'unknown error'). Will retry next cycle."
    rm -rf "$tmp_dir"
    return
  fi

  local latest_commit
  latest_commit=$(git -C "$tmp_dir" rev-parse HEAD)
  local last_commit=""
  [ -f "$marker_file" ] && last_commit=$(cat "$marker_file")

  if [ "$latest_commit" = "$last_commit" ]; then
    bashio::log.debug "${name}: already up to date (${latest_commit:0:8})."
    rm -rf "$tmp_dir"
    return
  fi

  local source_dir="$tmp_dir"
  [ -n "$subfolder" ] && source_dir="${tmp_dir}/${subfolder}"

  if [ ! -d "$source_dir" ]; then
    bashio::log.warning "${name}: expected \"${subfolder:-repo root}\" in ${repo_url} but it wasn't there — skipping this cycle, will try again next time in case this was transient."
    rm -rf "$tmp_dir"
    return
  fi

  bashio::log.info "${name}: new version found (${latest_commit:0:8}, was ${last_commit:-none}) — deploying to ${dest_dir}"
  mkdir -p "$dest_dir"
  rsync -a --delete "${source_dir}/" "${dest_dir}/"
  echo "$latest_commit" > "$marker_file"
  bashio::log.info "${name}: deployed ${latest_commit:0:8}"

  if [ "$needs_restart" = "true" ]; then
    restart_core
  fi

  rm -rf "$tmp_dir"
}

bashio::log.info "EverRise Auto Updater starting — checking the backend bridge every ${POLL_INTERVAL}s (frontend updates are now handled by the bridge's own Update entity, not this add-on)"

while true; do
  check_and_pull "Dashboard bridge (backend)" \
    "$BACKEND_REPO" \
    "${STATE_DIR}/backend-commit" \
    "${HA_CONFIG}/custom_components/${BACKEND_DOMAIN}" \
    "custom_components/${BACKEND_DOMAIN}" \
    "true"

  sleep "$POLL_INTERVAL"
done
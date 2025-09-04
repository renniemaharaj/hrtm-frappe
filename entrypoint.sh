#!/bin/bash
set -Eeuo pipefail

# ==========================================
# Frappe Entrypoint
# - Reads instance.json for deployment, branch, apps, sites
# - Reads common_site_config.json for Redis and other knobs
# - Initializes bench, ensures apps, aligns site apps to config
# - Switches between development (bench start) and production (supervisor+nginx)
# ==========================================

echo "[ENTRYPOINT] $(date '+%Y-%m-%d %H:%M:%S.%3N') PID: $$ (PPID: $PPID)"

# ---------------------------
# Paths
# ---------------------------
FRAPPE_HOME=${FRAPPE_HOME:-/home/frappe}
INSTANCE_JSON_SOURCE=${INSTANCE_JSON_SOURCE:-/instance.json}
COMMON_CONFIG_SOURCE=${COMMON_CONFIG_SOURCE:-/common_site_config.json}
BENCH_NAME_DEFAULT=${frappe_bench:-frappe-bench}
MERGED_SUPERVISOR_CONF="/supervisor-merged.conf"
WRAPPER_CONF="/supervisor.conf"

cd "$FRAPPE_HOME"

# ---------------------------
# Helpers
# ---------------------------
require() {
  command -v "$1" >/dev/null 2>&1 || { echo "[FATAL] Missing required command: $1"; exit 1; }
}

json_get() { # json_get <file> <jq_expr> [default]
  local file=$1; shift
  local expr=$1; shift
  local def=${1-}
  if [ ! -f "$file" ]; then
    echo "$def"; return 0
  fi
  local out
  if ! out=$(jq -r "$expr // empty" "$file" 2>/dev/null); then
    echo "$def"; return 0
  fi
  if [ -z "$out" ]; then echo "$def"; else echo "$out"; fi
}

read_apps_array() { # read_apps_array <file> <jq_expr> -> outputs lines
  local file=$1; local expr=$2
  jq -r "$expr // [] | .[]?" "$file" 2>/dev/null || true
}

parse_redis_host() { # parse_redis_host <redis://host:port>
  echo "$1" | sed -E 's|redis://([^:/]+):?.*|\1|'
}

parse_redis_port() { # parse_redis_port <redis://host:port>
  echo "$1" | sed -E 's|redis://[^:]+:([0-9]+).*|\1|'
}

# ---------------------------
# Requirements
# ---------------------------
require jq
require bench
require mysqladmin
require redis-cli
require sudo

# ---------------------------
# Load configuration (instance.json)
# ---------------------------
if [ ! -f "$INSTANCE_JSON_SOURCE" ]; then
  echo "[FATAL] $INSTANCE_JSON_SOURCE not found."; exit 1
fi

echo "[INFO] Loading instance.json..."
DEPLOYMENT=$(json_get "$INSTANCE_JSON_SOURCE" '.deployment' 'development')
FRAPPE_BRANCH=$(json_get "$INSTANCE_JSON_SOURCE" '.frappe_branch' 'develop')
BENCH_DIR="$FRAPPE_HOME/$(json_get "$INSTANCE_JSON_SOURCE" '.frappe_bench' "$BENCH_NAME_DEFAULT")"

# ---------------------------
# Load service knobs (common_site_config.json) for Redis only
# ---------------------------
if [ ! -f "$COMMON_CONFIG_SOURCE" ]; then
  echo "[FATAL] $COMMON_CONFIG_SOURCE not found."; exit 1
fi

echo "[INFO] Loading common_site_config.json..."
REDIS_QUEUE=$(json_get "$COMMON_CONFIG_SOURCE" '.redis_queue' 'redis://redis-queue:6379')
REDIS_CACHE=$(json_get "$COMMON_CONFIG_SOURCE" '.redis_cache' 'redis://redis-cache:6379')
REDIS_SOCKETIO=$(json_get "$COMMON_CONFIG_SOURCE" '.redis_socketio' 'redis://redis-socketio:6379')

# ---------------------------
# MariaDB credentials from environment
# ---------------------------
DB_ROOT_USERNAME=${MARIADB_ROOT_USERNAME:-root}
DB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-root}
DB_USER=${MARIADB_USER:-frappe}
DB_PASSWORD=${MARIADB_PASSWORD:-frappe}
DB_NAME=${MARIADB_DATABASE:-frappe}
DB_HOST=${MARIADB_HOST:-mariadb}
DB_PORT=${MARIADB_PORT:-3306}

# Debug toggles
WAIT_FOR_DB=${WAIT_FOR_DB:-1}
WAIT_FOR_REDIS=${WAIT_FOR_REDIS:-1}
DB_DEBUG=${DB_DEBUG:-0}
REDIS_DEBUG=${REDIS_DEBUG:-0}

# ---------------------------
# Ownership
# ---------------------------
sudo chown -R frappe:frappe "$FRAPPE_HOME"

# ---------------------------
# Service waits
# ---------------------------
if [ "$WAIT_FOR_DB" = "1" ]; then
  echo "[WAIT] MariaDB at ${DB_HOST}:${DB_PORT}..."
  until mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USERNAME" -p"$DB_ROOT_PASSWORD" --silent; do
    sleep 2
    [ "$DB_DEBUG" = "1" ] && echo "[DEBUG][DB] waiting..."
  done
  echo "[OK] MariaDB reachable."
fi

if [ "$WAIT_FOR_REDIS" = "1" ]; then
  for R in "$REDIS_QUEUE" "$REDIS_CACHE" "$REDIS_SOCKETIO"; do
    host=$(parse_redis_host "$R")
    port=$(parse_redis_port "$R")
    echo "[WAIT] Redis at ${host}:${port}..."
    until redis-cli -h "$host" -p "$port" ping >/dev/null 2>&1; do
      sleep 2
      [ "$REDIS_DEBUG" = "1" ] && echo "[DEBUG][REDIS $host:$port] waiting..."
    done
    echo "[OK] Redis ${host}:${port} reachable."
  done
fi

# ---------------------------
# Initialize bench
# ---------------------------
if [ ! -d "$BENCH_DIR" ]; then
  echo "[INIT] bench init --frappe-branch $FRAPPE_BRANCH $BENCH_DIR"
  bench init --frappe-branch "$FRAPPE_BRANCH" "$BENCH_DIR"
fi
cd "$BENCH_DIR"

# Ensure sites dir exists
mkdir -p "$BENCH_DIR/sites"

# Copy common config into bench (source of truth is outside)
COMMON_CONFIG_DEST="$BENCH_DIR/sites/common_site_config.json"
cp "$COMMON_CONFIG_SOURCE" "$COMMON_CONFIG_DEST"
sudo chown frappe:frappe "$COMMON_CONFIG_DEST"

# ---------------------------
# Sites management
# ---------------------------
echo "[SITES] Syncing sites with instance.json..."

# Initialize sites array (empty by default)
INSTANCE_SITES=()
mapfile -t INSTANCE_SITES < <(jq -r '.instance_sites[].site_name // empty' "$INSTANCE_JSON_SOURCE")

# Build a map of site -> apps only if we have sites
declare -A SITE_APPS
if [ ${#INSTANCE_SITES[@]} -gt 0 ]; then
    for site in "${INSTANCE_SITES[@]}"; do
        apps=$(jq -r --arg s "$site" '.instance_sites[] | select(.site_name==$s) | .preloaded_apps[]?' "$INSTANCE_JSON_SOURCE")
        SITE_APPS["$site"]="$apps"
    done
fi

# Collect current sites based on real directories with site_config.json
CURRENT_SITES=()
for dir in sites/*; do
    if [ -d "$dir" ] && [ -f "$dir/site_config.json" ]; then
        CURRENT_SITES+=("$(basename "$dir")")
    fi
done

# Get drop toggle from instance.json (default false)
DROP_ABANDONED_SITES=$(json_get "$INSTANCE_JSON_SOURCE" '.drop_abandoned_sites' 'false')

# Drop sites not in instance.json (only if enabled)
if [[ "$DROP_ABANDONED_SITES" == "true" ]]; then
    for site in "${CURRENT_SITES[@]}"; do
        if [[ ! " ${INSTANCE_SITES[*]} " =~ " $site " ]]; then
            echo "[SITE] Dropping unlisted site: $site"
            bench drop-site "$site" --force --root-password "$DB_ROOT_PASSWORD" || echo "[WARN] Failed to drop $site"
        fi
    done
else
    echo "[SITE] Skipping drop of abandoned sites (drop_abandoned_sites=false)"
fi

# Ensure and align each site
for site in "${INSTANCE_SITES[@]}"; do
  echo "[SITE] Processing: $site"

  # Create if missing
  if [ ! -d "sites/$site" ]; then
    echo "[SITE] Creating: $site"
    bench new-site "$site" \
      --db-root-username "$DB_ROOT_USERNAME" \
      --db-root-password "$DB_ROOT_PASSWORD" \
      --admin-password admin
  fi

  # Ensure apps exist in bench/apps (skip frappe)
  for app in ${SITE_APPS[$site]}; do
    if [ "$app" = "frappe" ]; then continue; fi
    if [ ! -d "apps/$app" ]; then
      echo "[APP] Fetching missing app: $app (branch: $FRAPPE_BRANCH)"
      bench get-app "$app" --branch "$FRAPPE_BRANCH" || \
        echo "[WARN] Failed to fetch $app"
    fi
  done

  # Align site apps
  echo "[APPS] Aligning apps for site: $site"
  current_apps=$(bench --site "$site" list-apps | awk '{print $1}' | sed '/^$/d')
  expected_apps=$(printf '%s\n' ${SITE_APPS[$site]} | sort -u)
  current_sorted=$(printf '%s\n' $current_apps | sort -u)

  # Install missing apps
  missing=$(comm -23 <(echo "$expected_apps") <(echo "$current_sorted"))
  if [ -n "$missing" ]; then
    echo "[APPS] Installing missing apps: $(echo "$missing" | xargs)"
    for app in $missing; do
      [ "$app" = "frappe" ] && continue
      bench --site "$site" install-app "$app" || echo "[WARN] Failed to install $app"
    done
  fi

  # Uninstall extras
  extras=$(comm -13 <(echo "$expected_apps") <(echo "$current_sorted") | grep -vx "frappe" || true)
  if [ -n "$extras" ]; then
    echo "[APPS] Uninstalling extra apps: $(echo "$extras" | xargs)"
    for app in $extras; do
      bench --site "$site" uninstall-app "$app" -y || echo "[WARN] Failed to uninstall $app"
    done
  fi

  # Migrate
  echo "[MIGRATE] bench --site $site migrate"
  bench --site "$site" migrate
done

# Set last site as current
if [ ${#INSTANCE_SITES[@]} -gt 0 ]; then
  bench use "${INSTANCE_SITES[-1]}"
fi

# ---------------------------
# Start services
# ---------------------------
if [ "$DEPLOYMENT" = "production" ]; then
  echo "[MODE] PRODUCTION"
  sudo mkdir -p /var/log
  sudo chown -R frappe:frappe /var/log

  if [ ! -f "config/supervisor.conf" ]; then
    echo "[SETUP] bench setup supervisor --skip-redis"
    bench setup supervisor --skip-redis
  fi

  if [ ! -f "config/nginx.conf" ]; then
    echo "[SETUP] bench setup nginx"
    bench setup nginx
  fi

  if ! grep -q "log_format main" /etc/nginx/nginx.conf; then
    echo "[PATCH] Injecting main log_format into /etc/nginx/nginx.conf"
    sudo sed -i '/http {/r /main.patch.conf' /etc/nginx/nginx.conf || true
  fi

  sudo ln -sf "$BENCH_DIR/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf

  echo "[SUPERVISOR] Merging configs -> $MERGED_SUPERVISOR_CONF"
  sudo bash -c "cat /dev/null > '$MERGED_SUPERVISOR_CONF'"
  sudo bash -c "cat /dev/null > '$MERGED_SUPERVISOR_CONF' && cat '$WRAPPER_CONF' >> '$MERGED_SUPERVISOR_CONF' && echo >> '$MERGED_SUPERVISOR_CONF' && cat '$BENCH_DIR/config/supervisor.conf' >> '$MERGED_SUPERVISOR_CONF'"

  echo "[BIN] bench: $(which bench)"
  command -v gunicorn >/dev/null && echo "[BIN] gunicorn: $(which gunicorn)" || echo "[BIN] gunicorn: not found"

  sudo supervisord -n -c "$MERGED_SUPERVISOR_CONF"
else
  echo "[MODE] DEVELOPMENT"
  exec bench start
fi

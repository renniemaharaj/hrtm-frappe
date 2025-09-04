#!/bin/bash
set -Eeuo pipefail

# ==========================================
# Frappe Entrypoint
# - Reads instance.json for deployment, branch, apps, site
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
INSTANCE_SITE=$(json_get "$INSTANCE_JSON_SOURCE" '.instance_site' 'frontend')
FRAPPE_BRANCH=$(json_get "$INSTANCE_JSON_SOURCE" '.frappe_branch' 'develop')
BENCH_DIR="$FRAPPE_HOME/$(json_get "$INSTANCE_JSON_SOURCE" '.frappe_bench' "$BENCH_NAME_DEFAULT")"

# Preloaded apps (array)
mapfile -t PRELOADED_APPS < <(read_apps_array "$INSTANCE_JSON_SOURCE" '.preloaded_apps')
# Guard: ensure frappe core is always considered installed, but never "get-app"
if ! printf '%s\n' "${PRELOADED_APPS[@]:-}" | grep -qx "frappe"; then
  PRELOADED_APPS=("frappe" "${PRELOADED_APPS[@]:-}")
fi

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

# Debug toggles (optional): set to 1 to enforce hard waits, 0 to skip
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
# Ensure apps exist in bench/apps (skip core frappe)
# ---------------------------
for app in "${PRELOADED_APPS[@]}"; do
  if [ "$app" = "frappe" ]; then continue; fi
  if [ ! -d "apps/$app" ]; then
    echo "[APP] Fetching: $app (branch: $FRAPPE_BRANCH)"
    if ! bench get-app "$app" --branch "$FRAPPE_BRANCH"; then
      echo "[WARN] bench get-app $app failed. If this is a private/custom app, ensure remotes are configured."
    fi
  fi
done

# ---------------------------
# Create site if missing
# ---------------------------
if [ ! -d "sites/$INSTANCE_SITE" ]; then
    echo "[SITE] Creating: $INSTANCE_SITE"
    bench new-site "$INSTANCE_SITE" \
        --db-root-username "$DB_ROOT_USERNAME" \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --admin-password admin
fi

# ---------------------------
# Align site apps to PRELOADED_APPS
# ---------------------------
echo "[APPS] Aligning site apps to preloaded_apps in instance.json..."
# Get currently installed apps
current_apps=$(bench --site "$INSTANCE_SITE" list-apps | awk '{print $1}' | sed '/^$/d')
expected_apps=$(printf '%s\n' "${PRELOADED_APPS[@]}" | sort -u)
current_sorted=$(printf '%s\n' $current_apps | sort -u)

# Install missing apps (skip frappe core)
missing=$(comm -23 <(echo "$expected_apps") <(echo "$current_sorted"))
if [ -n "$missing" ]; then
  echo "[APPS] Installing missing apps: $(echo "$missing" | xargs)"
  for app in $missing; do
    [ "$app" = "frappe" ] && continue
    bench --site "$INSTANCE_SITE" install-app "$app" || echo "[WARN] Failed to install $app"
  done
fi

extras=$(comm -13 <(echo "$expected_apps") <(echo "$current_sorted") | grep -vx "frappe" || true)
if [ -n "$extras" ]; then
  echo "[APPS] Uninstalling extra apps: $(echo "$extras" | xargs)"
  for app in $extras; do
    bench --site "$INSTANCE_SITE" uninstall-app "$app" -y || echo "[WARN] Failed to uninstall $app"
  done
fi

# ---------------------------
# Migrate and set current site
# ---------------------------
echo "[MIGRATE] bench --site $INSTANCE_SITE migrate"
bench --site "$INSTANCE_SITE" migrate
bench use "$INSTANCE_SITE"

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

# ---------------------------
# Merge wrapper and supervisor configs
 # ---------------------------
  echo "[SUPERVISOR] Merging configs -> $MERGED_SUPERVISOR_CONF"
    # Create/overwrite merged file
    sudo bash -c "cat /dev/null > '$MERGED_SUPERVISOR_CONF'"
    # Append wrapper config
    # sudo bash -c "cat '$WRAPPER_CONF' >> '$MERGED_SUPERVISOR_CONF'"
    # echo "" | sudo tee -a "$MERGED_SUPERVISOR_CONF" >/dev/null
    # Append bench-generated supervisor config
    # sudo bash -c "cat '$BENCH_DIR/config/supervisor.conf' >> '$MERGED_SUPERVISOR_CONF'"
    # Ensure frappe owns the merged config
    # sudo chown frappe:frappe "$MERGED_SUPERVISOR_CONF"
  sudo bash -c \
    "cat /dev/null > '$MERGED_SUPERVISOR_CONF' && cat '$WRAPPER_CONF' >> '$MERGED_SUPERVISOR_CONF' && echo >> '$MERGED_SUPERVISOR_CONF' && cat '$BENCH_DIR/config/supervisor.conf' >> '$MERGED_SUPERVISOR_CONF'"
  echo "[BIN] bench: $(which bench)"; command -v gunicorn >/dev/null && echo "[BIN] gunicorn: $(which gunicorn)" || echo "[BIN] gunicorn: not found"

  sudo supervisord -n -c "$MERGED_SUPERVISOR_CONF"
else
  echo "[MODE] DEVELOPMENT"
  exec bench start
fi

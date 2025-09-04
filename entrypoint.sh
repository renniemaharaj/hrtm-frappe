#!/bin/bash
set -e

echo "[ENTRYPOINT] $(date '+%Y-%m-%d %H:%M:%S.%3N') Entrypoint PID: $$ (PPID: $PPID)"

# ---------------------------
# Environment / Variables
# ---------------------------
FRAPPE_HOME=/home/frappe
INSTANCE_JSON_SOURCE="/instance.json"
COMMON_CONFIG_SOURCE="/common_site_config.json"

# ---------------------------
# Load instance.json
# ---------------------------
if [ -f "$INSTANCE_JSON_SOURCE" ]; then
    echo "Loading instance.json..."
    # Export JSON key-values as env vars
    export $(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$INSTANCE_JSON_SOURCE")
else
    echo "Error: $INSTANCE_JSON_SOURCE not found. Exiting."
    exit 1
fi

# ---------------------------
# Instance variables
# ---------------------------
BENCH_DIR="$FRAPPE_HOME/${frappe_bench:-frappe-bench}"
SITE_NAME="${instance_site:-frontend}"

# Whether to run in production or development mode
# production: uses supervisord and nginx
# development: uses `bench start`
DEPLOYMENT="${deployment:-development}"

DB_HOST="${DB_HOST:-mariadb}"
DB_ROOT_USERNAME="${DB_ROOT_USERNAME:-root}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-root}"
DB_USER="${DB_USER:-frappe}"
DB_PASSWORD="${DB_PASSWORD:-frappe}"
DB_PORT="${DB_PORT:-3306}"

# Redis setting - assuming default ports and hostnames
# Uncomment and modify if using custom Redis testing
# Set ports in common_site_config.json accordingly
# REDIS_QUEUE="${REDIS_QUEUE:-redis://redis-queue:6379}"
# REDIS_CACHE="${REDIS_CACHE:-redis://redis-cache:6379}"
# REDIS_SOCKETIO="${REDIS_SOCKETIO:-redis://redis-socketio:6379}"

COMMON_CONFIG_DEST="$BENCH_DIR/sites/common_site_config.json"

MERGED_SUPERVISOR_CONF="/supervisor-merged.conf"
WRAPPER_CONF="/supervisor.conf"

DEPLOYMENT="${deployment:-development}"
# ---------------------------
# Ensure frappe owns workspace
# ---------------------------
sudo chown -R frappe:frappe "$FRAPPE_HOME"
cd "$FRAPPE_HOME"

# ---------------------------
# Wait for MariaDB
# ---------------------------
# echo "Waiting for MariaDB..."
# until mysqladmin ping -h "$DB_HOST" -u "$DB_ROOT_USERNAME" -p"$DB_ROOT_PASSWORD" --silent; do
#     sleep 3
# done
# echo "MariaDB is ready!"

# ---------------------------
# Wait for Redis
# ---------------------------
# for REDIS_URL in "$REDIS_QUEUE" "$REDIS_CACHE" "$REDIS_SOCKETIO"; do
#     host=$(echo "$REDIS_URL" | sed -E 's|redis://([^:/]+):?.*|\1|')
#     port=$(echo "$REDIS_URL" | sed -E 's|redis://[^:]+:([0-9]+).*|\1|')
#     echo "Waiting for Redis at $host:$port..."
#     until redis-cli -h "$host" -p "$port" ping &>/dev/null; do
#         sleep 2
#     done
#     # echo "Redis $host:$port is ready!"
# done

# ---------------------------
# Initialize bench if needed
# ---------------------------
if [ ! -d "$BENCH_DIR" ]; then
    echo "Initializing bench at $BENCH_DIR..."
    bench init --frappe-branch "$frappe_branch" "$BENCH_DIR"
fi
cd "$BENCH_DIR"

# ---------------------------
# Common site config
# ---------------------------
if [ -f "$COMMON_CONFIG_SOURCE" ]; then
    echo "Copying common_site_config.json..."
    cp "$COMMON_CONFIG_SOURCE" "$COMMON_CONFIG_DEST"
    sudo chown frappe:frappe "$COMMON_CONFIG_DEST"
else
    echo "Error: $COMMON_CONFIG_SOURCE not found. Exiting."
    exit 1
fi

# ---------------------------
# Ensure apps are available
# ---------------------------
for app in erpnext hrms; do
    if [ ! -d "apps/$app" ]; then
        echo "Fetching app: $app..."
        bench get-app "$app" --branch "$frappe_branch"
    fi
done

# ---------------------------
# Create site if missing
# ---------------------------
if [ ! -d "sites/$SITE_NAME" ]; then
    echo "Creating site: $SITE_NAME..."
    bench new-site "$SITE_NAME" \
        --db-root-username "$DB_ROOT_USERNAME" \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --admin-password admin

    echo "Installing apps on $SITE_NAME..."
    bench --site "$SITE_NAME" install-app erpnext hrms
else
    echo "Site $SITE_NAME already exists."
    for app in erpnext hrms; do
        if ! bench --site "$SITE_NAME" list-apps | grep -q "$app"; then
            echo "Installing missing app: $app..."
            bench --site "$SITE_NAME" install-app "$app"
        fi
    done
fi

# ---------------------------
# Migrate site
# ---------------------------
echo "Running migrations for $SITE_NAME..."
bench --site "$SITE_NAME" migrate

# ---------------------------
# Set current site
# ---------------------------
bench use "$SITE_NAME"

# ---------------------------
# Start services
# ---------------------------
if [ "$DEPLOYMENT" = "production" ]; then
    echo "Starting in PRODUCTION mode..."

    # Ensure log dir exists
    sudo mkdir -p /var/log
    sudo chown -R frappe:frappe /var/log

    # Ensure bench dir exists
    if [ ! -d "$BENCH_DIR" ]; then
        echo "ERROR: BENCH_DIR $BENCH_DIR does not exist"
        exit 1
    fi

    cd "$BENCH_DIR"

    # Generate supervisor config if missing
    if [ ! -f "config/supervisor.conf" ]; then
        echo "Generating supervisor configuration..."
        bench setup supervisor --skip-redis
    else
        echo "Supervisor config exists, skipping generation..."
    fi

    # Generate nginx config if missing
    if [ ! -f "config/nginx.conf" ]; then
        echo "Generating nginx configuration..."
        bench setup nginx
    else
    echo "Nginx config exists, skipping generation..."
    fi

# ---------------------------
# Patch nginx.conf with log_format main if missing
# ---------------------------
if ! grep -q "log_format main" /etc/nginx/nginx.conf; then
    echo "Patching nginx.conf with main log_format..."
    # Insert contents of patch before the closing `}` of the http block
    sudo sed -i '/http {/r /main.patch.conf' /etc/nginx/nginx.conf
fi

# ---------------------------
# Link nginx config
# ---------------------------
sudo ln -sf "$BENCH_DIR/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf

    # ---------------------------
    # Merge wrapper and supervisor configs
    # ---------------------------
    echo "Merging supervisord configs..."
    # Create/overwrite merged file
    sudo bash -c "cat /dev/null > '$MERGED_SUPERVISOR_CONF'"
    # Append wrapper config
    sudo bash -c "cat '$WRAPPER_CONF' >> '$MERGED_SUPERVISOR_CONF'"
    echo "" | sudo tee -a "$MERGED_SUPERVISOR_CONF" >/dev/null
    # Append bench-generated supervisor config
    sudo bash -c "cat '$BENCH_DIR/config/supervisor.conf' >> '$MERGED_SUPERVISOR_CONF'"
    # Ensure frappe owns the merged config
    sudo chown frappe:frappe "$MERGED_SUPERVISOR_CONF"

    # Optional: list binaries for debug
    echo "Production binaries:"
    ls -l "$(which bench)" "$(which gunicorn)"

    # Start supervisord (foreground)
    sudo supervisord -n -c "$MERGED_SUPERVISOR_CONF"

else
    echo "Starting in DEVELOPMENT mode..."
    exec bench start
fi
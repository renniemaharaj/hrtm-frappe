#!/bin/bash
set -e

# ---------------------------
# Environment / Variables
# ---------------------------
FRAPPE_HOME=/home/frappe
BENCH_DIR=$FRAPPE_HOME/frappe-bench
SITE_NAME="${SITE_NAME:-frontend}"
DB_HOST="${DB_HOST:-mariadb}"
DB_ROOT_USERNAME="${DB_ROOT_USERNAME:-root}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-root}"
DB_USER="${DB_USER:-frappe}"
DB_PASSWORD="${DB_PASSWORD:-frappe}"
DB_PORT="${DB_PORT:-3306}"

REDIS_QUEUE="${REDIS_QUEUE:-redis://redis-queue:6379}"
REDIS_CACHE="${REDIS_CACHE:-redis://redis-cache:6379}"
REDIS_SOCKETIO="${REDIS_SOCKETIO:-redis://redis-socketio:6379}"

COMMON_CONFIG_SOURCE="/common_site_config.json"
COMMON_CONFIG_DEST="$BENCH_DIR/sites/common_site_config.json"

# ---------------------------
# Ensure frappe owns the workspace
# ---------------------------
sudo chown -R frappe:frappe "$FRAPPE_HOME"
cd "$FRAPPE_HOME"

# ---------------------------
# Wait for MariaDB
# ---------------------------
echo "Waiting for MariaDB to be ready..."
until mysqladmin ping -h "$DB_HOST" -u "$DB_ROOT_USERNAME" -p"$DB_ROOT_PASSWORD" --silent; do
    echo "MariaDB is unavailable - sleeping..."
    sleep 3
done
echo "MariaDB is up!"

# ---------------------------
# Wait for Redis services
# ---------------------------
echo "Waiting for Redis services..."

for REDIS_URL in "$REDIS_QUEUE" "$REDIS_CACHE" "$REDIS_SOCKETIO"; do
    host=$(echo "$REDIS_URL" | sed -E 's|redis://([^:/]+):?.*|\1|')
    port=$(echo "$REDIS_URL" | sed -E 's|redis://[^:]+:([0-9]+).*|\1|')
    until redis-cli -h "$host" -p "$port" ping &>/dev/null; do
        echo "Redis at $host:$port is unavailable - sleeping..."
        sleep 2
    done
    echo "Redis at $host:$port is up!"
done

# ---------------------------
# Initialize bench if not exists
# ---------------------------
if [ ! -d "$BENCH_DIR" ]; then
    echo "Initializing Frappe bench..."
    bench init --frappe-branch develop "$BENCH_DIR"
fi

cd "$BENCH_DIR"

# ---------------------------
# Copy common_site_config.json
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
# Pull apps if not already present
# ---------------------------
for app in erpnext hrms; do
    if [ ! -d "apps/$app" ]; then
        echo "Getting app $app..."
        bench get-app "$app" --branch develop
    fi
done

# ---------------------------
# Create site if not exists
# ---------------------------
if [ ! -d "sites/$SITE_NAME" ]; then
    echo "Creating site $SITE_NAME..."
    bench new-site "$SITE_NAME" \
        --db-root-username "$DB_ROOT_USERNAME" \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --db-name "$SITE_NAME" \
        --db-user "$DB_USER" \
        --db-password "$DB_PASSWORD" \
        --db-host "$DB_HOST" \
        --db-port "$DB_PORT" \
        --admin-password admin --force

    echo "Installing apps on site $SITE_NAME..."
    bench --site "$SITE_NAME" install-app erpnext hrms
fi

# ---------------------------
# Ensure site exists
# ---------------------------
if [ -d "sites/$SITE_NAME" ]; then
    echo "Site $SITE_NAME found."

    # Restart bench to ensure services pick up latest config
    echo "Restarting bench..."
    bench restart

    # Set the current site
    echo "Setting current site to $SITE_NAME..."
    bench use "$SITE_NAME"
else
    echo "ERROR: Site $SITE_NAME does not exist in sites/."
    exit 1
fi

# ---------------------------
# Start bench
# ---------------------------
echo "Starting bench..."
bench start

# ---------------------------
# Keep container running if no command is passed
# ---------------------------
exec "$@"

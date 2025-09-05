#!/bin/bash
set -Eeuo pipefail

cd $BENCH_DIR

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
# Frappe Docker Compose Setup

## Overview

This Docker Compose project sets up a full **Frappe development environment** with automatic app management:

* **Frappe Framework** (branch configurable, default `develop`)
* **ERPNext** and **HRMS** (preloaded apps)
* **MariaDB**
* **Redis** (cache, queue, socketio)
* **Site auto-creation** based on `instance.json` in the repository root
* **App alignment**: site apps are automatically synced with the `preloaded_apps` list from `instance.json`.

## Features

* **Zero manual steps** after first run — sites and apps are provisioned automatically.
* **App sync logic**:

  * Apps listed in `preloaded_apps` are always installed on the site.
  * Apps not in `preloaded_apps` are uninstalled (except `frappe`).
  * Ensures environments are consistent across containers.
* **Optimized entrypoint**:

  * Waits for MariaDB and Redis to be healthy before starting services.
  * Uses Docker environment variables for MariaDB credentials.
  * Parses `common_site_config.json` for Redis URLs using `jq`.

## Configuration

### Files

* `instance.json` (repo root) — controls deployment mode, branch, site name and preloaded apps.
* `common_site_config.json` (repo root) — Frappe-specific site settings (redis urls, socketio port, etc.). The entrypoint copies this file into `sites/common_site_config.json` inside the bench.

> **Note:** `instance.json` lives in the **repository root**. The entrypoint reads it from `/instance.json` inside the container. If you need to change it, edit `./instance.json` in the repo and restart the container.

### Example `instance.json` (repo root)

```json
{
    "deployment": "develop",
    "preloaded_apps": [
        "frappe",
        "erpnext",
        "hrms"
    ],  
    "instance_type": "isolated",
    "instance_site": "frontend",
    "frappe_branch": "develop"
}
```

* `deployment`: `production` or `development` (controls supervisor/nginx vs `bench start`).
* `instance_site`: site name created during boot (default: `frontend`).
* `frappe_branch`: branch used by `bench init` and `bench get-app`.
* `preloaded_apps`: array of apps to sync with the site.

### Example `common_site_config.json` (repo root)

```json
{
  "db_name": "frappe",
  "db_password": "frappe",
  "db_host": "mariadb",
  "db_user": "frappe",
  "db_port": 3306,
  "redis_cache": "redis://redis-cache:6379",
  "redis_queue": "redis://redis-queue:6379",
  "redis_socketio": "redis://redis-socketio:6379",
  "redis_socketio_channel": "redis_socketio",
  "socketio_port": 9000,
  "developer_mode": 1,
  "backup_limit": 5,
  "file_watcher_port": 6787,
  "frappe_user": "frappe",
  "email_sender": "no-reply@example.com",
  "realtime_enabled": true,
  "max_workers": 4,
  "max_celery_workers": 8,
  "worker_timeout": 300,
  "log_level": "INFO",
  "auto_email_id": "admin@example.com",
  "max_file_size": 52428800,
  "allow_guests": false
}
```

This file is copied into `frappe-bench/sites/common_site_config.json` by the entrypoint so Frappe uses these Redis URLs and other site settings.

## Docker Compose Environment Variables (MariaDB)

Define MariaDB credentials in your `docker-compose.yml` for the `mariadb` service and pass them to the `frappe` service as environment variables. Example:

```yaml
mariadb:
  image: mariadb:11
  environment:
    MARIADB_ROOT_PASSWORD: root
    MARIADB_USER: frappe
    MARIADB_PASSWORD: frappe
    MARIADB_DATABASE: frappe

frappe:
  environment:
    MARIADB_ROOT_PASSWORD: root
    MARIADB_ROOT_USERNAME: root
    MARIADB_USER: frappe
    MARIADB_PASSWORD: frappe
    MARIADB_DATABASE: frappe
```

The entrypoint reads these environment variables and uses the root credentials when calling `bench new-site` to avoid interactive prompts.

## Running the Project

1. **Build and start containers:**

```bash
# from repo root
docker compose up -d --build
```

2. **Check logs:**

```bash
docker compose logs -f frappe
```

3. **Access services:**

* Development: `http://localhost:8000`
* Production (if using hosts file): `http://<sitename>` (e.g. `http://frontend`)
* For productions, ensure you edit your hosts file to allow site names to go through

4. **Stop the environment:**

```bash
docker compose down
```

## Onboarding Guide

This setup is designed to make onboarding new developers quick and painless.

### Prerequisites

* Docker & Docker Compose installed.
* Ports `8000`, `9000`, and `3306` available.

### Quick start (first time)

1. Clone the repo:

```bash
git clone https://github.com/renniemaharaj/hrtm-frappe
cd hrtm-frappe
```

2. Edit `instance.json` in the repo root if you want custom `instance_site`, branch or `preloaded_apps`.

3. Start the environment:

```bash
docker compose up -d --build
```

4. Verify services are running and inspect the entrypoint logs:

```bash
docker ps
docker compose logs -f frappe
```

5. Enter the container for manual bench commands (if required):

```bash
docker compose exec frappe bash
cd frappe-bench
bench --site frontend migrate
```

### Development workflow

* Edit code in `./mount` to modify apps or any files mounted into the container.
* To change `preloaded_apps` or deployment mode, edit `./instance.json` (repo root) and restart the container to trigger re-sync.

### Troubleshooting

* Database issues: remove `./mysqldata` to reset MariaDB (careful: deletes data).
* Redis issues: remove redis volumes and restart the redis containers.
* Incorrect apps: check `instance.json` — the entrypoint enforces `preloaded_apps` (installs missing apps and uninstalls extras).
* If `bench new-site` prompts for a password, ensure `MARIADB_ROOT_PASSWORD` is set and visible to the `frappe` service.

## App Auto-Alignment

On every boot the entrypoint:

1. Ensures apps listed in `instance.json`'s `preloaded_apps` are present in `frappe-bench/apps` (fetches via `bench get-app` when missing).
2. Creates the configured site (if missing) using the Docker-provided root credentials.
3. Installs missing apps on the site and uninstalls any apps that are not part of `preloaded_apps` (except `frappe`).

This guarantees a consistent site/app state across machines and deployments. Restart the `frappe` container after changing `instance.json` to apply changes.

## Volumes

* `mysqldata`: MariaDB persistent storage
* `redis-cache`, `redis-queue`, `redis-socketio`: Redis persistent storage
* `mount`: Frappe workspace mount for local edits

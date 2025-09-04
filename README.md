# Frappe Docker Compose Setup

## Overview

This Docker Compose project sets up a full **Frappe development environment** with automatic app management:

* **Frappe Framework** (branch configurable, default `develop`)
* **ERPNext** and other site-specific apps
* **MariaDB**
* **Redis** (cache, queue, socketio)
* **Site auto-creation and management** based on `instance.json` in the repository root
* **App alignment**: site apps are automatically installed and synced based on each site's requirements.

## Features

* **Zero manual steps** after first run — sites and apps are provisioned automatically.
* **App management logic**:

  * Apps required by each site are installed automatically.
  * Any apps not required are uninstalled (except `frappe`).
  * Ensures environments are consistent across containers.
* **Optimized entrypoint**:

  * Waits for MariaDB and Redis to be healthy before starting services.
  * Uses Docker environment variables for MariaDB credentials.
  * Parses `common_site_config.json` for Redis URLs using `jq`.

## Site Auto-Management

The entrypoint handles site management automatically:

1. Reads `instance.json` to get the list of sites and their required apps.
2. Optionally drops abandoned sites if `drop_abandoned_sites` is `true`.
3. Creates missing sites using Docker-provided root credentials to avoid interactive prompts.
4. Installs required apps for each site.
5. Uninstalls apps that are not required for the site (except `frappe`).
6. Migrates each site after app alignment.

> Sites are automatically kept in sync with `instance.json` on container start. Restart the container to apply changes.

## Configuration

### Files

* `instance.json` (repo root) — controls deployment mode, sites, apps, and branch.
* `common_site_config.json` (repo root) — Frappe-specific site settings (redis urls, socketio port, etc.). Copied into `sites/common_site_config.json` inside the bench.

### Example `instance.json` (repo root)

```json
{
    "deployment": "production",
    "instance_sites": [
        {
            "site_name": "frontend",
            "apps": ["frappe", "erpnext", "hrms"]
        },
        {
            "site_name": "frontend1",
            "apps": ["frappe", "erpnext"]
        }
    ],
    "drop_abandoned_sites": true,
    "frappe_branch": "develop"
}
```

* `deployment`: `production` or `development` (controls supervisor/nginx vs `bench start`).
* `instance_sites`: array of site objects; each object defines a `site_name` and required `apps`.
* `drop_abandoned_sites`: if `true`, sites not listed will be dropped automatically.
* `frappe_branch`: branch used by `bench init` and `bench get-app`.

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

## Docker Compose Environment Variables (MariaDB)

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

## Running the Project

1. **Build and start containers:**

```bash
docker compose up -d --build
```

2. **Check logs:**

```bash
docker compose logs -f frappe
```

3. **Access services:**

* Development: `http://localhost:8000`
* Production: `http://<sitename>` (e.g., `http://frontend`) — edit hosts file as needed.

4. **Stop the environment:**

```bash
docker compose down
```

## Onboarding Guide

### Prerequisites

* Docker & Docker Compose installed.
* Ports `8000`, `9000`, and `3306` available.

### Quick start (first time)

1. Clone the repo:

```bash
git clone https://github.com/renniemaharaj/hrtm-frappe
cd hrtm-frappe
```

2. Edit `instance.json` in the repo root for custom sites, apps, or branch.
3. Start the environment:

```bash
docker compose up -d --build
```

4. Verify services are running and inspect logs:

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

* Edit code in `./mount` to modify apps or other files mounted into the container.
* Restart the container after changing `instance.json` to trigger site/app re-sync.

### Troubleshooting

* Database issues: remove `./mysqldata` to reset MariaDB (deletes data).
* Redis issues: remove Redis volumes and restart containers.
* Incorrect apps: check `instance.json` — the entrypoint enforces required apps per site.
* If `bench new-site` prompts for a password, ensure `MARIADB_ROOT_PASSWORD` is set and visible to the `frappe` service.

## Volumes

* `mysqldata`: MariaDB persistent storage
* `redis-cache`, `redis-queue`, `redis-socketio`: Redis persistent storage
* `mount`: Frappe workspace mount for local edits

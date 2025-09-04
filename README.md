# Frappe Docker Compose Setup

## Overview

This Docker Compose project sets up a full Frappe development environment, including:

* **Frappe Framework** (branch configurable, default `develop`)
* **ERPNext** (preloaded app)
* **HRMS** (preloaded app)
* **MariaDB 11** for database
* **Redis** for caching, queue, and Socket.IO communication

This setup provides a ready-to-use Frappe environment with a running frontend, database, and Redis services. It supports both development and production modes.

## Services

### 1. Frappe

* Builds from the provided `Dockerfile`.
* Mounts the local `./mount` directory to `/home/frappe`.
* Exposes port `8000` for the web interface.
* Depends on MariaDB and Redis services.
* Initializes Frappe Bench if it does not exist.
* Pulls ERPNext and HRMS apps if not already present.
* Creates a site (configurable, default `frontend`) if it does not exist.
* Uses `common_site_config.json` to configure database and Redis connections.
* Starts the Bench, which runs Frappe and all background workers including Socket.IO.

### 2. MariaDB

* Container: `frappe_mariadb`
* Image: `mariadb:11`
* Stores data in a persistent volume (`./mysqldata`).
* Environment variables set for root user and Frappe database credentials.
* Character set: `utf8mb4`, collation: `utf8mb4_unicode_ci`.

### 3. Redis

* **redis-cache**: caching layer
* **redis-queue**: background job queue
* **redis-socketio**: Socket.IO pub/sub
* Each Redis instance has a dedicated container and persistent volume.
* Configured in `common_site_config.json`.

## Preloaded Apps

* **ERPNext**: Core ERP functionality.
* **HRMS**: Human Resource Management System.
* Both apps are pulled during entrypoint execution if not already present.

  - Configurable app list coming soon!

## Configuration

Configuration is controlled via a simple JSON file:

```json
{
  "deployment": "production",
  "instance_type": "isolated",
  "instance_site": "frontend",
  "frappe_branch": "develop"
}
```

* **deployment**: `production` or `develop` mode
* **instance\_type**: currently `isolated`
* **instance\_site**: site name (default: `frontend`)
* **frappe\_branch**: branch of the Frappe framework to use (default: `develop`)

The `common_site_config.json` file sets the site-specific configuration for Frappe, including database connection and Redis URLs:

```json
{
  "db_name": "frontend",
  "redis_cache": "redis://redis-cache:6379",
  "redis_queue": "redis://redis-queue:6379",
  "redis_socketio": "redis://redis-socketio:6379",
  "redis_socketio_channel": "redis_socketio",
  "socketio_port": 9000
}
```

This file is copied into the `sites/` directory during container startup.

## Running the Project

1. **Build the containers:**

```bash
docker compose build
```

2. **Start the containers:**

```bash
docker compose up -d
```

3. **Check logs:**

```bash
docker compose logs -f frappe
```

4. **Access the Frappe frontend:**

* Open your browser and navigate to `http://localhost:8000`.
* Log in with the admin credentials defined during site creation.

5. **Stop the environment:**

```bash
docker-compose down
```

## Production Usage

This project also provides a simple **production switch** that runs:

* **supervisord** – process manager
* **gunicorn** – Python WSGI HTTP server
* **nginx** – reverse proxy serving your Frappe sites

To use this, you will need to add your sites to the system `hosts` file for proper resolution. This setup makes it possible to serve sites more realistically in production.

⚠️ **Note:** This production implementation is **not recommended yet** as the project is still in early development. It is, however, a good way to explore running Frappe in a more bare-bones manner with automatic app fetching and initial site installation.

## Onboarding Guide

This setup is designed to make onboarding new developers quick and painless. Follow these steps to get started:

### Prerequisites

* Install **Docker** and **Docker Compose** on your machine.
* Ensure ports `8000`, `9000`, and `3306` are available.

### Getting Started

1. **Clone the repository:**

```bash
git clone https://github.com/renniemaharaj/hrtm-frappe
cd hrtm-frappe
```

2. **Build and start the environment:**

```bash
docker-compose up -d --build
```

3. **Verify services are running:**

```bash
docker ps # List running docker services

# (eg output) 31053642328a   hrtm-frappe-frappe   "/entrypoint.sh slee…"   5 hours ago   Up 5 hours   0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp, 0.0.0.0:9000->9000/tcp, [::]:9000->9000/tcp   hrtm-frappe-frappe-1

docker exec -it {containerID} bash # containerID -> 31053642328a

cd frappe-bench # & execute bench commands
```

4. **Access the frontend:**

Open your browser at `http://localhost:8000`. (for develop mode)

Open your browser at http://sitename (eg http://frontend) (for production)

5. **Login credentials:**

Use the admin credentials created during site initialization.

Username: Administrator
Password: admin

### Development Workflow

* Make changes to Frappe apps in the mounted `./mount` directory.
* Use `docker-compose exec frappe bash` to open a shell inside the container.
* Run standard bench commands inside the container, for example:

```bash
bench --site frontend migrate
```

### Troubleshooting

* **Database issues:** Remove `./mysqldata` if you want to reset MariaDB.
* **Redis issues:** Remove redis volumes (`redis-cache`, `redis-queue`, `redis-socketio`) and restart.
* **Logs:** Use `docker-compose logs -f frappe` to debug container startup.

### Notes for New Developers

* This environment is both development and production-ready.
* Avoid editing core Frappe code directly—extend functionality through apps.
* For production deployments, coordinate with your team before exposing services.

## Notes

* The `entrypoint.sh` script handles initialization of Frappe, pulling apps, creating the site, copying the `common_site_config.json`, and waiting for MariaDB and Redis services.
* Bench and Frappe services are started automatically on container startup.
* Socket.IO communication is available on port `9000` for real-time updates.

## Volumes

* `mysqldata`: MariaDB persistent storage
* `redis-cache`, `redis-queue`, `redis-socketio`: Redis persistent storage
* `mount`: Frappe workspace mount for local edits

This setup ensures that your environment persists across container restarts while keeping Frappe, ERPNext, and HRMS ready to use.

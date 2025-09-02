# Frappe Docker Compose Setup

## Overview

This Docker Compose project sets up a full Frappe development environment, including:

* **Frappe Framework** (latest `develop` branch)
* **ERPNext** (preloaded app)
* **HRMS** (preloaded app)
* **MariaDB 11** for database
* **Redis** for caching, queue, and Socket.IO communication

This setup provides a ready-to-use Frappe development environment with a running frontend, database, and Redis services.

## Services

### 1. Frappe

* Builds from the provided `Dockerfile`.
* Mounts the local `./mount` directory to `/home/frappe`.
* Exposes port `8000` for the web interface.
* Depends on MariaDB and Redis services.
* Initializes Frappe Bench if it does not exist.
* Pulls ERPNext and HRMS apps if not already present.
* Creates a site (`frontend`) if it does not exist.
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

## Configuration

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
docker-compose build
```

2. **Start the containers:**

```bash
docker-compose up -d
```

3. **Check logs:**

```bash
docker-compose logs -f frappe
```

4. **Access the Frappe frontend:**

* Open your browser and navigate to `http://localhost:8000`.
* Log in with the admin credentials defined during site creation.

5. **Stop the environment:**

```bash
docker-compose down
```

## Notes

* The `entrypoint.sh` script handles the initialization of Frappe, pulling apps, creating the site, copying the `common_site_config.json`, and waiting for MariaDB and Redis services.
* Bench and Frappe services are started automatically on container startup.
* Socket.IO communication is available on port `9000` for real-time updates.

## Volumes

* `mysqldata`: MariaDB persistent storage
* `redis-cache`, `redis-queue`, `redis-socketio`: Redis persistent storage
* `mount`: Frappe workspace mount for local edits

This setup ensures that your development environment persists across container restarts while keeping Frappe, ERPNext, and HRMS ready to use.

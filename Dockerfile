FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------
# System dependencies
# ---------------------------
RUN apt-get update && apt-get install -y \
    git python-is-python3 python3-dev python3-pip python3-venv \
    mariadb-server mariadb-client libmariadb-dev pkg-config \
    redis-server \
    curl wget gnupg build-essential xvfb libfontconfig sudo \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Configure MariaDB utf8mb4 (for older Frappe versions)
RUN echo "\
[mysqld]\n\
character-set-client-handshake = FALSE\n\
character-set-server = utf8mb4\n\
collation-server = utf8mb4_unicode_ci\n\
\n\
[mysql]\n\
default-character-set = utf8mb4\n\
" > /etc/mysql/my.cnf

# ---------------------------
# Install Node.js 18.x and Yarn globally
# ---------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn

# ---------------------------
# Create frappe user
# ---------------------------
RUN useradd -ms /bin/bash frappe && \
    echo "frappe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER frappe
WORKDIR /home/frappe

# Verify Node, npm, Yarn
RUN node -v && npm -v && yarn -v

# Increase yarn network timeout (for slower connections)
RUN yarn config set network-timeout 600000 -g

USER root

# ---------------------------
# Install wkhtmltopdf
# ---------------------------
RUN wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb \
    && apt-get update && apt-get install -y ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb \
    && rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb

USER frappe

# Verify wkhtmltopdf
RUN wkhtmltopdf --version

USER root

# Fix ownership
RUN chown -R frappe:frappe /home/frappe

# ---------------------------
# Install Bench CLI
# ---------------------------
RUN PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install frappe-bench

USER frappe

# Verify Bench
RUN bench --version

# ---------------------------
# Test cron installation
# ---------------------------
RUN crontab -l || echo "* * * * * echo 'cron works' >> /home/frappe/cron_test.log"

# ---------------------------
# Runtime working dir
# ---------------------------
WORKDIR /home/frappe

# Note:
# - Bench init should be executed at container runtime:
# docker exec -it frappe_app su frappe -c "bench init --frappe-branch develop frappe-bench"
# - This allows persistence of frappe-bench folder using volumes.

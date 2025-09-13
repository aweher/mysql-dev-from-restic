# Copyright (c) 2025 Ariel S. Weher <ariel@weher.net>
# Este código es propietario y confidencial. Todos los derechos reservados.

FROM --platform=$BUILDPLATFORM percona/percona-xtradb-cluster:5.7

# Switch to root temporarily to install packages and restic
USER root

# Paquetes necesarios para restic + jq (parseo JSON)
RUN microdnf update -y && \
    microdnf install -y jq ca-certificates curl bash bzip2 && \
    microdnf clean all && \
    # Install restic from GitHub releases (multiarch support)
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then RESTIC_ARCH="amd64"; elif [ "$ARCH" = "aarch64" ]; then RESTIC_ARCH="arm64"; else RESTIC_ARCH="amd64"; fi && \
    RESTIC_VERSION=$(curl -s https://api.github.com/repos/restic/restic/releases/latest | jq -r .tag_name | sed 's/v//') && \
    curl -L https://github.com/restic/restic/releases/latest/download/restic_${RESTIC_VERSION}_linux_${RESTIC_ARCH}.bz2 -o restic.bz2 && \
    bunzip2 restic.bz2 && \
    chmod +x restic && \
    mv restic /usr/local/bin/

# Build arguments for downloading SQL files during build
ARG RESTIC_REPOSITORY
ARG RESTIC_PASSWORD  
ARG DB_LIST
ARG RESTIC_HOST=""
ARG RESTIC_TAG="mysqldump"
ARG RESTIC_SNAPSHOT=""

# Copy script for downloading SQL files during build
COPY scripts/build-fetch-sql.sh /tmp/build-fetch-sql.sh
RUN chmod +x /tmp/build-fetch-sql.sh

# Download SQL files during build (only if RESTIC_REPOSITORY is provided)
RUN if [ -n "${RESTIC_REPOSITORY}" ]; then \
        echo "Downloading SQL files during build..."; \
        /tmp/build-fetch-sql.sh; \
    else \
        echo "No RESTIC_REPOSITORY provided, skipping SQL download."; \
    fi

# Clean up build script
RUN rm -f /tmp/build-fetch-sql.sh

# Tipico ajuste PXC: asegurar sql_mode sin ONLY_FULL_GROUP_BY al inicio si queres (opcional)
COPY config/pxc-tweaks.cnf /etc/mysql/conf.d/pxc-tweaks.cnf

# Set proper permissions for mysql user and configs
RUN chown -R mysql:mysql /etc/mysql/conf.d/ /docker-entrypoint-initdb.d/ && \
    chmod -R 644 /etc/mysql/conf.d/ && \
    chmod -R 755 /docker-entrypoint-initdb.d/ && \
    find /docker-entrypoint-initdb.d/ -name "*.sql" -exec chmod 644 {} \;

# Switch back to mysql user like the base image
USER mysql

# Usar el entrypoint/cmd por defecto del image base
# (percona/percona-xtradb-cluster:5.7 ya trae /entrypoint.sh y CMD mysqld)
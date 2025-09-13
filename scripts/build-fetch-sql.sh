#!/usr/bin/env bash
# Copyright (c) 2025 Ariel S. Weher <ariel@weher.net>
# Este código es propietario y confidencial. Todos los derechos reservados.

set -euo pipefail

# Script para descargar archivos SQL durante el build de la imagen Docker
# Este script se ejecuta en tiempo de construcción, no en tiempo de ejecución

echo "[build-fetch] Starting SQL download during Docker build..."

# Variables requeridas (deben venir como build args)
: "${RESTIC_REPOSITORY:?Build arg RESTIC_REPOSITORY required}"
: "${RESTIC_PASSWORD:?Build arg RESTIC_PASSWORD required}"
: "${DB_LIST:?Build arg DB_LIST (comma-separated) required}"

# Variables opcionales con defaults
RESTIC_HOST="${RESTIC_HOST:-}"
RESTIC_TAG="${RESTIC_TAG:-mysqldump}"
RESTIC_SNAPSHOT="${RESTIC_SNAPSHOT:-}"
DUMPS_BASE_PATH="${DUMPS_BASE_PATH:-/mysql_dumps}"

export RESTIC_PASSWORD
export RESTIC_CACHE_DIR="/tmp/restic-cache-build"

echo "[build-fetch] Using repository: ${RESTIC_REPOSITORY}"
echo "[build-fetch] DB list: ${DB_LIST}"

restic_repo_args=( -r "${RESTIC_REPOSITORY}" )

# Ahora usamos búsqueda por base de datos individual con tags específicos
echo "[build-fetch] Using per-database snapshot approach with tags mysqldump,<database>"

# Función: para una DB dada, buscar su snapshot específico y descargarlo
fetch_db_sql() {
  local db="$1"
  local out_sql="/docker-entrypoint-initdb.d/50-${db}.sql"

  echo "[build-fetch] Looking for snapshots for DB '${db}' using tags mysqldump,${db}..."

  # Construir argumentos de filtro usando 'latest' para obtener el snapshot más reciente
  local snapshot_args=("${restic_repo_args[@]}" "snapshots" "latest" "--json")
  
  # Agregar filtro de hostname si está especificado
  if [ -n "${RESTIC_HOST}" ]; then
    snapshot_args+=("--host" "${RESTIC_HOST}")
  fi
  
  # Agregar tags específicos para esta base de datos
  snapshot_args+=("--tag" "mysqldump,${db}")
  
  # Buscar el snapshot más reciente para esta base de datos específica
  set +e
  snapshots_json="$(restic "${snapshot_args[@]}" 2>/dev/null)"
  local rc=$?
  set -e
  
  if [ $rc -ne 0 ] || [ -z "${snapshots_json}" ] || [ "${snapshots_json}" = "null" ] || [ "${snapshots_json}" = "[]" ]; then
    echo "[build-fetch] WARNING: No snapshots found for DB '${db}' with tags mysqldump,${db}. Skipping."
    return 0
  fi
  
  # Obtener el snapshot ID (con 'latest' debería ser solo uno)
  local snap_id
  snap_id="$(echo "${snapshots_json}" | jq -r '.[0].id // .id' 2>/dev/null)"
  
  if [ -z "${snap_id}" ] || [ "${snap_id}" = "null" ]; then
    echo "[build-fetch] WARNING: No valid snapshot ID found for DB '${db}'. Skipping."
    return 0
  fi
  
  echo "[build-fetch] Found snapshot ${snap_id} for DB '${db}'"
  
  # Buscar el archivo SQL en el snapshot
  local target_file="/${db}.sql"
  
  echo "[build-fetch] Downloading ${target_file} from snapshot ${snap_id} -> ${out_sql}"
  set +e
  restic "${restic_repo_args[@]}" dump "${snap_id}" "${target_file}" > "${out_sql}.tmp" 2>/dev/null
  rc=$?
  set -e
  
  if [ $rc -ne 0 ]; then
    echo "[build-fetch] WARNING: ${target_file} not found in snapshot ${snap_id}. Skipping."
    rm -f "${out_sql}.tmp" "${out_sql}" 2>/dev/null || true
    return 0
  fi
  
  # Crear archivo final con CREATE DATABASE y USE statements, removiendo LOCK TABLES incompatibles con PXC
  {
    echo "-- Auto-generated database creation for ${db}"
    echo "CREATE DATABASE IF NOT EXISTS \`${db}\`;"
    echo "USE \`${db}\`;"
    echo ""
    # Filtrar statements problemáticos para PXC
    sed \
      -e '/LOCK TABLES/d' \
      -e '/UNLOCK TABLES/d' \
      -e '/FLUSH TABLE.*WITH READ LOCK/d' \
      -e '/FLUSH TABLE.*FOR EXPORT/d' \
      "${out_sql}.tmp"
  } > "${out_sql}"
  
  # Limpiar archivo temporal
  rm -f "${out_sql}.tmp"
  
  # Nos aseguramos que el archivo exista y sea legible
  chmod 0644 "${out_sql}"
  echo "[build-fetch] Successfully downloaded and prepared ${target_file} ($(wc -c < "${out_sql}") bytes)"
}

# Crear directorio de destino
mkdir -p /docker-entrypoint-initdb.d

# Iterar DB_LIST (coma-separado)
IFS=',' read -r -a DBS <<< "${DB_LIST}"
for db in "${DBS[@]}"; do
  db_trim="$(echo "${db}" | xargs)"
  [ -n "${db_trim}" ] && fetch_db_sql "${db_trim}"
done

echo "[build-fetch] Done. SQL files ready for MySQL initialization."
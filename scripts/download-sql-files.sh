#!/usr/bin/env bash
# Copyright (c) 2025 Ariel S. Weher <ariel@weher.net>
# Este código es propietario y confidencial. Todos los derechos reservados.

set -euo pipefail

# Script para descargar archivos SQL desde Restic al directorio local ./sqlfiles/
# Este script se ejecuta localmente, no dentro del contenedor Docker

echo "[local-fetch] Starting SQL download to local ./sqlfiles/ directory..."

# Cargar variables de entorno desde .env
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
    echo "[local-fetch] Loaded configuration from .env"
else
    echo "[local-fetch] ERROR: .env file not found"
    exit 1
fi

# Variables requeridas
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD required}"
: "${DB_LIST:?DB_LIST (comma-separated) required}"

# Variables opcionales con defaults
RESTIC_HOST="${RESTIC_HOST:-}"
RESTIC_TAG="${RESTIC_TAG:-mysqldump}"
SQLFILES_DIR="./sqlfiles"
RETENTION_DAYS="${SQLFILES_RETENTION_DAYS:-7}"

export RESTIC_PASSWORD
export RESTIC_CACHE_DIR="${HOME}/.cache/restic"

echo "[local-fetch] Using repository: ${RESTIC_REPOSITORY}"
echo "[local-fetch] DB list: ${DB_LIST}"
echo "[local-fetch] Output directory: ${SQLFILES_DIR}"
echo "[local-fetch] Retention policy: ${RETENTION_DAYS} days"

restic_repo_args=( -r "${RESTIC_REPOSITORY}" )

# Crear directorio de destino
mkdir -p "${SQLFILES_DIR}"

# Función de limpieza de archivos antiguos
cleanup_old_files() {
  echo "[local-fetch] Cleaning up SQL files older than ${RETENTION_DAYS} days..."
  find "${SQLFILES_DIR}" -name "*.sql" -type f -mtime +${RETENTION_DAYS} -print0 | \
    while IFS= read -r -d '' file; do
      echo "[local-fetch] Removing old file: $(basename "$file")"
      rm -f "$file"
    done
}

# Ejecutar limpieza al inicio
cleanup_old_files

# Función: para una DB dada, buscar su snapshot específico y descargarlo localmente
fetch_db_sql_local() {
  local db="$1"

  echo "[local-fetch] Looking for snapshots for DB '${db}' using tags mysqldump,${db}..."

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
    echo "[local-fetch] WARNING: No snapshots found for DB '${db}' with tags mysqldump,${db}. Skipping."
    return 0
  fi
  
  # Obtener el snapshot ID (con 'latest' debería ser solo uno)
  local snap_id
  snap_id="$(echo "${snapshots_json}" | jq -r '.[0].id // .id' 2>/dev/null)"
  
  if [ -z "${snap_id}" ] || [ "${snap_id}" = "null" ]; then
    echo "[local-fetch] WARNING: No valid snapshot ID found for DB '${db}'. Skipping."
    return 0
  fi
  
  echo "[local-fetch] Found snapshot ${snap_id} for DB '${db}'"
  
  # Usar snapshot ID en el nombre del archivo (primeros 8 caracteres)
  local snap_short="${snap_id:0:8}"
  local out_sql="${SQLFILES_DIR}/${db}_${snap_short}.sql"
  
  # Verificar si ya existe el archivo con este snapshot
  if [ -f "${out_sql}" ]; then
    echo "[local-fetch] File already exists for snapshot ${snap_short}: $(basename "${out_sql}")"
    echo "[local-fetch] Skipping download for DB '${db}'"
    return 0
  fi
  
  # Buscar el archivo SQL en el snapshot
  local target_file="/${db}.sql"
  
  echo "[local-fetch] Downloading ${target_file} from snapshot ${snap_short} -> $(basename "${out_sql}")"
  set +e
  restic "${restic_repo_args[@]}" dump "${snap_id}" "${target_file}" > "${out_sql}.tmp" 2>/dev/null
  rc=$?
  set -e
  
  if [ $rc -ne 0 ]; then
    echo "[local-fetch] WARNING: ${target_file} not found in snapshot ${snap_short}. Skipping."
    rm -f "${out_sql}.tmp" "${out_sql}" 2>/dev/null || true
    return 0
  fi
  
  # Crear archivo final con CREATE DATABASE y USE statements, removiendo LOCK TABLES incompatibles con PXC
  {
    echo "-- Auto-generated database creation for ${db}"
    echo "-- Downloaded from snapshot ${snap_id} (${snap_short}) on $(date)"
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
  echo "[local-fetch] Successfully downloaded and prepared $(basename "${out_sql}") ($(wc -c < "${out_sql}") bytes)"
}

# Iterar DB_LIST (coma-separado)
IFS=',' read -r -a DBS <<< "${DB_LIST}"
for db in "${DBS[@]}"; do
  db_trim="$(echo "${db}" | xargs)"
  [ -n "${db_trim}" ] && fetch_db_sql_local "${db_trim}"
done

echo "[local-fetch] Done. SQL files saved to ${SQLFILES_DIR}/"
echo "[local-fetch] You can now inspect the downloaded files before building the Docker image."
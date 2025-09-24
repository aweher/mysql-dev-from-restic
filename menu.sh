#!/bin/bash
# Copyright (c) 2025 Ariel S. Weher <ariel@weher.net>
# Este código es propietario y confidencial. Todos los derechos reservados.

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables
COMPOSE_FILE="docker-compose.yml"
CONTAINER_NAME="backup-mysql-dev"
PHPMYADMIN_CONTAINER="backup-phpmyadmin"

# Función para mostrar el header
show_header() {
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}    Backup MySQL Dev - Control Panel${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
}

# Función para crear .env desde .env.example
create_env_file() {
    echo -e "${BLUE}=== Configurando archivo .env ===${NC}"

    if [ ! -f ".env.example" ]; then
        echo -e "${RED}❌ Archivo .env.example no encontrado${NC}"
        return 1
    fi

    echo -e "${YELLOW}El archivo .env no existe. Se creará desde .env.example${NC}"
    echo "Por favor, proporciona los siguientes valores:"
    echo ""

    # Variables requeridas
    echo -e "${CYAN}=== Configuración Restic (REQUERIDA) ===${NC}"

    read -p "URL del repositorio Restic: " restic_repo
    while [ -z "$restic_repo" ]; do
        echo -e "${RED}Este campo es obligatorio${NC}"
        read -p "URL del repositorio Restic: " restic_repo
    done

    read -p "Contraseña del repositorio Restic: " restic_password
    while [ -z "$restic_password" ]; do
        echo -e "${RED}Este campo es obligatorio${NC}"
        read -p "Contraseña del repositorio Restic: " restic_password
    done

    read -p "Lista de bases de datos (separadas por comas): " db_list
    while [ -z "$db_list" ]; do
        echo -e "${RED}Este campo es obligatorio${NC}"
        read -p "Lista de bases de datos (separadas por comas): " db_list
    done

    echo ""
    echo -e "${CYAN}=== Configuración MySQL ===${NC}"

    read -p "Contraseña root de MySQL [password_root_mysql]: " mysql_root_password
    mysql_root_password=${mysql_root_password:-password_root_mysql}

    read -p "Usuario MySQL [dev_user]: " mysql_user
    mysql_user=${mysql_user:-dev_user}

    read -p "Contraseña usuario MySQL [dev_password]: " mysql_password
    mysql_password=${mysql_password:-dev_password}

    echo ""
    echo -e "${CYAN}=== Configuración Opcional ===${NC}"

    read -p "Hostname para filtrar snapshots (opcional): " restic_host

    read -p "Tag para filtrar snapshots [mysqldump]: " restic_tag
    restic_tag=${restic_tag:-mysqldump}

    read -p "Días de retención para archivos SQL [7]: " retention_days
    retention_days=${retention_days:-7}

    read -p "Nombre del cluster [dev-cluster]: " cluster_name
    cluster_name=${cluster_name:-dev-cluster}

    # Crear archivo .env
    echo "🔧 Creando archivo .env..."
    cat > .env << EOF
# Copyright (c) 2025 Ariel S. Weher <ariel@weher.net>
# Este código es propietario y confidencial. Todos los derechos reservados.

# Restic Configuration (REQUIRED)
# URL del repositorio Restic (rest, sftp, s3, etc.)
RESTIC_REPOSITORY=$restic_repo

# Contraseña del repositorio Restic
RESTIC_PASSWORD=$restic_password

# Lista de bases de datos a restaurar (separadas por comas)
DB_LIST=$db_list

# Hostname para filtrar snapshots (opcional)
EOF

    if [ -n "$restic_host" ]; then
        echo "RESTIC_HOST=$restic_host" >> .env
    else
        echo "# RESTIC_HOST=hostname-servidor.domain.com" >> .env
    fi

    cat >> .env << EOF

# Tag para filtrar snapshots (por defecto: mysqldump)
RESTIC_TAG=$restic_tag

# Snapshot específico a usar (opcional, por defecto usa el más reciente)
# RESTIC_SNAPSHOT=a58161e7

# Ruta base en el snapshot donde están los dumps (opcional)
# DUMPS_BASE_PATH=/mysql_dumps

# SQL Files Retention (días)
# Número de días para mantener archivos SQL descargados localmente
SQLFILES_RETENTION_DAYS=$retention_days

# MySQL Configuration
# Contraseña del usuario root de MySQL
MYSQL_ROOT_PASSWORD=$mysql_root_password

# Usuario adicional de MySQL (opcional)
MYSQL_USER=$mysql_user
MYSQL_PASSWORD=$mysql_password

# Base de datos por defecto (opcional)
# MYSQL_DATABASE=default_db

# PXC Cluster (Optional)
# Nombre del cluster Percona XtraDB Cluster
CLUSTER_NAME=$cluster_name

# Contraseña para XtraBackup (opcional)
# XTRABACKUP_PASSWORD=backup_password
EOF

    echo -e "${GREEN}✅ Archivo .env creado correctamente${NC}"
    echo -e "${YELLOW}📝 Puedes editar .env manualmente si necesitas ajustar algún valor${NC}"
    echo ""

    return 0
}

# Función para mostrar el estado del entorno
show_status() {
    echo -e "${BLUE}=== Estado del Entorno ===${NC}"
    
    # Verificar si existe docker-compose.yml
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${RED}❌ Archivo $COMPOSE_FILE no encontrado${NC}"
        return 1
    fi
    
    # Verificar estado de los contenedores
    local mysql_status=$(docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.Status}}" 2>/dev/null || echo "No existe")
    local phpmyadmin_status=$(docker ps -a --filter "name=$PHPMYADMIN_CONTAINER" --format "{{.Status}}" 2>/dev/null || echo "No existe")
    
    echo -n "MySQL Container: "
    if [[ "$mysql_status" == *"Up"* ]]; then
        echo -e "${GREEN}🟢 Ejecutándose${NC}"
        echo "   └─ Puerto: 3306"
        echo "   └─ Estado: $mysql_status"
    elif [[ "$mysql_status" == *"Exited"* ]]; then
        echo -e "${YELLOW}🟡 Detenido${NC}"
        echo "   └─ Estado: $mysql_status"
    else
        echo -e "${RED}❌ No existe${NC}"
    fi
    
    echo -n "phpMyAdmin: "
    if [[ "$phpmyadmin_status" == *"Up"* ]]; then
        echo -e "${GREEN}🟢 Ejecutándose${NC}"
        echo "   └─ URL: http://localhost:8080"
        echo "   └─ Estado: $phpmyadmin_status"
    elif [[ "$phpmyadmin_status" == *"Exited"* ]]; then
        echo -e "${YELLOW}🟡 Detenido${NC}"
        echo "   └─ Estado: $phpmyadmin_status"
    else
        echo -e "${RED}❌ No existe${NC}"
    fi
    
    # Mostrar volúmenes
    local volumes=$(docker volume ls --filter "name=backup_mysql_dev_data" --format "{{.Name}}" 2>/dev/null || echo "")
    echo -n "Volúmenes: "
    if [ -n "$volumes" ]; then
        echo -e "${GREEN}✅ Datos persistentes guardados${NC}"
        echo "   └─ Volumen: backup_mysql_dev_data"
    else
        echo -e "${YELLOW}⚠️  Sin datos persistentes${NC}"
    fi
    
    echo ""
}

# Función para iniciar el entorno
start_environment() {
    echo -e "${BLUE}=== Iniciando Entorno ===${NC}"

    # Verificar si el archivo .env existe
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}⚠️  Archivo .env no encontrado${NC}"
        read -p "¿Deseas crear el archivo .env ahora? (S/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if ! create_env_file; then
                return 1
            fi
        else
            echo -e "${YELLOW}Por favor, crea manualmente .env desde .env.example${NC}"
            return 1
        fi
    fi

    # Verificar que existan archivos SQL para las bases de datos requeridas
    echo "🔍 Verificando archivos SQL para las bases de datos configuradas..."

    # Cargar configuración para obtener DB_LIST
    if [ -f ".env" ]; then
        source .env
    fi

    local missing_dbs=()
    local found_dbs=()
    local outdated_files=0

    if [ -n "$DB_LIST" ] && [ -d "sqlfiles" ]; then
        # Verificar cada base de datos en DB_LIST
        IFS=',' read -r -a DBS <<< "$DB_LIST"
        for db in "${DBS[@]}"; do
            db_trim="$(echo "$db" | xargs)"

            # Buscar archivos SQL para esta base de datos
            local sql_files=($(find sqlfiles -name "${db_trim}*.sql" -type f 2>/dev/null))

            if [ ${#sql_files[@]} -eq 0 ]; then
                missing_dbs+=("$db_trim")
            else
                found_dbs+=("$db_trim")

                # Verificar si los archivos son antiguos (más de 7 días)
                local newest_file=$(find sqlfiles -name "${db_trim}*.sql" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
                if [ -n "$newest_file" ]; then
                    local file_age=$((($(date +%s) - $(stat -c %Y "$newest_file" 2>/dev/null || echo 0)) / 86400))
                    if [ "$file_age" -gt 7 ]; then
                        ((outdated_files++))
                    fi
                fi
            fi
        done
    fi

    # Mostrar estado de los archivos
    if [ ${#found_dbs[@]} -gt 0 ]; then
        echo -e "${GREEN}✅ Archivos SQL encontrados para: ${found_dbs[*]}${NC}"
        for db in "${found_dbs[@]}"; do
            local sql_files=($(find sqlfiles -name "${db}*.sql" -type f 2>/dev/null))
            local newest_file=$(find sqlfiles -name "${db}*.sql" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
            if [ -n "$newest_file" ]; then
                local file_date=$(stat -c %y "$newest_file" 2>/dev/null | cut -d' ' -f1)
                echo "   └─ $db: $(basename "$newest_file") (${file_date})"
            fi
        done
    fi

    if [ ${#missing_dbs[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Archivos SQL faltantes para: ${missing_dbs[*]}${NC}"
    fi

    if [ "$outdated_files" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  $outdated_files archivo(s) tienen más de 7 días de antigüedad${NC}"
    fi

    # Decisión sobre qué hacer
    if [ ${#missing_dbs[@]} -gt 0 ] || [ "$outdated_files" -gt 0 ]; then
        echo ""
        echo -e "${CYAN}Opciones disponibles:${NC}"
        echo "1) Buscar y descargar snapshots actualizados desde Restic"
        echo "2) Continuar con los archivos SQL existentes"
        if [ ${#missing_dbs[@]} -gt 0 ]; then
            echo "3) Continuar sin las bases de datos faltantes (MySQL iniciará parcialmente)"
        fi
        echo ""

        read -p "¿Deseas buscar snapshots actualizados en Restic? (S/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "📥 Buscando y descargando snapshots actualizados..."
            if ./scripts/download-sql-files.sh; then
                echo -e "${GREEN}✅ Archivos SQL actualizados desde Restic${NC}"

                # Verificar nuevamente después de la descarga
                local final_missing=()
                for db in "${missing_dbs[@]}"; do
                    if [ ! -f "sqlfiles/${db}"*.sql ]; then
                        final_missing+=("$db")
                    fi
                done

                if [ ${#final_missing[@]} -gt 0 ]; then
                    echo -e "${YELLOW}⚠️  Aún faltan archivos para: ${final_missing[*]}${NC}"
                    echo -e "${YELLOW}⚠️  Estas bases de datos no se crearán al inicializar MySQL${NC}"
                fi
            else
                echo -e "${RED}❌ Error descargando archivos desde Restic${NC}"
                echo -e "${YELLOW}Continuando con archivos existentes...${NC}"
            fi
        else
            echo -e "${YELLOW}Continuando con archivos SQL existentes...${NC}"
        fi
    elif [ ! -d "sqlfiles" ] || [ -z "$(ls -A sqlfiles/*.sql 2>/dev/null)" ]; then
        echo -e "${RED}❌ No se encontraron archivos SQL en ./sqlfiles/${NC}"
        echo -e "${YELLOW}⚠️  Los contenedores MySQL necesitan archivos SQL para inicializar las bases de datos${NC}"
        echo ""
        echo "Opciones disponibles:"
        echo "1) Ejecutar primero 'Actualizar bases de datos' para descargar desde Restic"
        echo "2) Colocar manualmente archivos .sql en el directorio ./sqlfiles/"
        echo "3) Continuar sin archivos SQL (MySQL iniciará vacío)"
        echo ""

        read -p "¿Deseas continuar sin archivos SQL? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}❌ Inicio cancelado${NC}"
            echo -e "${CYAN}💡 Tip: Usa la opción 'Actualizar bases de datos' para descargar archivos SQL${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Continuando sin archivos SQL - MySQL iniciará vacío${NC}"
        fi
    else
        echo -e "${GREEN}✅ Todos los archivos SQL están disponibles y actualizados${NC}"
    fi

    echo ""
    echo "🚀 Iniciando contenedores..."
    
    # Iniciar solo MySQL
    if docker compose up -d mysql-dev; then
        echo -e "${GREEN}✅ MySQL container iniciado${NC}"
        
        # Preguntar si desea iniciar phpMyAdmin
        read -p "¿Deseas iniciar phpMyAdmin también? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            echo "🚀 Iniciando phpMyAdmin..."
            if docker compose --profile admin up -d phpmyadmin; then
                echo -e "${GREEN}✅ phpMyAdmin iniciado en http://localhost:8080${NC}"
            else
                echo -e "${RED}❌ Error iniciando phpMyAdmin${NC}"
            fi
        fi
        
        echo ""
        echo -e "${CYAN}=== Información de Conexión ===${NC}"
        echo "MySQL Host: localhost"
        echo "MySQL Port: 3306"
        echo "MySQL User: $(grep MYSQL_USER .env | cut -d'=' -f2 | tr -d '"' || echo 'dev_user')"
        echo "MySQL Root Password: $(grep MYSQL_ROOT_PASSWORD .env | cut -d'=' -f2 | tr -d '"' || echo 'backup_dev_2024')"
        echo ""
        echo "Para ver logs en tiempo real: docker logs $CONTAINER_NAME -f"
    else
        echo -e "${RED}❌ Error iniciando el entorno${NC}"
        return 1
    fi
}

# Función para detener el entorno
stop_environment() {
    echo -e "${BLUE}=== Deteniendo Entorno ===${NC}"
    
    echo "🛑 Deteniendo contenedores..."
    if docker compose down; then
        echo -e "${GREEN}✅ Entorno detenido correctamente${NC}"
        echo -e "${YELLOW}📝 Los datos se mantienen en el volumen persistente${NC}"
    else
        echo -e "${RED}❌ Error deteniendo el entorno${NC}"
        return 1
    fi
}

# Función para visualizar logs
view_logs() {
    echo -e "${BLUE}=== Visualizando Logs ===${NC}"
    
    local mysql_running=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null || echo "")
    
    if [ -z "$mysql_running" ]; then
        echo -e "${RED}❌ Container MySQL no está ejecutándose${NC}"
        echo "Mostrando últimos logs disponibles..."
        docker logs "$CONTAINER_NAME" --tail 50 2>/dev/null || {
            echo -e "${RED}❌ No se pudieron obtener los logs${NC}"
            return 1
        }
    else
        echo -e "${GREEN}📋 Mostrando logs en tiempo real...${NC}"
        echo -e "${YELLOW}Presiona Ctrl+C para salir${NC}"
        echo ""
        docker logs "$CONTAINER_NAME" -f
    fi
}

# Función para actualizar bases de datos
update_databases() {
    echo -e "${BLUE}=== Actualizando Bases de Datos ===${NC}"
    
    # Verificar si el archivo .env existe
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}⚠️  Archivo .env no encontrado${NC}"
        read -p "¿Deseas crear el archivo .env ahora? (S/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if ! create_env_file; then
                return 1
            fi
        else
            echo -e "${YELLOW}Por favor, crea manualmente .env desde .env.example${NC}"
            return 1
        fi
    fi

    # Verificar variables necesarias
    source .env
    if [ -z "$RESTIC_REPOSITORY" ] || [ -z "$RESTIC_PASSWORD" ] || [ -z "$DB_LIST" ]; then
        echo -e "${RED}❌ Variables RESTIC_REPOSITORY, RESTIC_PASSWORD o DB_LIST no configuradas en .env${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}⚠️  ADVERTENCIA: Esta acción reemplazará TODAS las bases de datos actuales${NC}"
    echo -e "${YELLOW}⚠️  con las versiones más recientes del repositorio Restic${NC}"
    echo ""
    echo "Bases de datos a actualizar: $DB_LIST"
    echo "Repositorio: $RESTIC_REPOSITORY"
    echo ""
    
    read -p "¿Deseas continuar? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}❌ Operación cancelada${NC}"
        return 0
    fi
    
    # Paso 1: Descargar nuevos archivos SQL
    echo "📥 Paso 1/4: Descargando archivos SQL actualizados..."
    if ! ./scripts/download-sql-files.sh; then
        echo -e "${RED}❌ Error descargando archivos SQL${NC}"
        return 1
    fi
    
    # Paso 2: Detener contenedores si están ejecutándose
    local mysql_running=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null || echo "")
    if [ -n "$mysql_running" ]; then
        echo "🛑 Paso 2/4: Deteniendo contenedores..."
        docker compose down
    else
        echo "📝 Paso 2/4: Contenedores ya están detenidos"
    fi
    
    # Paso 3: Eliminar volumen de datos (reinicialización)
    echo "🗑️  Paso 3/4: Eliminando datos antiguos..."
    docker volume rm backup_mysql_dev_data 2>/dev/null || true
    
    # Paso 4: Crear contenedor temporal para importar SQL
    echo "🔄 Paso 4/4: Importando nuevas bases de datos..."
    
    # Verificar que existan archivos SQL descargados
    if [ ! -d "sqlfiles" ] || [ -z "$(ls -A sqlfiles 2>/dev/null)" ]; then
        echo -e "${RED}❌ No se encontraron archivos SQL descargados${NC}"
        return 1
    fi
    
    # Crear directorio temporal para init scripts
    local temp_init_dir=$(mktemp -d)
    
    # Copiar archivos SQL al directorio temporal con nombres adecuados para MySQL init
    echo "📋 Preparando archivos SQL para importación..."
    local counter=50
    for db_name in $(echo $DB_LIST | tr ',' ' '); do
        # Buscar el archivo SQL más reciente para esta base de datos
        local sql_file=$(find sqlfiles -name "${db_name}_*.sql" -type f | sort | tail -1)
        if [ -n "$sql_file" ] && [ -f "$sql_file" ]; then
            echo "   ├─ Preparando $db_name desde $(basename $sql_file)"
            # Crear script que crea la DB y luego importa
            cat > "$temp_init_dir/${counter}-${db_name}.sql" << EOF
-- Crear base de datos ${db_name}
CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
USE \`${db_name}\`;

-- Importar contenido
$(cat "$sql_file")
EOF
            ((counter++))
        else
            echo -e "${RED}   ├─ ❌ No se encontró archivo SQL para $db_name${NC}"
        fi
    done
    
    # Iniciar contenedor temporal para importar
    echo "🚀 Iniciando MySQL temporal para importación..."
    if docker run --rm \
        -v "$temp_init_dir:/docker-entrypoint-initdb.d:ro" \
        -v "backup_mysql_dev_data:/var/lib/mysql" \
        -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
        -e MYSQL_USER="$MYSQL_USER" \
        -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
        percona/percona-xtradb-cluster:5.7 \
        mysqld --initialize-insecure; then
        
        echo -e "${GREEN}✅ Bases de datos actualizadas correctamente${NC}"
        echo -e "${CYAN}📝 Puedes iniciar el entorno normalmente ahora${NC}"
    else
        echo -e "${RED}❌ Error durante la importación de las bases de datos${NC}"
        rm -rf "$temp_init_dir"
        return 1
    fi
    
    # Limpiar directorio temporal
    rm -rf "$temp_init_dir"
    
    echo ""
    echo -e "${GREEN}🎉 Actualización completada${NC}"
    echo "Bases de datos actualizadas: $DB_LIST"
    echo "Para conectarte, usa la opción 'Iniciar entorno'"
}

# Función para diagnosticar repositorio Restic
diagnose_restic_repository() {
    echo -e "${BLUE}=== Diagnóstico Repositorio Restic ===${NC}"

    # Verificar si el archivo .env existe
    if [ ! -f ".env" ]; then
        echo -e "${RED}❌ Archivo .env no encontrado${NC}"
        return 1
    fi

    # Cargar variables
    source .env
    if [ -z "$RESTIC_REPOSITORY" ] || [ -z "$RESTIC_PASSWORD" ]; then
        echo -e "${RED}❌ Variables RESTIC_REPOSITORY o RESTIC_PASSWORD no configuradas en .env${NC}"
        return 1
    fi

    export RESTIC_PASSWORD
    export RESTIC_CACHE_DIR="${HOME}/.cache/restic"

    echo "📡 Conectando al repositorio: $RESTIC_REPOSITORY"
    echo ""

    # Verificar conectividad básica
    echo "🔍 Verificando conectividad..."
    if ! restic -r "$RESTIC_REPOSITORY" snapshots >/dev/null 2>&1; then
        echo -e "${RED}❌ No se pudo conectar al repositorio${NC}"
        echo "Verifica las credenciales y la conectividad de red"
        return 1
    fi
    echo -e "${GREEN}✅ Conectividad OK${NC}"
    echo ""

    # Mostrar estadísticas del repositorio
    echo "📊 Estadísticas del repositorio:"
    restic -r "$RESTIC_REPOSITORY" stats --quiet || echo "No se pudieron obtener estadísticas"
    echo ""

    # Listar todos los snapshots con sus tags
    echo "📋 Snapshots disponibles:"
    restic -r "$RESTIC_REPOSITORY" snapshots --compact || {
        echo -e "${RED}❌ No se pudieron listar los snapshots${NC}"
        return 1
    }
    echo ""

    # Mostrar tags únicos disponibles
    echo "🏷️  Tags disponibles en el repositorio:"
    restic -r "$RESTIC_REPOSITORY" snapshots --json 2>/dev/null | \
        jq -r '.[].tags[]?' 2>/dev/null | sort -u | \
        while read -r tag; do
            [ -n "$tag" ] && echo "   └─ $tag"
        done || echo "   └─ No se pudieron obtener los tags"
    echo ""

    # Verificar snapshots específicos para las bases de datos configuradas
    if [ -n "$DB_LIST" ]; then
        echo "🔍 Buscando snapshots para bases de datos configuradas:"
        IFS=',' read -r -a DBS <<< "$DB_LIST"
        for db in "${DBS[@]}"; do
            db_trim="$(echo "$db" | xargs)"
            echo "   🗄️  Base de datos: $db_trim"

            # Buscar con tag exacto
            local count_exact=$(restic -r "$RESTIC_REPOSITORY" snapshots --tag "$db_trim" --json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
            echo "      └─ Con tag '$db_trim': $count_exact snapshot(s)"

            # Buscar con tag mysqldump
            local count_mysqldump=$(restic -r "$RESTIC_REPOSITORY" snapshots --tag "mysqldump" --json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
            echo "      └─ Con tag 'mysqldump': $count_mysqldump snapshot(s)"

            # Buscar con hostname si está configurado
            if [ -n "$RESTIC_HOST" ]; then
                local count_host=$(restic -r "$RESTIC_REPOSITORY" snapshots --host "$RESTIC_HOST" --json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
                echo "      └─ Con hostname '$RESTIC_HOST': $count_host snapshot(s)"
            fi
        done
    fi

    echo ""
    echo -e "${CYAN}💡 Recomendaciones:${NC}"
    echo "   • Si no hay snapshots con tags específicos de BD, modifica RESTIC_TAG en .env"
    echo "   • Verifica que el hostname en RESTIC_HOST coincida con el servidor de backup"
    echo "   • Los snapshots deben contener archivos /<database_name>.sql en la raíz"
}

# Función para descargar archivo SQL desde URL
download_sql_from_url() {
    echo -e "${BLUE}=== Descargar SQL desde URL ===${NC}"

    # Verificar comandos disponibles
    local download_cmd=""
    local download_args=""

    if command -v axel &> /dev/null; then
        download_cmd="axel"
        download_args="-a"
        echo -e "${GREEN}✅ Usando axel (descarga acelerada)${NC}"
    elif command -v wget &> /dev/null; then
        download_cmd="wget"
        download_args="-O"
        echo -e "${GREEN}✅ Usando wget${NC}"
    elif command -v curl &> /dev/null; then
        download_cmd="curl"
        download_args="-L -o"
        echo -e "${GREEN}✅ Usando curl${NC}"
    else
        echo -e "${RED}❌ No se encontró ningún comando de descarga disponible${NC}"
        echo -e "${YELLOW}Por favor, instala curl, wget o axel${NC}"
        return 1
    fi

    echo ""
    read -p "URL del archivo SQL: " sql_url

    if [ -z "$sql_url" ]; then
        echo -e "${RED}❌ URL no puede estar vacía${NC}"
        return 1
    fi

    # Validar que la URL parece válida
    if [[ ! "$sql_url" =~ ^https?:// ]]; then
        echo -e "${YELLOW}⚠️  La URL no parece válida (debe comenzar con http:// o https://)${NC}"
        read -p "¿Deseas continuar de todas formas? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}❌ Descarga cancelada${NC}"
            return 0
        fi
    fi

    # Extraer nombre del archivo o solicitar uno
    local filename=$(basename "$sql_url")
    if [[ ! "$filename" =~ \.sql$ ]] || [ ${#filename} -lt 5 ]; then
        read -p "Nombre del archivo (con extensión .sql): " custom_filename
        if [ -n "$custom_filename" ]; then
            if [[ ! "$custom_filename" =~ \.sql$ ]]; then
                custom_filename="${custom_filename}.sql"
            fi
            filename="$custom_filename"
        else
            filename="downloaded_$(date +%Y%m%d_%H%M%S).sql"
            echo -e "${YELLOW}Usando nombre automático: $filename${NC}"
        fi
    fi

    # Crear directorio sqlfiles si no existe
    if [ ! -d "sqlfiles" ]; then
        echo "📁 Creando directorio sqlfiles..."
        mkdir -p sqlfiles
    fi

    local filepath="sqlfiles/$filename"

    # Verificar si el archivo ya existe
    if [ -f "$filepath" ]; then
        echo -e "${YELLOW}⚠️  El archivo $filename ya existe${NC}"
        read -p "¿Deseas sobrescribirlo? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}❌ Descarga cancelada${NC}"
            return 0
        fi
    fi

    echo ""
    echo "📥 Descargando archivo SQL..."
    echo "   └─ URL: $sql_url"
    echo "   └─ Destino: $filepath"
    echo "   └─ Comando: $download_cmd"
    echo ""

    # Ejecutar descarga según el comando disponible
    case "$download_cmd" in
        "axel")
            if axel -a "$sql_url" -o "$filepath"; then
                download_success=true
            else
                download_success=false
            fi
            ;;
        "wget")
            if wget -O "$filepath" "$sql_url"; then
                download_success=true
            else
                download_success=false
            fi
            ;;
        "curl")
            if curl -L -o "$filepath" "$sql_url"; then
                download_success=true
            else
                download_success=false
            fi
            ;;
    esac

    if [ "$download_success" = true ]; then
        # Verificar que el archivo se descargó y tiene contenido
        if [ -f "$filepath" ] && [ -s "$filepath" ]; then
            local file_size=$(du -h "$filepath" | cut -f1)
            echo -e "${GREEN}✅ Descarga completada${NC}"
            echo "   └─ Archivo: $filepath"
            echo "   └─ Tamaño: $file_size"

            # Verificar que parece ser un archivo SQL válido
            if head -n 5 "$filepath" | grep -i -E "(create|insert|drop|use|database)" > /dev/null; then
                echo -e "${GREEN}   └─ ✓ El archivo parece contener SQL válido${NC}"
            else
                echo -e "${YELLOW}   └─ ⚠️  El archivo puede no contener SQL válido${NC}"
                echo "       Primeras líneas del archivo:"
                head -n 3 "$filepath" | sed 's/^/       /'
            fi
        else
            echo -e "${RED}❌ Error: El archivo se descargó pero está vacío${NC}"
            rm -f "$filepath" 2>/dev/null
            return 1
        fi
    else
        echo -e "${RED}❌ Error durante la descarga${NC}"
        rm -f "$filepath" 2>/dev/null
        return 1
    fi

    echo ""
    echo -e "${CYAN}💡 Tip: Ahora puedes usar 'Iniciar entorno' para cargar la base de datos${NC}"
}

# Función para eliminar el entorno completamente
remove_environment() {
    echo -e "${BLUE}=== Eliminando Entorno ===${NC}"
    echo -e "${RED}⚠️  ADVERTENCIA: Esta acción eliminará TODOS los datos de la base de datos${NC}"
    echo -e "${RED}⚠️  Esta operación NO se puede deshacer${NC}"
    echo ""
    
    read -p "¿Estás seguro de que deseas eliminar TODO el entorno? (escribe 'SI' para confirmar): " confirmation
    
    if [ "$confirmation" = "SI" ]; then
        echo "🗑️  Eliminando contenedores..."
        docker compose down -v --remove-orphans 2>/dev/null || true
        
        echo "🗑️  Eliminando imágenes..."
        docker rmi $(docker images --filter "reference=backup-mysql-dev*" -q) 2>/dev/null || true
        
        echo "🗑️  Eliminando volúmenes..."
        docker volume rm backup_mysql_dev_data 2>/dev/null || true
        
        echo "🗑️  Eliminando redes..."
        docker network rm backup-dev-network 2>/dev/null || true
        
        echo -e "${GREEN}✅ Entorno eliminado completamente${NC}"
        echo -e "${YELLOW}📝 Para volver a usar, ejecuta la opción 'Iniciar'${NC}"
    else
        echo -e "${YELLOW}❌ Operación cancelada${NC}"
    fi
}

# Función para mostrar el menú principal
show_menu() {
    echo -e "${CYAN}Selecciona una opción:${NC}"
    echo ""
    echo "1) 🚀 Iniciar entorno"
    echo "2) 🛑 Detener entorno"
    echo "3) 📋 Visualizar logs"
    echo "4) 📊 Mostrar estado"
    echo "5) 🔄 Actualizar bases de datos"
    echo "6) 📥 Descargar SQL desde URL"
    echo "7) 🔍 Diagnosticar repositorio Restic"
    echo "8) 🗑️  Eliminar entorno (⚠️  PELIGROSO)"
    echo "9) ❌ Salir"
    echo ""
    echo -n "Opción [1-9]: "
}

# Función principal
main() {
    while true; do
        clear
        show_header
        show_status
        show_menu
        
        read -r choice
        echo ""
        
        case $choice in
            1)
                start_environment
                ;;
            2)
                stop_environment
                ;;
            3)
                view_logs
                ;;
            4)
                echo "🔄 Actualizando estado..."
                sleep 1
                continue
                ;;
            5)
                update_databases
                ;;
            6)
                download_sql_from_url
                ;;
            7)
                diagnose_restic_repository
                ;;
            8)
                remove_environment
                ;;
            9)
                echo -e "${GREEN}👋 ¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Opción inválida. Por favor selecciona 1-9.${NC}"
                ;;
        esac
        
        echo ""
        read -p "Presiona Enter para continuar..." -r
    done
}

# Verificar que Docker esté disponible
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker no está instalado o no está en el PATH${NC}"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose no está disponible${NC}"
    exit 1
fi

# Ejecutar función principal
main
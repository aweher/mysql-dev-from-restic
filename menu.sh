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
        echo -e "${RED}❌ Archivo .env no encontrado${NC}"
        echo -e "${YELLOW}Por favor, copia .env.example a .env y configura las variables${NC}"
        return 1
    fi
    
    echo "🚀 Iniciando contenedores..."
    
    # Iniciar solo MySQL
    if docker compose up -d mysql-dev; then
        echo -e "${GREEN}✅ MySQL container iniciado${NC}"
        
        # Preguntar si desea iniciar phpMyAdmin
        read -p "¿Deseas iniciar phpMyAdmin también? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
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
        echo -e "${RED}❌ Archivo .env no encontrado${NC}"
        echo -e "${YELLOW}Por favor, copia .env.example a .env y configura las variables${NC}"
        return 1
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
    
    read -p "¿Deseas continuar? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
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
    echo "6) 🗑️  Eliminar entorno (⚠️  PELIGROSO)"
    echo "7) ❌ Salir"
    echo ""
    echo -n "Opción [1-7]: "
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
                remove_environment
                ;;
            7)
                echo -e "${GREEN}👋 ¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Opción inválida. Por favor selecciona 1-7.${NC}"
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
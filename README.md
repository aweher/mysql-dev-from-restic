<!--
Copyright (c) 2025 Ariel S. Weher <ariel@weher.net>
Este código es propietario y confidencial. Todos los derechos reservados.
-->

# Backup MySQL Dev - Restore from Backup

Sistema completo de restauración de bases de datos MySQL desde backups almacenados en Restic para entornos de desarrollo, con interfaz de línea de comandos interactiva.

## Descripción

Este proyecto crea un contenedor MySQL basado en Percona XtraDB Cluster que automáticamente:

1. **Descarga dumps SQL** desde un repositorio Restic al inicializar
2. **Importa las bases de datos** durante el primer arranque
3. **Configura MySQL** con ajustes optimizados para desarrollo

## Arquitectura

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Restic Repo   │───▶│  Docker Init     │───▶│   MySQL Ready   │
│                 │    │                  │    │                 │
│ /db1.sql        │    │ 1. Fetch dumps   │    │ • db1 imported  │
│ /db2.sql        │    │ 2. Import DBs    │    │ • db2 imported  │
│ /db3.sql        │    │ 3. Start MySQL   │    │ • Ready to use  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Características Principales

- **🚀 Inicio rápido**: Menú interactivo para gestión completa del entorno
- **📦 Verificación inteligente**: Detecta archivos SQL faltantes o desactualizados
- **🔄 Actualización automática**: Descarga snapshots recientes desde Restic
- **🐳 Docker Compose**: Configuración completa con phpMyAdmin opcional
- **🛠️ Configuración asistida**: Creación automática de archivos `.env`
- **📊 Diagnósticos**: Herramientas para verificar repositorio Restic
- **📥 Descarga desde URL**: Capacidad de importar SQL desde URLs externas

## Estructura del Proyecto

```
├── Dockerfile                      # Imagen MySQL con Restic
├── docker-compose.yml             # Orquestación de servicios
├── menu.sh                        # 🎯 Interfaz principal interactiva
├── scripts/
│   ├── build-fetch-sql.sh         # Script de construcción
│   └── download-sql-files.sh      # Descarga desde Restic
├── config/
│   └── pxc-tweaks.cnf             # Configuración MySQL optimizada
├── sqlfiles/                      # 📁 Archivos SQL descargados
├── .env.example                   # Plantilla de configuración
└── README.md
```

## Variables de Entorno

### Obligatorias

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `RESTIC_REPOSITORY` | URL del repositorio Restic | `rest:https://restic.example.com/repo` |
| `RESTIC_PASSWORD` | Password del repositorio | `mi_password_secreto` |
| `DB_LIST` | Lista de bases de datos (separadas por coma) | `backup,intranet,apigateway` |

### Opcionales

| Variable | Descripción | Default | Ejemplo |
|----------|-------------|---------|---------|
| `DUMPS_BASE_PATH` | Ruta base en Restic donde están los dumps | `/mysql_dumps` | `/backups/mysql` |
| `RESTIC_HOST` | Filtrar por hostname específico | *(sin filtro)* | `pxc3.dc.backup.net.ar` |
| `RESTIC_TAG` | Filtrar por tag específico | *(sin filtro)* | `mysqldump` |
| `RESTIC_SNAPSHOT` | ID de snapshot específico a usar | *(último disponible)* | `a58161e7` |

## 🚀 Inicio Rápido

### Método Recomendado: Menú Interactivo

```bash
# 1. Clonar o descargar el proyecto
cd backup-mysql-dev-mysql-dev-frombackup

# 2. Ejecutar el menú principal
./menu.sh
```

El menú interactivo te guiará paso a paso para:
- ✅ Crear archivo `.env` con configuración asistida
- ✅ Verificar conectividad con Restic
- ✅ Descargar bases de datos automáticamente
- ✅ Iniciar el entorno completo

### Opciones del Menú Principal

```
============================================
    Backup MySQL Dev - Control Panel
============================================

1) 🚀 Iniciar entorno
2) 🛑 Detener entorno
3) 📋 Visualizar logs
4) 📊 Mostrar estado
5) 🔄 Actualizar bases de datos
6) 📥 Descargar SQL desde URL
7) 🔍 Diagnosticar repositorio Restic
8) 🗑️  Eliminar entorno (⚠️  PELIGROSO)
9) ❌ Salir
```

### Configuración Manual (Avanzado)

Si prefieres configurar manualmente:

```bash
# 1. Crear archivo .env desde la plantilla
cp .env.example .env

# 2. Editar configuración
nano .env

# 3. Iniciar con Docker Compose
docker compose up --build -d
```

## Funcionamiento

### Proceso de Inicialización Inteligente

Cuando ejecutas "🚀 Iniciar entorno", el sistema realiza:

1. **🔍 Verificación de Archivos SQL**:
   - Revisa si existen archivos SQL para cada BD en `DB_LIST`
   - Detecta archivos desactualizados (>7 días)
   - Muestra estado detallado con fechas

2. **🤖 Decisión Automática**:
   - Si hay archivos faltantes/antiguos → Pregunta si actualizar desde Restic
   - Si todos están actualizados → Continúa directamente
   - Opción por defecto: Sí actualizar `(S/n)`

3. **📥 Descarga Inteligente** (si se solicita):
   - Ejecuta `scripts/download-sql-files.sh`
   - Busca snapshots más recientes en Restic
   - Verifica qué archivos siguen faltando

4. **🚀 Inicio de Servicios**:
   - Inicia MySQL con archivos SQL actualizados
   - Pregunta opcionalmente por phpMyAdmin
   - Muestra información de conexión

### Arquitectura del Sistema

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Restic Repo   │───▶│  Smart Checker   │───▶│   MySQL Ready   │
│                 │    │                  │    │                 │
│ Snapshots con   │    │ • Detecta falta  │    │ • BD actuales   │
│ tags mysqldump  │    │ • Verifica edad  │    │ • phpMyAdmin    │
│                 │    │ • Actualiza auto │    │ • Listo para uso│
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Estructura de Restic Esperada

```
Snapshot: a58161e7 (2025-09-11 03:15:01)
Host: pxc3.dc.backup.net.ar
Tags: [mysqldump, backup]
├── /backup.sql
├── /intranet.sql
├── /apigateway.sql
└── ...
```

## Logs

El proceso genera logs detallados:

```bash
# Ver logs del contenedor
docker logs mysql-dev

# Logs típicos durante la inicialización:
[fetch-restic] Using repository: rest:https://restic.example.com/repo
[fetch-restic] DB list: backup,intranet,apigateway
[fetch-restic] Latest snapshot id: a58161e7
[fetch-restic] Found: /backup.sql -> dumping to /docker-entrypoint-initdb.d/50-backup.sql
[fetch-restic] Done. Generated SQL files will be imported by the MySQL init process.
```

## Configuración MySQL

El contenedor incluye configuraciones optimizadas para desarrollo:

```ini
[mysqld]
# Configuración en /etc/mysql/conf.d/pxc-tweaks.cnf
sql_mode=STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
```

Esta configuración excluye `ONLY_FULL_GROUP_BY` para mayor compatibilidad.

## 🛠️ Herramientas de Diagnóstico

### Opción 7: Diagnosticar Repositorio Restic

Desde el menú principal, esta opción realiza:

```
🔍 Diagnosticar repositorio Restic
├── ✅ Verificar conectividad al repositorio
├── 📊 Mostrar estadísticas (tamaño, snapshots)
├── 📋 Listar todos los snapshots disponibles
├── 🏷️  Mostrar tags únicos en el repositorio
└── 🔍 Buscar snapshots específicos para tus BDs
```

### Comandos de Diagnóstico Manual

```bash
# 1. Verificar conectividad básica
./menu.sh  # Opción 7

# 2. Ver logs en tiempo real
./menu.sh  # Opción 3

# 3. Verificar estado completo
./menu.sh  # Opción 4
```

## 🚨 Solución de Problemas

### ❌ Error: "no snapshot found matching filters"

**Causa**: El filtro `RESTIC_HOST` no coincide con el hostname real.

**Solución**:
1. Ejecutar `./menu.sh` → Opción 7 (Diagnosticar Restic)
2. Verificar el hostname real en la lista de snapshots
3. Corregir `RESTIC_HOST` en archivo `.env`

### ❌ Error: "no .sql found for DB"

**Causa**: La base de datos no existe en el snapshot o el nombre no coincide.

**Solución**:
1. Usar diagnóstico Restic para ver snapshots disponibles
2. Verificar que existe `/<database_name>.sql` en el snapshot
3. Ajustar `DB_LIST` en `.env` con nombres exactos

### 🐳 MySQL no inicia o falla la importación

**Diagnosis**:
```bash
./menu.sh  # Opción 3 para ver logs
```

**Soluciones comunes**:
- Verificar que los archivos SQL son válidos
- Comprobar permisos del volumen de datos
- Reiniciar eliminando el volumen: Opción 8 (Eliminar entorno)

## 🛡️ Características de Seguridad

- **🔐 Credenciales seguras**: Las credenciales Restic no se almacenan en la imagen
- **🗂️ Datos persistentes**: Volúmenes Docker para mantener datos entre reinicios
- **🚫 No hardcoding**: Todas las credenciales via variables de entorno
- **🔄 Limpieza automática**: Archivos temporales se eliminan después de la importación
- **👤 Usuarios MySQL**: Configuración de usuarios no-root para desarrollo

## 📋 Casos de Uso

### 1. Desarrollador Individual
```bash
# Configurar una vez
./menu.sh  # Crear .env y descargar BDs

# Uso diario
./menu.sh  # Opción 1: Iniciar entorno
# ... desarrollar ...
./menu.sh  # Opción 2: Detener entorno
```

### 2. Equipo de Desarrollo
```bash
# Actualizar con datos frescos semanalmente
./menu.sh  # Opción 5: Actualizar bases de datos

# Mantener entorno corriendo
./menu.sh  # Opción 4: Mostrar estado
```

### 3. Testing con Datos Específicos
```bash
# Descargar SQL específico desde URL
./menu.sh  # Opción 6: Descargar SQL desde URL

# O usar snapshot específico
# Editar .env: RESTIC_SNAPSHOT=a58161e7
```

## 🔧 Desarrollo y Personalización

### Modificar Scripts de Descarga

```bash
# 1. Editar script de construcción
nano scripts/build-fetch-sql.sh

# 2. Editar script de descarga en tiempo real
nano scripts/download-sql-files.sh

# 3. Reconstruir para cambios en build-time
docker compose up --build -d
```

### Personalizar Configuración MySQL

```bash
# Editar configuraciones optimizadas
nano config/pxc-tweaks.cnf

# Aplicar cambios
docker compose up --build -d
```

## 🎯 Comandos Rápidos de Referencia

```bash
# Inicio completo desde cero
./menu.sh
# Seleccionar: 1 (Iniciar entorno) - Te guiará paso a paso

# Verificar si todo está funcionando
./menu.sh
# Seleccionar: 4 (Mostrar estado)

# Ver logs en tiempo real
./menu.sh
# Seleccionar: 3 (Visualizar logs)

# Actualizar bases de datos con snapshots frescos
./menu.sh
# Seleccionar: 5 (Actualizar bases de datos)

# Diagnosticar problemas con Restic
./menu.sh
# Seleccionar: 7 (Diagnosticar repositorio Restic)

# Reiniciar completamente (borra todos los datos)
./menu.sh
# Seleccionar: 8 (Eliminar entorno) - ¡CUIDADO!
```

## 📞 Conexión a MySQL

Una vez iniciado el entorno:

```bash
# Desde línea de comandos local
mysql -h 127.0.0.1 -P 3306 -u root -p
# Password: configurado en .env (MYSQL_ROOT_PASSWORD)

# O usar phpMyAdmin (si está habilitado)
# http://localhost:8080
# Usuario: root
# Password: el configurado en .env
```

## 📚 Más Información

- **Configuración**: Todos los ajustes en archivo `.env`
- **Logs**: Accesibles desde el menú (Opción 3) o `docker logs backup-mysql-dev`
- **Datos**: Persistentes en volumen Docker `backup_mysql_dev_data`
- **Red**: Servicios en red `backup-dev-network`

---

**© 2025 Ariel S. Weher - Uso interno backup-mysql-dev**
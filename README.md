<!--
Copyright (c) 2025 Ariel S. Weher <ariel@weher.net>
Este código es propietario y confidencial. Todos los derechos reservados.
-->

# Backup MySQL Dev - Restore from Backup

Docker container que restaura bases de datos MySQL desde backups almacenados en Restic para entornos de desarrollo.

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

## Estructura del Proyecto

```
├── Dockerfile
├── scripts/
│   └── 10-fetch-restic-dumps.sh    # Script de descarga desde Restic
├── config/
│   └── pxc-tweaks.cnf              # Configuración MySQL
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

## Uso

### 1. Construcción de la imagen

```bash
docker build -t backup-mysql-dev .
```

### 2. Ejecución básica

```bash
docker run -d \
  --name mysql-dev \
  -e RESTIC_REPOSITORY="rest:https://restic.example.com/repo" \
  -e RESTIC_PASSWORD="mi_password" \
  -e DB_LIST="backup,intranet,apigateway" \
  -p 3306:3306 \
  backup-mysql-dev
```

### 3. Docker Compose

```yaml
version: '3.8'

services:
  mysql-dev:
    build: .
    ports:
      - "3306:3306"
    environment:
      RESTIC_REPOSITORY: "rest:https://restic.example.com/repo"
      RESTIC_PASSWORD: "mi_password_secreto"
      DB_LIST: "backup,intranet,apigateway"
      RESTIC_HOST: "pxc3.dc.backup.net.ar"
      RESTIC_TAG: "mysqldump"
      
      # Variables MySQL estándar
      MYSQL_ROOT_PASSWORD: "root_password"
      MYSQL_USER: "dev_user"
      MYSQL_PASSWORD: "dev_password"
      
    volumes:
      - mysql_data:/var/lib/mysql
      
volumes:
  mysql_data:
```

## Funcionamiento

### Proceso de Inicialización

1. **Verificación**: Comprueba si MySQL ya está inicializado
2. **Conexión a Restic**: Se conecta al repositorio con las credenciales
3. **Selección de Snapshot**: 
   - Usa `RESTIC_SNAPSHOT` si está definido
   - Sino, busca el snapshot más reciente (con filtros opcionales)
4. **Descarga de Dumps**: Para cada base de datos en `DB_LIST`:
   - Busca `/<db_name>.sql` en el snapshot
   - Lo descarga como `/docker-entrypoint-initdb.d/50-<db_name>.sql`
5. **Importación**: MySQL importa automáticamente todos los `.sql`

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

## Solución de Problemas

### Error: "no snapshot found matching filters"

```bash
# Verificar snapshots disponibles
restic -r rest:https://restic.example.com/repo snapshots

# Verificar filtros
docker run --rm -e RESTIC_REPOSITORY="..." -e RESTIC_PASSWORD="..." \
  backup-mysql-dev restic snapshots --json | jq '.[].tags'
```

### Error: "no .sql found for DB"

- Verificar que la base de datos existe en el snapshot
- Comprobar la estructura de paths en Restic
- Revisar variable `DUMPS_BASE_PATH`

### MySQL no inicia

```bash
# Ver logs detallados
docker logs mysql-dev -f

# Verificar permisos
docker exec mysql-dev ls -la /docker-entrypoint-initdb.d/
```

## Desarrollo

### Modificar el script de fetch

1. Editar `scripts/10-fetch-restic-dumps.sh`
2. Reconstruir la imagen: `docker build -t backup-mysql-dev .`

### Agregar configuraciones MySQL

1. Editar `config/pxc-tweaks.cnf`
2. Reconstruir la imagen

## Consideraciones de Seguridad

- **Nunca hardcodear** `RESTIC_PASSWORD` en el Dockerfile
- Usar **Docker secrets** o **variables de entorno seguras**
- El contenedor **no persiste credenciales** después de la inicialización
- Los dumps descargados son **temporales** y se eliminan con el contenedor

## Licencia

Este proyecto es para uso interno de backup-mysql-dev.
# ClinicQueue — Guía de Despliegue con Docker

Sistema de gestión de turnos y filas para clínicas y centros médicos.

---

## Requisitos previos

| Herramienta | Versión mínima | Notas |
|-------------|---------------|-------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | 24.x o superior | Incluye Docker Compose v2 |
| Git | cualquier versión | Solo para clonar el repositorio |

> **Windows**: Docker Desktop debe estar en ejecución antes de correr cualquier comando.
> **Linux/Mac**: Docker Engine + Docker Compose plugin son suficientes.

---

## Instalación en 4 pasos

### 1. Descargar el proyecto

```bash
git clone <URL_DEL_REPOSITORIO> flow-connected
cd flow-connected
```

O descomprima el archivo `.zip` entregado y entre a la carpeta.

### 2. Configurar las variables de entorno

```bash
cp .env.docker.example .env
```

Abra `.env` con cualquier editor de texto y cambie **obligatoriamente**:

| Variable | Descripción |
|----------|-------------|
| `POSTGRES_PASSWORD` | Contraseña de la base de datos (evite el carácter `#`) |
| `DATABASE_URL` | Debe contener la misma contraseña que `POSTGRES_PASSWORD` |
| `JWT_SECRET` | Clave secreta para tokens de acceso (mínimo 32 caracteres) |
| `JWT_REFRESH_SECRET` | Clave secreta para tokens de refresco (mínimo 32 caracteres) |
| `PGADMIN_DEFAULT_EMAIL` | Correo de acceso a pgAdmin |
| `PGADMIN_DEFAULT_PASSWORD` | Contraseña de acceso a pgAdmin |

**Generar claves JWT aleatorias** (ejecute uno de estos comandos):
```bash
# Con Node.js
node -e "console.log(require('crypto').randomBytes(40).toString('hex'))"

# Con OpenSSL
openssl rand -hex 40
```

> **Nota importante sobre contraseñas**: No use el carácter `#` en `POSTGRES_PASSWORD`
> ni en `DATABASE_URL` — es un carácter reservado en URLs y causará error de conexión.

### 3. Levantar el sistema

```bash
docker compose up -d
```

La primera vez este comando:
1. Descarga las imágenes base de PostgreSQL, Node.js y pgAdmin (~500 MB)
2. Construye la imagen de la aplicación (~5-8 minutos)
3. Descarga el motor de TTS (síntesis de voz en español)
4. Crea e inicializa la base de datos con el schema completo

Verifique que todos los servicios estén en línea:
```bash
docker compose ps
```

Todos los servicios deben mostrar estado **Up** y el de `postgres` debe aparecer como **healthy**.

### 4. Cargar datos iniciales

```bash
docker compose exec api node apps/api/db/seeds/demo_seed.js
```

Este comando crea:
- Usuario administrador: `admin` / `admin1234`
- Usuario operador: `operator1` / `operator1234`
- Un módulo de atención de ejemplo (Consultorio 1)
- Tres estaciones de atención
- Un tablero de visualización de turnos

---

## Acceso al sistema

| Servicio | URL | Descripción |
|----------|-----|-------------|
| **Aplicación** | http://localhost:3001 | UI + API (mismo servidor) |
| **pgAdmin** | http://localhost:5050 | Administración de base de datos |

> Si cambió `API_PORT` o `PGADMIN_PORT` en `.env`, use esos puertos en lugar de 3001 y 5050.

### Primer acceso a pgAdmin

1. Ingrese con el email y contraseña definidos en `.env`
2. En el panel izquierdo expanda **Docker → ClinicQueue DB**
3. Ingrese la contraseña de PostgreSQL (`POSTGRES_PASSWORD`) cuando se solicite

---

## Comandos útiles

```bash
# Ver estado de los contenedores
docker compose ps

# Ver logs de la aplicación en tiempo real
docker compose logs -f api

# Ver logs de PostgreSQL
docker compose logs -f postgres

# Detener el sistema (conserva los datos)
docker compose down

# Reiniciar un servicio específico
docker compose restart api

# Abrir una terminal dentro del contenedor de la API
docker compose exec api sh
```

### Reinicio completo (borra todos los datos)

> ⚠️ Este comando elimina TODOS los datos almacenados. Úselo solo para reinstalar desde cero.

```bash
docker compose down -v
docker compose up -d
```

---

## Actualización del sistema

Cuando reciba una nueva versión del sistema:

```bash
# 1. Bajar el sistema actual
docker compose down

# 2. Reemplazar los archivos del proyecto (excepto .env)

# 3. Reconstruir la imagen
docker compose build --no-cache

# 4. Levantar con la nueva versión
docker compose up -d
```

---

## Puertos y red

Por defecto el sistema expone solo dos puertos en el servidor:

- **3001**: Aplicación (UI + API)
- **5050**: pgAdmin

La base de datos PostgreSQL **no está expuesta** al exterior — solo es accesible desde dentro de la red Docker interna.

Para cambiar los puertos, edite `API_PORT` y `PGADMIN_PORT` en `.env` y ejecute `docker compose up -d`.

---

## Respaldo de la base de datos

```bash
# Crear un respaldo
docker compose exec postgres pg_dump -U postgres clinicqueue_db > respaldo_$(date +%Y%m%d).sql

# Restaurar un respaldo
docker compose exec -T postgres psql -U postgres clinicqueue_db < respaldo_20260101.sql
```

---

## Solución de problemas frecuentes

### Los contenedores no arrancan / Error de contraseña en `DATABASE_URL`

**Causa**: La contraseña contiene el carácter `#`.
**Solución**: Cambie la contraseña en `.env` (tanto en `POSTGRES_PASSWORD` como en `DATABASE_URL`) por una que no contenga `#`, luego ejecute:
```bash
docker compose down -v
docker compose up -d
```

### pgAdmin no inicia / "does not appear to be a valid email"

**Causa**: El email en `PGADMIN_DEFAULT_EMAIL` no tiene un dominio válido (ej. `.local`).
**Solución**: Use un dominio real como `.com` o `.net` (ej. `admin@miempresa.com`).

### La aplicación carga pero no puede conectarse a la API

**Causa**: El contenedor de la API aún está iniciando o esperando a PostgreSQL.
**Solución**: Espere 30-60 segundos y recargue. Verifique con `docker compose ps` que `api` esté en estado **healthy**.

### Error al cargar datos de demo: "column does not exist"

**Causa**: La base de datos no se reinicializó después de un cambio de schema.
**Solución**:
```bash
docker compose down -v
docker compose up -d
# Esperar que postgres esté healthy, luego:
docker compose exec api node apps/api/db/seeds/demo_seed.js
```

---

## Arquitectura

```
Servidor (host)
├── :3001  ──→  contenedor API (Node.js + Fastify)
│                  ├── Sirve el UI (SvelteKit compilado, modo SPA)
│                  ├── API REST en /api/*
│                  └── WebSocket para actualizaciones en tiempo real
│                         └── se conecta a postgres:5432 (interno)
└── :5050  ──→  contenedor pgAdmin
                   └── se conecta a postgres:5432 (interno)

Red interna Docker:
└── postgres:5432  (PostgreSQL 16, NO expuesto al exterior)
```

---

## Soporte

Para asistencia técnica, contacte al equipo de desarrollo.

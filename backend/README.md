# AYNI – Backend (FastAPI + SQL Server)

API REST de la plataforma AYNI para la gestión de ollas comunes.

## Requisitos

- [uv](https://docs.astral.sh/uv/) y Python 3.12+
- SQL Server (instancia Express local `localhost\SQLEXPRESS` o Docker en el puerto 1433) y SQL Server Management Studio (SSMS)
- `ODBC Driver 18 for SQL Server` (o 17; se detecta automáticamente)

## Puesta en marcha

1. Ejecute el script `../database/AyniOllasDB.SQL` en su SQL Server (crea la BD, tablas, SPs y datos semilla).
2. Copie `.env.example` a `.env` y complete `DB_SERVER`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` (o `DB_TRUSTED_CONNECTION=true` para autenticación de Windows), `JWT_SECRET` y `API_NINJAS_KEY`. Toda la configuración se lee en `app/core/config.py` (`pydantic-settings`).
3. Instale dependencias y levante la API (sin `--reload`):

```powershell
uv sync
```

```powershell
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Documentación interactiva: http://127.0.0.1:8000/docs · Estado: http://127.0.0.1:8000/api/health · BD: http://127.0.0.1:8000/health/db (`{"status": "ok"}` o `503`)

Al arrancar, la API reemplaza los `password_hash = 'PENDING_HASH'` por hashes bcrypt:

| Usuario | Contraseña | Rol |
|---|---|---|
| admin@ayni.org | Admin1234! | ADMIN |
| dirigenta@ayni.org | Dirigenta1234! | DIRIGENTA |
| maria.condori@ayni.org | Dirigenta1234! | DIRIGENTA |

## Endpoints por Historia de Usuario

| HU | Endpoint(s) |
|---|---|
| HU-01 | `GET /api/public/kpis` |
| HU-02 | `GET /api/public/ubigeos`, `GET /api/public/ollas` |
| HU-03 | `GET /api/public/ollas`, `GET /api/public/ollas/{id_olla}` |
| HU-04 | `POST /api/public/ollas` (sin cuenta) · `POST /api/auth/registro-olla` (con cuenta) |
| HU-05 | Validaciones y errores en español en toda la API (`{"detail": "..."}`) |
| HU-06 | `POST /api/auth/registro-olla` · alias `POST /api/auth/activar` |
| HU-07 | `POST /api/auth/login`, `GET /api/auth/me` (bloqueo 15 min tras 5 intentos) |
| HU-08 | `GET /api/olla/mi-olla`, `PUT /api/olla/estado-diario` |
| HU-09 | `GET /api/donantes`, `POST /api/donantes` |
| HU-10 | `GET /api/donaciones`, `POST /api/donaciones` |
| HU-11 | `GET /api/insumos`, `GET /api/inventario/stock`, `GET /api/inventario/lotes`, `POST /api/inventario/entrada`, `POST /api/inventario/salida`, `POST /api/inventario/descartar` |
| HU-12 | `GET /api/recetas?raciones=`, `POST /api/recetas/despachar`, `GET /api/recetas/externas?q=` |
| HU-13 | Toda respuesta exitosa de `POST/PUT/PATCH` incluye `mensaje` |
| HU-14 | `GET /api/movimientos`, `GET /api/reportes/resumen`, `GET /api/reportes/exportar-csv`, `/api/admin/*` |

Las rutas con datos de una olla usan la olla de la dirigenta autenticada. Un `ADMIN` puede consultarlas
indicando `?id_olla=N`.

## Entorno local vs. despliegue

Este repositorio es la versión **local** del proyecto (SQL Server + SSMS). La versión desplegada en la nube vive en
repositorios separados: `FlorDazu/Backend` (PostgreSQL en Supabase, Docker en Render) y `FlorDazu/Frontend` (Render).

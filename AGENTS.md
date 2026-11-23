# AGENTS.md

## Repo layout

- Top-level dirs: `backend/` (FastAPI + PostgreSQL/Supabase API via `psycopg` + `psycopg_pool`), `sql/001_ayni_postgres.sql` (PostgreSQL reference schema: 11 tables, seed data, 6 PL/pgSQL functions), `frontend/` (**Angular 22** standalone components + signals + CSS global; `ng serve` runs on port **4200** because backend CORS only allows `http://localhost:4200` — no proxy needed) and `.github/workflows/ci.yml` (pytest + ng build). Tests live in `backend/tests/`; no lint config.
- Backend layout under `backend/app/`: `apis/` (the 8 routers, formerly `routers/`), `core/` (`config.py`, `database.py`, `security.py`), `schemas/` (`__init__.py` re-exports `from .schemas import *`, so `app.schemas` imports are unchanged), plus empty `services/` and `repositories/` packages prepared for future extraction.
- The frontend mirrors the 8 routers with typed services in `src/app/core/services/*` and DTOs in `src/app/core/models.ts` (field names must match `backend/app/schemas/schemas.py` and `backend/app/apis/*`). Its typecheck/build is `npm run build` (`ng build`). Login (`AuthService.login`) first sends **form-urlencoded** `username`/`password` as specified, then auto-retries as **JSON** on 422 because the current backend validates `LoginRequest` as a JSON body (form data → 422). Layout: `core/` (auth/interceptor/guards/toasts) + `features/` (publico, auth, panel, admin).
- User-facing text (error messages, `mensaje` strings, comments, docs) is **Spanish**. Keep new strings in Spanish.
- Read `backend/README.md` before adding endpoints: it maps endpoints to user stories HU-01..HU-14 and lists seed users/passwords.

## Commands (run from `backend/`)

```powershell
uv sync                                                   # install deps (uv; Python 3.12 pinned in .python-version)
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000  # start API — README says run WITHOUT --reload
uv run pytest                                             # run backend/tests (DB-independent: fakes the connection)
```

## Commands (run from `frontend/`)

```powershell
npm install     # first time only
npm start       # ng serve → http://localhost:4200 (port fixed: backend CORS allowlist)
npm run build   # typecheck + production build (ng build)
```

- Prereqs: a Supabase project with `sql/001_ayni_postgres.sql` already applied (SQL Editor), and `backend/.env` copied from `.env.example` (`DATABASE_URL`, `CORS_ORIGINS`, `JWT_*`, `API_NINJAS_KEY`). No ODBC driver needed.
- Tests: `uv run pytest` in `backend/` only (no frontend tests, no lint). `backend/tests/conftest.py` monkeypatches `app.core.database.obtener_conexion`, so tests never touch PostgreSQL. Also verify by starting the API and checking `/docs`, `/api/health` and `/health/db`.
- **All configuration lives in `backend/app/core/config.py`** (`settings`, a `pydantic_settings.BaseSettings` with `SettingsConfigDict(env_file=backend/.env, env_file_encoding="utf-8", extra="ignore")`; every field has a safe default so tests load without `.env`; `cors_origins` is `Annotated[list[str], NoDecode]` split by commas in a `field_validator`): `DATABASE_URL` / `DB_*` / `DB_SSLMODE`, pool (`DB_POOL_MIN`, `DB_POOL_MAX`, `DB_TIMEOUT`), optional `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`, `JWT_*`, `CORS_ORIGINS`, `API_NINJAS_KEY`. Never call `os.getenv` elsewhere: add the field to `Settings` and import `settings`. `settings.advertencias()` is logged at startup (missing `DATABASE_URL`, example `JWT_SECRET`…).
- `pyproject.toml` sets `[tool.uv] package = false`: not an installable package. Run from `backend/` so `app.main:app` imports resolve. `.env` is loaded from `backend/.env` explicitly by `app/core/config.py` (path-independent).

## Database workflow (critical) — PostgreSQL en Supabase

- **Schema reference: `sql/001_ayni_postgres.sql`.** It is applied manually (Supabase SQL Editor or `psql`); the app **never** runs it on startup. There is no migration tool (no Alembic): a schema change means editing this script and re-applying it. Everything lives in schema `dbo` (kept so the router SQL `dbo.tabla` works unchanged).
- Tables (11): `ubigeos` → `ollas` (FK ubigeo) → `usuarios` (FK olla, `rol` ADMIN/DIRIGENTA, `intentos_fallidos`, `bloqueado_hasta`), `insumos`, `donantes` (FK olla) → `donaciones` (FK olla, donante) → `lotes_inventario` (FK olla, insumo, donación; PEPS index) → `movimientos_inventario` (kardex `#E-/#S-/#D-`, FK olla, insumo, lote, usuario), `recetas` → `receta_ingredientes` (FK receta CASCADE, insumo) → `despachos_receta` (FK olla, receta, usuario). Booleans are real `BOOLEAN`, timestamps `TIMESTAMPTZ`.
- Business logic lives in PL/pgSQL functions: `sp_registrar_olla`, `sp_crear_cuenta_dirigenta`, `sp_registrar_entrada_inventario`, `sp_registrar_salida_peps` (PEPS/FIFO, `FOR UPDATE`), `sp_descartar_lote`, `sp_despachar_receta_atomica`. Routers still write `EXEC dbo.sp_RegistrarSalidaPEPS @a = ?, ...`; `database.py::_adaptar_sql_y_params` rewrites it to `SELECT * FROM dbo.sp_registrar_salida_peps(%s, ...)` (CamelCase → snake_case, positional args **in declaration order**, literal `0/1` → `FALSE/TRUE`). It also maps `OUTPUT inserted.x` → `RETURNING x`, `ISNULL` → `COALESCE`, `GETDATE()/SYSDATETIME()` → `CURRENT_TIMESTAMP`, `?` → `%s`. Write **new** SQL in native PostgreSQL (`CURRENT_DATE`, `fecha - CURRENT_DATE`, `make_interval`, `LIMIT`, `ILIKE`); never use a literal `%` or `?` inside SQL text.
- Functions signal business errors with `RAISE EXCEPTION '<mensaje en español> (50xxx)'`. `app/core/database.py::traducir_error_sql` extracts the code: **50001/50010 → 409**, other `5xxxx → 400`, `psycopg.OperationalError`/SQLSTATE `08xxx` → 503, `23505` → 409, `23503/23502/23514` → 400, passing the message as `detail`. New business errors must follow this pattern.
- Seed users are inserted with `password_hash = 'PENDING_HASH'`; on startup the lifespan in `app/main.py` replaces them with bcrypt hashes, and on shutdown it calls `close_pool()`. The API **boots even if the DB is down** (logs a warning) — failures show up per-request as 503, not at startup.

### Conexión (Supabase Session pooler)

- `DATABASE_URL` (preferred; `DB_SERVER/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD` are only a local fallback) must be the **Session pooler** string: `postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require`. Port 5432 (session mode) keeps server-side state per connection, which `psycopg` needs; the Transaction pooler (6543) is not used. URL-encode special characters in the password (`@`→`%40`, `#`→`%23`, `/`→`%2F`, `%`→`%25`…).
- `app/core/database.py` keeps one `psycopg_pool.ConnectionPool` (sizes/timeout from `settings`, default min 1, max 10, timeout 5 s, `autocommit=True`, `dict_row`). `get_db` borrows a connection and returns it to the pool; `transaccion(conn)` wraps statements in `conn.transaction()` (all or nothing).
- `GET /health/db`: checks that `DATABASE_URL` is set, runs `SELECT 1` and answers `{"status": "ok"}`; otherwise **503** with a short Spanish message (never echoes the DSN). `GET /api/health` is the older, always-200 variant used by the frontend.
- The app connects as the **`postgres` user (table owner)**, so Row Level Security does not block it even if RLS is enabled on the tables. Isolation by `id_olla` is enforced by the API (`get_id_olla_contexto`), not by the database. If the tables were ever accessed with the Supabase `anon`/`authenticated` roles (e.g. from the frontend via supabase-js), RLS **must** be enabled and explicit policies defined per table — today none exist.
- CORS: `CORS_ORIGINS` (comma-separated) is read from `.env`; `http://localhost:4200` is always appended in `app/main.py`.

### Recetario externo (API Ninjas, HU-12)

- `GET /api/recetas/externas?q=...`: the Spanish query is translated to English with `deep_translator.GoogleTranslator(source="es", target="en")` (local dictionary fallback), sent to API Ninjas `/v3/recipe`, and the results are translated back `en → es`: `title`, `servings` (`"1 Servings"` → `"1 porción"`, deterministic regex before Google), `ingredients` (`list[str]`, bullets) and `pasos`/`instructions` (`list[str]`, numbered steps). Lists are translated in one call joined by `
`, falling back to item-by-item if the line count changes.
- Successful responses are cached in memory per query (`strip().lower()`, accents removed; max 100). Any translation exception is logged (`logger.warning`) and the recipe is returned in English. Without `API_NINJAS_KEY` or on network failure, local Spanish recipes are returned with an `aviso`.

## Code conventions (deviations from defaults)

- All errors are `{"detail": "..."}` in Spanish. Validation errors are translated centrally in `app/main.py` (`manejar_validacion`): write validator messages as Spanish `ValueError` in `app/schemas/schemas.py` and the handler formats them — don't build error responses manually. Successful `POST/PUT/PATCH` responses must include a `"mensaje"` field (HU-13).
- DB access only through helpers in `app/core/database.py`: `consultar`, `consultar_uno`, `ejecutar`, `ejecutar_sp`, `get_db`, `transaccion`. **Never drive a raw cursor yourself.** Connections come from the pool in autocommit mode; the helpers adapt the SQL and always close their cursor. Use `transaccion()` when grouping multiple statements/SPs.
- Auth/authorization deps from `app/core/security.py`: `get_usuario_actual`, `requiere_admin`, `get_id_olla_contexto`. The last one always scopes DIRIGENTAs to their own olla (ignores the param); an ADMIN must pass `?id_olla=N` explicitly.
- `bcrypt==4.0.1` is pinned (passlib 1.7.4 breaks on bcrypt ≥ 4.1) — don't bump it casually.

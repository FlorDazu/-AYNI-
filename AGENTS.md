# AGENTS.md

## Repo layout

- Top-level dirs: `backend/` (FastAPI + SQL Server API via `pyodbc`), `database/AyniOllasDB.SQL` (complete SQL Server schema, stored procedures, seed data), `frontend/` (**Angular 22** standalone components + signals + CSS global; `ng serve` runs on port **4200** because backend CORS only allows `http://localhost:4200` — no proxy needed) and `.github/workflows/ci.yml` (pytest + ng build). Tests live in `backend/tests/`; no lint config.
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

- Prereqs: SQL Server up (local Express instance `localhost\SQLEXPRESS` or Docker on port 1433) with `database/AyniOllasDB.SQL` run in SSMS, `ODBC Driver 18 for SQL Server` (17 also auto-detected), and `backend/.env` copied from `.env.example` (`DB_*`, `CORS_ORIGINS`, `JWT_*`, `API_NINJAS_KEY`).
- Tests: `uv run pytest` in `backend/` only (no frontend tests, no lint). `backend/tests/conftest.py` monkeypatches `app.core.database.obtener_conexion`, so tests never touch SQL Server. Also verify by starting the API and checking `/docs`, `/api/health` and `/health/db`.
- **All configuration lives in `backend/app/core/config.py`** (`settings`, a `pydantic_settings.BaseSettings` with `SettingsConfigDict(env_file=backend/.env, env_file_encoding="utf-8", extra="ignore")`; every field has a safe default so tests load without `.env`; `cors_origins` is `Annotated[list[str], NoDecode]` split by commas in a `field_validator`): `DB_SERVER`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_DRIVER`, `DB_TRUSTED_CONNECTION` (Windows auth, ignores user/password), `DB_TIMEOUT`, `JWT_*`, `CORS_ORIGINS`, `API_NINJAS_KEY`. Never call `os.getenv` elsewhere: add the field to `Settings` and import `settings`. `settings.advertencias()` is logged at startup (empty `DB_PASSWORD`, example `JWT_SECRET`…).
- `pyproject.toml` sets `[tool.uv] package = false`: not an installable package. Run from `backend/` so `app.main:app` imports resolve. `.env` is loaded from `backend/.env` explicitly by `app/core/config.py` (path-independent).

## Database workflow (critical) — SQL Server

- **All schema lives in `database/AyniOllasDB.SQL`, and the script begins by DROPing the entire `AyniOllasDB` database.** Re-running it wipes all data. There is no migration tool (no Alembic): a schema change means editing this script and accepting a full reset (seed `PENDING_HASH` users come back too).
- Business logic lives in stored procedures: `sp_RegistrarOlla`, `sp_CrearCuentaDirigenta`, `sp_RegistrarEntradaInventario`, `sp_RegistrarSalidaPEPS` (PEPS/FIFO), `sp_DescartarLote`, `sp_DespacharRecetaAtomica`. Writes in routers go through `EXEC dbo.sp_...`; reads are inline T-SQL (`ISNULL`, `GETDATE()`, `DATEDIFF`, `TOP`).
- SPs signal business errors with `THROW 50xxx, '<mensaje en español>', 1`. `app/core/database.py::traducir_error_sql` maps **50001/50010 → 409**, other `5xxxx → 400`, connection failures → 503, duplicates (2627/2601) → 409, FK/CHECK/length (547/515/8152) → 400, and passes the THROW text through as `detail`. New business errors should follow this pattern.
- Seed users are inserted with `password_hash = 'PENDING_HASH'`; on startup the lifespan in `app/main.py` replaces them with bcrypt hashes. The API **boots even if the DB is down** (logs a warning) — failures show up per-request as 503, not at startup.
- `GET /health/db` checks the SQL Server config, runs `SELECT 1` and answers `{"status": "ok"}`, or **503** with a short Spanish message. `GET /api/health` is the always-200 variant used by the frontend.
- **Two deliverables:** this repo is the LOCAL version (SQL Server + SSMS). The cloud version lives in separate repos `FlorDazu/Backend` (PostgreSQL/Supabase, Docker on Render, GitHub Actions) and `FlorDazu/Frontend` (Render). Do not mix their code here.

### Recetario externo (API Ninjas, HU-12)

- `GET /api/recetas/externas?q=...`: the Spanish query is translated to English with `deep_translator.GoogleTranslator(source="es", target="en")` (local dictionary fallback), sent to API Ninjas `/v3/recipe`, and the results are translated back `en → es`: `title`, `servings` (`"1 Servings"` → `"1 porción"`, deterministic regex before Google), `ingredients` (`list[str]`, bullets) and `pasos`/`instructions` (`list[str]`, numbered steps). Lists are translated in one call joined by `
`, falling back to item-by-item if the line count changes.
- Successful responses are cached in memory per query (`strip().lower()`, accents removed; max 100). Any translation exception is logged (`logger.warning`) and the recipe is returned in English. Without `API_NINJAS_KEY` or on network failure, local Spanish recipes are returned with an `aviso`.

## Code conventions (deviations from defaults)

- All errors are `{"detail": "..."}` in Spanish. Validation errors are translated centrally in `app/main.py` (`manejar_validacion`): write validator messages as Spanish `ValueError` in `app/schemas/schemas.py` and the handler formats them — don't build error responses manually. Successful `POST/PUT/PATCH` responses must include a `"mensaje"` field (HU-13).
- DB access only through helpers in `app/core/database.py`: `consultar`, `consultar_uno`, `ejecutar`, `ejecutar_sp`, `get_db`, `transaccion`. **Never drive a raw cursor yourself.** Connections are autocommit without MARS; the helpers drain all result sets, otherwise the next statement fails with `Connection is busy with results for another command`. Use `transaccion()` when grouping multiple statements/SPs.
- Auth/authorization deps from `app/core/security.py`: `get_usuario_actual`, `requiere_admin`, `get_id_olla_contexto`. The last one always scopes DIRIGENTAs to their own olla (ignores the param); an ADMIN must pass `?id_olla=N` explicitly.
- `bcrypt==4.0.1` is pinned (passlib 1.7.4 breaks on bcrypt ≥ 4.1) — don't bump it casually.

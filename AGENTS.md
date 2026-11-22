# AGENTS.md

## Repo layout

- Top-level dirs: `backend/` (FastAPI + SQL Server API), `database/AyniOllasDB.SQL` (complete schema, stored procedures, seed data), `frontend/` (**Angular 22** standalone components + signals + CSS global; `ng serve` runs on port **4200** because backend CORS only allows `http://localhost:4200` — no proxy needed) and `.github/workflows/ci.yml` (pytest + ng build). Tests live in `backend/tests/`; no lint config.
- Backend layout under `backend/app/`: `apis/` (the 8 routers, formerly `routers/`), `core/` (`database.py`, `security.py`), `schemas/` (`__init__.py` re-exports `from .schemas import *`, so `app.schemas` imports are unchanged), plus empty `services/` and `repositories/` packages prepared for future extraction.
- The frontend mirrors the 8 routers with typed services in `src/app/core/services/*` and DTOs in `src/app/core/models.ts` (field names must match `backend/app/schemas/schemas.py` and `backend/app/apis/*`). Its typecheck/build is `npm run build` (`ng build`). Login (`AuthService.login`) first sends **form-urlencoded** `username`/`password` as specified, then auto-retries as **JSON** on 422 because the current backend validates `LoginRequest` as a JSON body (form data → 422). Layout: `core/` (auth/interceptor/guards/toasts) + `features/` (publico, auth, panel, admin).
- User-facing text (error messages, `mensaje` strings, comments, docs) is **Spanish**. Keep new strings in Spanish.
- Read `backend/README.md` before adding endpoints: it maps endpoints to user stories HU-01..HU-14 and lists seed users/passwords.

## Commands (run from `backend/`)

```powershell
uv sync                                                   # install deps (uv; Python 3.12 pinned in .python-version)
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000  # start API — README says run WITHOUT --reload
uv run pytest                                             # run backend/tests (DB-independent: fakes the connection)
```

- Prereqs: SQL Server up (Docker, port 1433), `ODBC Driver 18 for SQL Server` (17 also auto-detected), `backend/.env` copied from `.env.example` (`DB_*`, `API_NINJAS_KEY`).
- Tests: `uv run pytest` in `backend/` only (no frontend tests, no lint). `backend/tests/conftest.py` monkeypatches `app.core.database.obtener_conexion`, so tests never touch SQL Server. Also verify by starting the API and checking `/docs` and `/api/health`.
- `pyproject.toml` sets `[tool.uv] package = false`: not an installable package. Run from `backend/` so `app.main:app` imports resolve. `.env` is loaded from `backend/.env` explicitly (path-independent).

## Database workflow (critical)

- **All schema lives in `database/AyniOllasDB.SQL`, and the script begins by DROPing the entire `AyniOllasDB` database.** Re-running it wipes all data. There is no migration tool (no Alembic): a schema change means editing this script and accepting a full reset (seed `PENDING_HASH` users come back too).
- Business logic lives in stored procedures: `sp_RegistrarOlla`, `sp_CrearCuentaDirigenta`, `sp_RegistrarEntradaInventario`, `sp_RegistrarSalidaPEPS` (PEPS/FIFO), `sp_DescartarLote`, `sp_DespacharRecetaAtomica`. Writes in routers go through `EXEC dbo.sp_...`; reads are inline SQL.
- SPs signal business errors with `THROW 50xxx, '<mensaje en español>', 1`. `app/core/database.py::traducir_error_sql` maps **50001/50010 → 409**, other `5xxxx → 400`, connection failures → 503, and passes the THROW text through as `detail`. New business errors should follow this pattern.
- Seed users are inserted with `password_hash = 'PENDING_HASH'`; on startup the lifespan in `app/main.py` replaces them with bcrypt hashes. The API **boots even if the DB is down** (logs a warning) — failures show up per-request as 503, not at startup.

## Code conventions (deviations from defaults)

- All errors are `{"detail": "..."}` in Spanish. Validation errors are translated centrally in `app/main.py` (`manejar_validacion`): write validator messages as Spanish `ValueError` in `app/schemas/schemas.py` and the handler formats them — don't build error responses manually. Successful `POST/PUT/PATCH` responses must include a `"mensaje"` field (HU-13).
- DB access only through helpers in `app/core/database.py`: `consultar`, `consultar_uno`, `ejecutar`, `ejecutar_sp`, `get_db`, `transaccion`. **Never drive a raw cursor yourself.** Connections are autocommit without MARS; the helpers drain all result sets, otherwise the next statement fails with `Connection is busy with results for another command`. Use `transaccion()` when grouping multiple statements/SPs.
- Auth/authorization deps from `app/core/security.py`: `get_usuario_actual`, `requiere_admin`, `get_id_olla_contexto`. The last one always scopes DIRIGENTAs to their own olla (ignores the param); an ADMIN must pass `?id_olla=N` explicitly.
- `bcrypt==4.0.1` is pinned (passlib 1.7.4 breaks on bcrypt ≥ 4.1) — don't bump it casually.

# AYNI · Plataforma de Gestión de Ollas Comunes

**AYNI** es una plataforma web para la gestión operativa, el abastecimiento y la transparencia de las **Ollas Comunes** del Perú. Conecta a ciudadanos, dirigentas y administradores en torno a un directorio público de ollas, un inventario con rotación PEPS, el registro de donaciones, la planificación de recetas según raciones y reportes exportables, con indicadores de impacto en vivo y trazabilidad de cada movimiento.

El nombre hace referencia al *ayni* andino: la reciprocidad como motor de la comunidad.

---

## 1 · Stack Tecnológico

| Capa | Tecnología |
|---|---|
| **Frontend** | **Angular 22** (TypeScript, standalone components + signals, rutas con carga diferida) · CSS moderno responsivo con soporte de accesibilidad **WCAG 2.1 AA** (enfoque visible, objetivos táctiles de 48 px, salto al contenido, control de tamaño de letra `A− / A+`) · **Bootstrap 5.0.2** (CDN) como base de utilidades y grid |
| **Backend** | **Python 3.12 + FastAPI** · gestión de paquetes con [**uv**](https://docs.astral.sh/uv/) y archivo **`requirements.txt`** (compatible con `pip`) |
| **Base de datos** | **Microsoft SQL Server** (administrado con **SQL Server Management Studio**) vía **`pyodbc`** · modelo normalizado en **3FN** · lógica de negocio en **Procedimientos Almacenados** |
| **Seguridad y calidad** | Autenticación **JWT** (8 h) con control de acceso por roles · contraseñas hasheadas con **bcrypt / passlib** · pruebas con **pytest + httpx** (`TestClient`) · **GitHub Actions** (CI) |

---

## 2 · Arquitectura del Proyecto

```text
-AYNI-/
│
├── .github/workflows/ci.yml      ← CI: pytest (backend) + ng build (frontend)
│
├── backend/                      ← API REST (FastAPI + SQL Server)
│   ├── app/
│   │   ├── apis/                 ← [CAPA API] los 8 routers: admin, auth, donaciones,
│   │   │                             inventario, olla, public, recetas, reportes
│   │   ├── core/                 ← [NÚCLEO] config.py (variables de entorno, pydantic-settings)
│   │   │                             database.py (conexión pyodbc + helpers SQL)
│   │   │                             security.py (JWT, bcrypt, dependencias de rol)
│   │   ├── schemas/              ← [CAPA ESQUEMAS] modelos Pydantic de validación
│   │   │                             (app/schemas/__init__.py reexporta .schemas)
│   │   ├── services/             ← [CAPA SERVICIOS] preparada para lógica de negocio
│   │   ├── repositories/         ← [CAPA REPOSITORIOS] preparada para acceso a datos
│   │   └── main.py               ← app FastAPI: CORS, lifespan, manejo de errores
│   ├── tests/                    ← pruebas pytest (conftest.py + test_api.py)
│   ├── requirements.txt          ← dependencias exportadas con uv
│   ├── pyproject.toml / uv.lock
│   └── .env.example              ← plantilla de variables de entorno
│
├── frontend/                     ← SPA Angular (puerto 4200)
│   └── src/app/
│       ├── core/                 ← servicios tipados, models.ts, guards,
│       │                             interceptor JWT, toasts, tamaño de letra
│       ├── features/
│       │   ├── publico/          ← landing, ollas, olla-detalle, registro público,
│       │   │                         nosotros, contactanos, layouts
│       │   ├── auth/             ← login y registro de dirigenta
│       │   ├── panel/            ← mi-olla, inventario, donaciones, recetas, reportes
│       │   └── admin/            ← ollas-admin, usuarios-admin, auditoría
│       └── styles.css            ← sistema de diseño global (paleta AYNI)
│
├── database/
│   ├── AyniOllasDB.SQL           ← script completo de SQL Server: BD, 11 tablas, 6 SPs y datos semilla
│   ├── 002_regiones_y_recetas.sql ← incremental: 162 distritos del Perú y 6 recetas más
│   └── 003_insumos_adicionales.sql ← incremental: 12 insumos más (kg, L o unidades)
│
├── README.md                     ← este documento
├── AGENTS.md                     ← guía para agentes de código
└── .gitignore                    ← ignora .env, opencode.json, .venv, node_modules, dist, cachés
```

### Arquitectura en capas de `backend/app/`

```text
        HTTP ──►  apis/        (endpoints y prefijos de ruta)
                     │
                     ▼
                schemas/       (validación Pydantic de entrada/salida)
                     │
                     ▼
                services/      (lógica de negocio — preparada)
                     │
                     ▼
                repositories/  (acceso a datos — preparado)
                     │
                     ▼
                core/          (config.py: settings · database.py: pyodbc · security.py: JWT/roles)
                     │
                     ▼
                SQL Server     (Procedimientos Almacenados + SQL en línea)
```

> Hoy la lógica de negocio vive en los **Procedimientos Almacenados** (`sp_RegistrarOlla`, `sp_RegistrarSalidaPEPS`, `sp_DespacharRecetaAtomica`, …); las capas `services/` y `repositories/` están creadas para futuras extracciones **sin mover todavía ninguna función probada**.

---

## 3 · Roles y Módulos Funcionales

### Ciudadano / Público (sin sesión)
- **Indicadores en vivo** de la red (ollas activas, beneficiarios hoy, donaciones, distritos) — `HU-01`.
- **Directorio de ollas** con búsqueda geográfica en cascada departamento → provincia → distrito y ficha pública de cada olla (`HU-02`, `HU-03`).
- **Solicitud de registro de una nueva olla** desde el portal, con o sin cuenta (`HU-04`).
- Páginas institucionales **Nosotros** y **Contáctanos** (formulario validado).

### Dirigenta (`DIRIGENTA`)
- **Registro en un paso**: cuenta + olla común con código único (`HU-06`) e inicio de sesión con bloqueo temporal (`HU-07`).
- **Gestión de su olla**: perfil, estado diario (atiende hoy, recibe frescos, necesidades urgentes) visible al instante en el portal (`HU-08`).
- **Unidades de medida**: cada insumo se guarda en su unidad base (**kg**, **L** o **unidades**); los formularios permiten registrar en gramos, sacos, ml, botellas, galoneras, docenas o cajas y convierten automáticamente.
- **Inventario por lotes/vencimientos** con semáforo (vigente / por vencer / vencido), entradas, salidas **PEPS (FIFO)** y descartes (`HU-11`).
- **Donantes y donaciones** monetarias y en especie, con trazabilidad (`HU-09`, `HU-10`).
- **Receta del día** (una por día, con botón «Otra receta») con **cálculo proporcional** según raciones, despacho atómico (todo o nada por PEPS) y sugerencias de recetario externo (API Ninjas) **traducidas al español** (`HU-12`).
- **Reportes**: kardex de movimientos, reporte consolidado y **exportación CSV** (`HU-14`).

### Administrador (`ADMIN`)
- **Aprobación / rechazo de ollas**: activación y desactivación global de cualquier olla registrada.
- **Gestión de usuarios**: roles, activación/desactivación y desbloqueo de cuentas.
- **Auditoría por olla**: resumen de inventario, semáforo de lotes y kardex de una olla concreta mediante `?id_olla=N`.

---

## 4 · Seguridad y Buenas Prácticas

- **JWT con control de acceso por roles**: `ADMIN` y `DIRIGENTA` protegidos con `canActivate` en el frontend y dependencias de rol en el backend; la dirigenta siempre opera sobre su propia olla.
- **Contraseñas hasheadas** con `bcrypt` (`passlib`); los hashes se generan al arrancar la API para los usuarios semilla.
- **Bloqueo de cuenta**: 5 intentos fallidos → 15 minutos de bloqueo.
- **Variables de entorno seguras**: `.env` (y `opencode.json`, con la clave de TestSprite) están **ignorados en Git** desde el `.gitignore` de la raíz; solo se versiona `backend/.env.example` como plantilla. Nunca subir claves reales al repositorio.
- **CORS restringido** a los orígenes de `CORS_ORIGINS` (por defecto `http://localhost:4200` y `http://127.0.0.1:4200`).
- **Errores en español** con formato `{"detail": "..."}` y respuestas exitosas de `POST/PUT/PATCH` con campo `mensaje`.
- **Sin secretos de producción en el repositorio**: credenciales de prueba y claves de servicios son locales o están en `.env`.

---

## 5 · Guía de Instalación y Ejecución Local

### Prerrequisitos

- **SQL Server** (instancia Express local, p. ej. `localhost\SQLEXPRESS`, o Docker en el puerto 1433) y **SQL Server Management Studio (SSMS)**.
- **ODBC Driver 18 for SQL Server** (el 17 también se detecta automáticamente).
- [uv](https://docs.astral.sh/uv/) y Python 3.12+ · Node.js 22+.

### Paso 1 · Base de datos (SSMS)

Hay **un único script** de base de datos: `database/AyniOllasDB.SQL`.

1. Abra **SSMS** y conéctese a su instancia de SQL Server.
2. Abra el archivo `database/AyniOllasDB.SQL`.
3. Ejecútelo completo (tecla `F5` o *Execute*).

4. Ejecute también `database/002_regiones_y_recetas.sql`: agrega **162 distritos de las 25 regiones** (foco en **Junín/Huancayo** con sus 28 distritos y en los 43 distritos de **Lima**) y **6 recetas** más. Es incremental: no borra nada y puede ejecutarse varias veces.
5. Ejecute `database/003_insumos_adicionales.sql`: agrega 12 insumos (azúcar, sal, ajo, harina, avena, quinua, frejol, cebolla, zanahoria, pescado, huevos y leche fresca).

> ⚠️ **Advertencia:** el script `AyniOllasDB.SQL` comienza con `DROP DATABASE AyniOllasDB`: re-ejecutarlo **borra todos los datos** existentes. Crea la BD, las 11 tablas normalizadas, los 6 procedimientos almacenados y los datos semilla (usuarios con `password_hash = 'PENDING_HASH'`, que la API reemplaza por hashes bcrypt al arrancar).

### Paso 2 · Backend (`http://127.0.0.1:8000`)

```powershell
cd backend

# 1. Variables de entorno
Copy-Item .env.example .env
#    Edite .env con sus valores locales (ver tabla siguiente)

# 2. Dependencias (una de dos)
uv sync                     # recomendado (usa uv.lock)
# pip install -r requirements.txt   # alternativa sin uv

# 3. Levantar la API (sin --reload)
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

#### Variables de entorno (`.env.example`)

Plantilla versionada en `backend/.env.example`. Cópiala a `backend/.env` (ignorado por Git) y ajusta los valores; **nunca subas un `.env` real al repositorio**.

Todas las variables se leen en un solo archivo: `backend/app/core/config.py` (`pydantic-settings`).

| Variable | Ejemplo | Descripción |
|---|---|---|
| `DB_SERVER` | `localhost\SQLEXPRESS` o `localhost,1433` | Instancia de SQL Server (Express local o Docker). |
| `DB_NAME` | `AyniOllasDB` | Base de datos creada por `database/AyniOllasDB.SQL`. |
| `DB_USER` / `DB_PASSWORD` | `sa` / *(su contraseña local)* | Usuario de SQL Server (autenticación SQL). |
| `DB_TRUSTED_CONNECTION` | `true` / `false` | `true` = autenticación de Windows (no usa `DB_USER` ni `DB_PASSWORD`). |
| `DB_DRIVER` | `ODBC Driver 18 for SQL Server` | Driver ODBC (el 17 también se detecta automáticamente). |
| `DB_TIMEOUT` | `5` | Segundos de espera al conectar (la API no se bloquea si SQL Server está apagado). |
| `CORS_ORIGINS` | `http://localhost:4200,http://127.0.0.1:4200` | Orígenes permitidos separados por comas (`localhost:4200` se incluye siempre). |
| `JWT_SECRET` | *(cadena secreta propia)* | Firma del token JWT — genérela única y privada. |
| `JWT_ALGORITHM` | `HS256` | Algoritmo de firma JWT. |
| `JWT_EXPIRE_MINUTES` | `480` | Vigencia de la sesión (8 horas). |
| `API_NINJAS_KEY` | *(clave de api.ninjas.com)* | Clave para el recetario externo (`/api/recetas/externas`, traducido al español). |
| `GOOGLE_TRANSLATE_API_KEY` | *(opcional)* | Google Cloud Translation API. Sin clave se usa la cadena gratuita Google → MyMemory. |

- Documentación interactiva: <http://127.0.0.1:8000/docs>
- Estado/salud: <http://127.0.0.1:8000/api/health> · Base de datos: <http://127.0.0.1:8000/health/db> (`{"status": "ok"}` o `503`)

### Paso 3 · Frontend (`http://localhost:4200`)

```powershell
cd frontend
npm install     # primera vez
npm start       # ng serve → http://localhost:4200
```

> Use el puerto **4200**: es el origen permitido por el CORS del backend. No se necesita proxy; la URL de la API está en `frontend/src/environments/environment.ts`.

---

## 6 · Pruebas Automatizadas e Integración Continua (CI)

### Pruebas locales

```powershell
cd backend
uv run pytest        # 10 pruebas: /docs, rutas OpenAPI, salud, 422, 401, 403, 404
```

Las pruebas **no necesitan base de datos**: `tests/conftest.py` sustituye la conexión por un doble falso y verifica documentación, validación en español y bloqueos de autenticación.

### Pipeline (`.github/workflows/ci.yml`)

Se ejecuta en cada *push* a `main` / `master` / `frontend` y en cada *pull request*, con dos trabajos en paralelo:

| Trabajo | Pasos |
|---|---|
| **Backend (pytest)** | checkout → instalar `uv` → driver ODBC (`unixodbc-dev`) → `uv sync` → verificar que la API carga (`from app.main import app`) → **`uv run pytest`** |
| **Frontend (ng build)** | checkout → Node.js 22 (caché npm) → `npm ci` → **`npm run build`** (typecheck + build de producción) |

---

## 7 · Usuarios de Prueba (Entorno Local)

Definidos en los datos semilla de `database/AyniOllasDB.SQL`:

| Correo | Rol | Olla vinculada |
|---|---|---|
| `admin@ayni.org` | **ADMIN** | — |
| `dirigenta@ayni.org` | **DIRIGENTA** | Olla 1 |
| `maria.condori@ayni.org` | **DIRIGENTA** | Olla 2 |

La contraseña inicial de estas cuentas se define **localmente** al arrancar la API (se reemplaza el `PENDING_HASH` semilla). **No hay claves de producción en el repositorio.**

---

## 8 · Entorno Local y Versión Desplegada

Este repositorio es la versión **local** del proyecto: **SQL Server + SSMS**, API en `127.0.0.1:8000` y Angular en `localhost:4200`.

La versión publicada en la nube vive en dos repositorios aparte, con la misma lógica de negocio adaptada a PostgreSQL:

| Repositorio | Contenido | Despliegue |
|---|---|---|
| `FlorDazu/Backend` | API FastAPI con **PostgreSQL en Supabase** (funciones PL/pgSQL), `Dockerfile` | Render (Docker) + GitHub Actions |
| `FlorDazu/Frontend` | SPA Angular con `server.mjs` y `render.yaml` | Render (Node) + GitHub Actions |

---

## Documentación relacionada

- `PRD.md` — documento de requisitos de producto: roles, requerimientos por módulo, inventario de endpoints, modelo de datos, reglas de negocio y criterios de aceptación E2E.
- `backend/README.md` — endpoints por historia de usuario (HU-01…HU-14) y puesta en marcha del API con SQL Server.
- `AGENTS.md` — convenciones del repositorio, comandos de desarrollo y flujo de base de datos.

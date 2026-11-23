# AYNI · Plataforma de Gestión de Ollas Comunes

**AYNI** es una plataforma web para la gestión operativa, el abastecimiento y la transparencia de las **Ollas Comunes** del Perú. Conecta a ciudadanos, dirigentas y administradores en torno a un directorio público de ollas, un inventario con rotación PEPS, el registro de donaciones, la planificación de recetas según raciones y reportes exportables, con indicadores de impacto en vivo y trazabilidad de cada movimiento.

El nombre hace referencia al *ayni* andino: la reciprocidad como motor de la comunidad.

---

## 1 · Stack Tecnológico

| Capa | Tecnología |
|---|---|
| **Frontend** | **Angular 22** (TypeScript, standalone components + signals, rutas con carga diferida) · CSS moderno responsivo con soporte de accesibilidad **WCAG 2.1 AA** (enfoque visible, objetivos táctiles de 48 px, salto al contenido, control de tamaño de letra `A− / A+`) · **Bootstrap 5.0.2** (CDN) como base de utilidades y grid |
| **Backend** | **Python 3.12 + FastAPI** · gestión de paquetes con [**uv**](https://docs.astral.sh/uv/) y archivo **`requirements.txt`** (compatible con `pip`) |
| **Base de datos** | **Microsoft SQL Server** · modelo normalizado en **3FN** · lógica de negocio en **Procedimientos Almacenados** |
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
│   │   ├── core/                 ← [NÚCLEO] database.py (conexión y helpers SQL)
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
│   └── AyniOllasDB.SQL           ← esquema completo: BD, tablas, SPs y datos semilla
│
├── README.md                     ← este documento
├── AGENTS.md                     ← guía para agentes de código
└── .gitignore                    ← ignora .env, .venv, node_modules, dist, cachés
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
                core/          (database.py: helpers SQL · security.py: JWT/roles)
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
- **Inventario por lotes/vencimientos** con semáforo (vigente / por vencer / vencido), entradas, salidas **PEPS (FIFO)** y descartes (`HU-11`).
- **Donantes y donaciones** monetarias y en especie, con trazabilidad (`HU-09`, `HU-10`).
- **Recetas con cálculo proporcional** según raciones, despacho atómico (todo o nada por PEPS) y sugerencias de recetario externo (`HU-12`).
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
- **Variables de entorno seguras**: `.env` está **ignorado en Git** (raíz y `backend/`), solo se versiona `.env.example` como plantilla. Nunca subir claves reales al repositorio.
- **CORS restringido** a `http://localhost:4200` (el origen exacto del frontend en desarrollo).
- **Errores en español** con formato `{"detail": "..."}` y respuestas exitosas de `POST/PUT/PATCH` con campo `mensaje`.
- **Sin secretos de producción en el repositorio**: credenciales de prueba y claves de servicios son locales o están en `.env`.

---

## 5 · Guía de Instalación y Ejecución Local

### Prerrequisitos

- SQL Server (Docker en el puerto 1433 o instancia local) y **ODBC Driver 18 for SQL Server** (el 17 también se detecta automáticamente).
- [uv](https://docs.astral.sh/uv/) y Python 3.12+ · Node.js 22+ · SQL Server Management Studio (SSMS).

### Paso 1 · Base de datos

Hay **un único script** de base de datos: `database/AyniOllasDB.SQL`. Se ejecuta **en este orden (paso único)**:

1. Abra **SSMS** y conéctese a su instancia de SQL Server.
2. Abra el archivo `database/AyniOllasDB.SQL`.
3. Ejecúselo completo (tecla `F5` o *Execute*).

> ⚠️ **Advertencia:** el script comienza con `DROP DATABASE AyniOllasDB` — re-ejecutarlo **borra todos los datos** existentes. Crea la BD, las 11 tablas normalizadas, los 6 procedimientos almacenados y los datos semilla (usuarios con `password_hash = 'PENDING_HASH'`, que la API reemplaza por hashes bcrypt al arrancar).

### Paso 2 · Backend (`http://localhost:8000`)

```powershell
cd backend

# 1. Variables de entorno
copy .env.example .env      # en PowerShell: Copy-Item .env.example .env
#    Edite .env: DB_SERVER, DB_PASSWORD y API_NINJAS_KEY (recetas externas)

# 2. Dependencias (una de dos)
uv sync                     # recomendado (usa uv.lock)
# pip install -r requirements.txt   # alternativa sin uv

# 3. Levantar la API 
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

- Documentación interactiva: <http://127.0.0.1:8000/docs>
- Estado/salud: <http://127.0.0.1:8000/api/health>

### Paso 3 · Frontend (`http://localhost:4200`)

```powershell
cd frontend
npm install     # primera vez
npm start       # ng serve → http://localhost:4200
```

> El puerto **4200** es fijo: el CORS del backend solo permite ese origen. No se necesita proxy.

---

## 6 · Pruebas Automatizadas e Integración Continua (CI)

### Pruebas locales

```powershell
cd backend
uv run pytest        # 10 pruebas: /docs, rutas OpenAPI, salud, 422, 401, 403, 404
```

Las pruebas **no necesitan SQL Server**: `tests/conftest.py` sustituye la conexión por un doble falso y verifica documentación, validación en español y bloqueos de autenticación.

### Pipeline (`.github/workflows/ci.yml`)

Se ejecuta en cada *push* a `main` / `master` / `frontend` y en cada *pull request*, con dos trabajos en paralelo:

| Trabajo | Pasos |
|---|---|
| **Backend (pytest)** | checkout → instalar `uv` → driver ODBC (`unixodbc-dev`) → `uv sync` → verificar que la API carga (`from app.main import app`) → **`uv run pytest`** |
| **Frontend (ng build)** | checkout → Node.js 22 (caché npm) → `npm ci` → **`npm run build`** (typecheck + build de producción) |

---

## 7 · Usuarios de Prueba (Entorno Local)

Definidos en los scripts semilla de `database/AyniOllasDB.SQL`:

| Correo | Rol | Olla vinculada |
|---|---|---|
| `admin@ayni.org` | **ADMIN** | — |
| `dirigenta@ayni.org` | **DIRIGENTA** | Olla 1 |
| `maria.condori@ayni.org` | **DIRIGENTA** | Olla 2 |

La contraseña inicial de estas cuentas se define **localmente** al arrancar la API (se reemplaza el `PENDING_HASH` semilla); consulte `backend/README.md` en su entorno local. **No hay claves de producción en el repositorio.**

---

## Documentación relacionada

- `backend/README.md` — endpoints por historia de usuario (HU-01…HU-14) y puesta en marcha del API.
- `AGENTS.md` — convenciones del repositorio, comandos de desarrollo y flujo de base de datos.

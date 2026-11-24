# PRD · AYNI — Plataforma de Gestión de Ollas Comunes

| Campo | Valor |
|---|---|
| **Producto** | AYNI · Ollas Comunes |
| **Documento** | Documento de Requisitos de Producto (PRD) |
| **Versión** | 1.1 (entorno local con SQL Server, configuración centralizada y recetario externo en español) |
| **Estado** | Aprobado para desarrollo |
| **Fecha** | Noviembre 2026 |
| **Fuentes de verdad** | `backend/` (API FastAPI) · `database/AyniOllasDB.SQL` (esquema y SPs) · `frontend/` (Angular) · `.github/workflows/ci.yml` (CI) |

> **Nota de seguridad:** este documento **no contiene contraseñas, tokens ni credenciales en texto plano**. Las cuentas de entorno local se listan únicamente con correo y rol (Anexo A); sus claves se definen solo en el equipo de desarrollo (`.env` ignorado en Git y semillas `PENDING_HASH` resueltas al arrancar la API).

---

## 1 · Visión general del sistema

### 1.1 Contexto y problema

Las **ollas comunes** del Perú son cocinas comunitarias que sostienen la alimentación de barrios populares. Su gestión suele ser manual (cuadernos, hojas de cálculo), lo que provoca:

- Falta de **transparencia** sobre el estado real de las ollas y su impacto.
- Pérdida de **control de abastecimiento**: insumos vencidos, faltantes no detectados a tiempo.
- **Trazabilidad incompleta** de quién donó, qué se recibió y qué se consumió.
- Dificultad para **planificar** cuánto cocinar según el número de raciones.

### 1.2 Descripción del producto

**AYNI** es una plataforma web que conecta a tres actores en torno a un directorio público de ollas comunes, un inventario con rotación **PEPS (FIFO)**, el registro de donaciones, la planificación de recetas según raciones y reportes exportables, con indicadores de impacto en vivo y trazabilidad de cada movimiento. El nombre hace referencia al *ayni* andino: la reciprocidad como motor de la comunidad.

### 1.3 Objetivos del sistema

| ID | Objetivo |
|---|---|
| **GO-01** | **Transparencia**: publicar indicadores en vivo y un directorio consultable de ollas activas sin necesidad de sesión. |
| **GO-02** | **Control de abastecimiento**: gestionar el inventario por lotes con vencimientos y rotación PEPS para reducir mermas. |
| **GO-03** | **Trazabilidad**: registrar cada movimiento de inventario con autor, fechas, saldos anterior/posterior y motivo. |
| **GO-04** | **Eficiencia operativa**: calcular recetas de forma proporcional a las raciones y despachar insumos de forma atómica. |
| **GO-05** | **Gobernanza**: diferenciar roles (público, dirigenta, administrador), auditar ollas y gestionar cuentas. |
| **GO-06** | **Inclusión**: interfaz en español, responsiva y accesible (WCAG 2.1 AA). |

### 1.4 Alcance

**Incluido:** portal público, autenticación por roles, gestión de olla, inventario PEPS, donantes/donaciones, recetas, reportes con exportación CSV, administración de ollas y usuarios, auditoría, API REST documentada (OpenAPI) y CI.

**Fuera de alcance (v1):** pagos en línea, aplicación móvil nativa, notificaciones push/SMS, multilingüe, firma digital de comprobantes.

### 1.5 Arquitectura resumida

```text
 Navegador (SPA Angular 22, puerto 4200)
        │  HTTP/JSON + JWT (Bearer)   ·  CORS restringido a localhost:4200
        ▼
 API FastAPI (Python 3.12, puerto 8000)
        │  capas: apis/ → schemas/ → services/ → repositories/ → core/
        │  (validación Pydantic · JWT/roles · helpers SQL)
        ▼
 Microsoft SQL Server (BD `AyniOllasDB`, 3FN) · administrado con SSMS
        │  driver `pyodbc` + ODBC Driver 18/17 for SQL Server
        └── Lógica de negocio en 6 Procedimientos Almacenados atómicos
```

- **Frontend:** Angular 22 (standalone + signals, rutas con carga diferida), CSS propio con base **Bootstrap 5.0.2** (CDN), accesibilidad WCAG 2.1 AA.
- **Backend:** FastAPI con `uv`; los endpoints viven en la capa `apis/` y la persistencia se ejecuta vía SPs y SQL en línea sobre `core/database.py` (`pyodbc`). Toda la configuración (`DB_SERVER`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_DRIVER`, `DB_TRUSTED_CONNECTION`, JWT, CORS, API Ninjas) se lee en `core/config.py` (`pydantic-settings`, desde `backend/.env`).
- **Entornos:** este repositorio es la versión **local** (SQL Server + SSMS). La versión desplegada en la nube vive en los repositorios `FlorDazu/Backend` (PostgreSQL en Supabase, Docker en Render) y `FlorDazu/Frontend` (Render).
- **Datos:** 11 tablas normalizadas, 6 SPs, función de correlativos e índices de rendimiento.

---

## 2 · Roles y permisos

### 2.1 Definición de roles

| Rol | Identidad | Sesión | Alcance de datos |
|---|---|---|---|
| **Público** (ciudadano) | Cualquier visitante del portal | No requiere | Solo lectura de datos públicos; puede registrar una olla sin cuenta. |
| **DIRIGENTA** | Usuario vinculado a **una** olla (`usuarios.id_olla`) | JWT (8 h) | **Siempre su propia olla**; el parámetro `id_olla` se ignora en su favor. |
| **ADMIN** | Usuario global sin olla (`id_olla = NULL`) | JWT (8 h) | **Todas** las ollas; en recursos con alcance debe indicar `?id_olla=N`. |

### 2.2 Matriz de permisos

| Capacidad | Público | DIRIGENTA | ADMIN |
|---|:---:|:---:|:---:|
| Consultar KPIs, directorio y fichas de ollas | ✓ | ✓ | ✓ |
| Registrar una nueva olla sin cuenta (`POST /api/public/ollas`) | ✓ | ✓ | ✓ |
| Crear cuenta de dirigenta + olla en un paso | ✓ | ✓ | ✓ |
| Iniciar sesión y consultar su perfil (`/api/auth/*`) | — | ✓ | ✓ |
| Ver/actualizar el estado diario de la olla | — | ✓ (la suya) | ✓ (`?id_olla=N`) |
| Inventario: entradas, salidas PEPS, descartes, lotes, stock | — | ✓ (la suya) | ✓ (`?id_olla=N`) |
| Donantes y donaciones | — | ✓ (la suya) | ✓ (`?id_olla=N`) |
| Recetas, despachos y recetario externo | — | ✓ (la suya) | ✓ (`?id_olla=N`) |
| Reportes: kardex, resumen y exportación CSV | — | ✓ (la suya) | ✓ (`?id_olla=N`) |
| Listado global de insumos y recetas externas | — | ✓ | ✓ |
| Auditar cualquier olla (`/api/admin/ollas`, auditoría) | — | — | ✓ |
| Activar / desactivar ollas | — | — | ✓ |
| Gestionar usuarios: rol, activación y desbloqueo | — | — | ✓ |

### 2.3 Reglas de acceso y códigos de autorización

| Situación | Código | Mensaje (ejemplo) |
|---|---|---|
| Sin token, token expirado o inválido | `401` | «Debe iniciar sesión para acceder a este recurso.» / «Su sesión ha expirado.» |
| Cuenta desactivada u olla desactivada | `403` | «Su cuenta está desactivada. Comuníquese con el administrador de AYNI.» |
| Acceso a recurso exclusivo de ADMIN | `403` | «Solo el administrador de AYNI puede realizar esta acción.» |
| DIRIGENTA sin olla asignada | `403` | «Su cuenta no tiene una olla común asignada.» |
| ADMIN en recurso con alcance sin `?id_olla=N` | `400` | «Como administrador debe indicar la olla a consultar con el parámetro id_olla.» |
| `id_olla` inexistente | `404` | «La olla común indicada no existe.» |
| Cuenta bloqueada por intentos fallidos | `423` | «Su cuenta está bloqueada temporalmente por intentos fallidos…» |

---

## 3 · Requerimientos funcionales por módulo

> **HU** = historia de usuario trazable en `backend/README.md`. **Evidencia** = endpoint(s) REST y vista(s) Angular.

### M1 · Portal público (sin sesión)

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-01** | Mostrar indicadores en vivo de la red: ollas activas, ollas que atienden hoy, beneficiarios (hoy y total), distritos cubiertos, donaciones y monto en soles. | HU-01 | `GET /api/public/kpis` · vista *landing* |
| **RF-02** | Listar ollas activas con **búsqueda geográfica en cascada** departamento → provincia → distrito y filtros combinados. | HU-02 | `GET /api/public/ubigeos`, `GET /api/public/ollas` · vista *ollas* |
| **RF-03** | Mostrar la **ficha pública** de una olla (código único, ubicación, beneficiarios, estado diario, necesidades urgentes). | HU-03 | `GET /api/public/ollas/{id_olla}` · vista *olla-detalle* |
| **RF-04** | Permitir **registrar una olla sin cuenta**, activada y verificada al instante, con código único `AYNI-####`. | HU-04 | `POST /api/public/ollas` → `201` · vista *registro-publico* |
| **RF-05** | Páginas institucionales **Nosotros** y **Contáctanos** con formulario validado por campo. | — | vistas *nosotros*, *contactanos* |

### M2 · Autenticación y cuentas

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-06** | **Registro en un paso**: crear cuenta de dirigenta + olla común con código único; alias de activación. | HU-06 | `POST /api/auth/registro-olla`, `POST /api/auth/activar` → `201` · vista *registro* |
| **RF-07** | **Inicio de sesión** con JWT (8 h) y **bloqueo temporal**: 5 intentos fallidos → 15 minutos; informa intentos restantes. | HU-07 | `POST /api/auth/login`, `GET /api/auth/me` · vista *login* |
| **RF-08** | Gestión de sesión en el frontend: interceptor JWT, guards por rol, aviso y re-login ante token vencido. | HU-07 | `core/` (interceptor, guards) · vista *login* |

### M3 · Panel de la olla («Mi Olla»)

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-09** | Consultar el perfil de **su** olla: datos de contacto, beneficiarios y estado diario. | HU-08 | `GET /api/olla/mi-olla` · vista *mi-olla* |
| **RF-10** | Actualizar el **estado diario** (atiende hoy, recibe frescos, necesidades urgentes) con reflejo inmediato en el portal público. | HU-08 | `PUT /api/olla/estado-diario` → `200` |

### M4 · Inventario PEPS

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-11** | Consultar el **catálogo de insumos** y el **stock** consolidado por insumo de la olla. | HU-11 | `GET /api/insumos`, `GET /api/inventario/stock` · vista *inventario* |
| **RF-12** | Listar **lotes** con semáforo de vencimiento: vigente / por vencer (≤ 7 días) / vencido, con saldo disponible. | HU-11 | `GET /api/inventario/lotes` |
| **RF-13** | Registrar una **entrada** de inventario: crea lote `LT-#####` y movimiento `E-#####` con saldos. | HU-11 | `POST /api/inventario/entrada` → `201` (SP `sp_RegistrarEntradaInventario`) |
| **RF-14** | Registrar una **salida** con rotación **PEPS/FIFO**: consume primero el lote más antiguo; saldo insuficiente → error sin efectos. | HU-11 | `POST /api/inventario/salida` → `200` (SP `sp_RegistrarSalidaPEPS`) |
| **RF-15** | **Descartar** un lote con motivo obligatorio (ej. vencido), marcándolo `DESCARTADO` y registrando movimiento `D-`. | HU-11 | `POST /api/inventario/descartar` → `200` (SP `sp_DescartarLote`) |

### M5 · Donantes y donaciones

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-16** | Gestionar **donantes** (persona natural, empresa, mercado, institución) con datos de contacto y marca de frecuencia. | HU-09 | `GET/POST /api/donantes` · vista *donaciones* |
| **RF-17** | Registrar **donaciones** monetarias (monto en soles, comprobante) y en especie (descripción), vinculadas al donante cuando existe. | HU-10 | `GET/POST /api/donaciones` → `201` |

### M6 · Recetas

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-18** | Listar recetas con **cálculo proporcional** de ingredientes según las raciones indicadas (`raciones_base` como referencia). | HU-12 | `GET /api/recetas?raciones=` · vista *recetas* |
| **RF-19** | **Despachar** una receta de forma **atómica** (todo o nada): si algún ingrediente alcanza por PEPS, se generan todas las salidas y el registro del despacho; si no, no cambia nada. | HU-12 | `POST /api/recetas/despachar` → `200` (SP `sp_DespacharRecetaAtomica`) |
| **RF-20** | Consultar **sugerencias de recetario externo** (API Ninjas) como apoyo a la planificación, **100 % en español**: la búsqueda se traduce `es → en` antes de consultar y la respuesta se traduce `en → es` (`title`, `servings` → «1 porción» / «N porciones», `ingredients` y `pasos`/`instructions` como listas, conservando viñetas y pasos numerados). Caché en memoria por búsqueda; si la traducción falla se registra en bitácora y se devuelve el texto en inglés; sin clave o sin red se muestran recetas locales con `aviso`. | HU-12 | `GET /api/recetas/externas?q=` · `deep-translator` (`GoogleTranslator`) |

### M7 · Reportes

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-21** | **Kardex** de movimientos de la olla (entrada/salida/descarte) con correlativo, saldos y motivo. | HU-14 | `GET /api/movimientos` · vista *reportes* |
| **RF-22** | **Reporte consolidado**: resumen de inventario, donaciones y actividad de la olla. | HU-14 | `GET /api/reportes/resumen` |
| **RF-23** | **Exportación CSV** del kardex para su uso fuera de la plataforma. | HU-14 | `GET /api/reportes/exportar-csv` |

### M8 · Administración

| ID | Requerimiento | HU | Evidencia |
|---|---|---|---|
| **RF-24** | **Aprobación / rechazo de ollas**: listar todas las ollas y activar o desactivar cualquier olla (efecto inmediato en portal y accesos). | HU-14 | `GET /api/admin/ollas`, `PATCH /api/admin/ollas/{id_olla}/estado` → `200` · vista *ollas-admin* |
| **RF-25** | **Gestión de usuarios**: listar cuentas, cambiar rol, activar/desactivar y **desbloquear** cuentas. | HU-14 | `GET /api/admin/usuarios`, `PATCH /api/admin/usuarios/{id_usuario}` → `200` · vista *usuarios-admin* |
| **RF-26** | **Auditoría por olla**: resumen de inventario, semáforo de lotes y kardex de una olla concreta mediante `?id_olla=N`. | HU-14 | mismos recursos de panel con alcance ADMIN · vista *auditoria* |

### M9 · Requerimientos transversales

| ID | Requerimiento | HU |
|---|---|---|
| **RF-27** | Todos los errores responden `{"detail": "…"}` **en español** (validaciones de Pydantic y `ValueError` traducidos centralmente). | HU-05 |
| **RF-28** | Toda respuesta exitosa de `POST`/`PUT`/`PATCH` incluye el campo **`mensaje`** en español. | HU-13 |
| **RF-29** | Accesibilidad **WCAG 2.1 AA**: enfoque visible, objetivos táctiles ≥ 48 px, salto al contenido, contraste y `aria-*`. | — |
| **RF-30** | Interfaz **responsiva** (móvil → escritorio) con paleta y sistema de diseño propios de AYNI. | — |
| **RF-31** | **Rendimiento**: rutas con carga diferida (lazy loading) y bundle inicial contenido (~315 kB). | — |

---

## 4 · Inventario de endpoints REST

**Base URL:** `http://127.0.0.1:8000` · **Documentación:** `/docs` (OpenAPI) · **Salud:** `GET /api/health` y `GET /health/db` · **Total de rutas: 34.**

### 4.1 Endpoints públicos (sin sesión) — 11

| Método | Ruta | Descripción | HU |
|---|---|---|---|
| `GET` | `/` | Raíz de la API (mensaje de bienvenida y versión). | — |
| `GET` | `/api/health` | Estado de la API y de la base de datos (siempre `200`, usado por el frontend). | — |
| `GET` | `/health/db` | Comprueba la configuración de SQL Server y ejecuta `SELECT 1`: `200 {"status": "ok"}`; si falta la configuración o falla la conexión (`pyodbc.Error`) → `503` con mensaje corto en español (sin exponer credenciales). | — |
| `GET` | `/api/public/kpis` | Indicadores en vivo de la red. | HU-01 |
| `GET` | `/api/public/ubigeos` | Lista de departamentos → provincias → distritos (búsqueda en cascada). | HU-02 |
| `GET` | `/api/public/ollas` | Directorio de ollas activas con filtros geográficos. | HU-02/03 |
| `GET` | `/api/public/ollas/{id_olla}` | Ficha pública de una olla. | HU-03 |
| `POST` | `/api/public/ollas` | Registro de olla **sin cuenta** → `201`. | HU-04 |
| `POST` | `/api/auth/login` | Autenticación → `200` (token JWT). | HU-07 |
| `POST` | `/api/auth/registro-olla` | Registro en un paso (cuenta + olla) → `201`. | HU-06 |
| `POST` | `/api/auth/activar` | Alias de activación de la cuenta creada → `201`. | HU-06 |

### 4.2 Endpoints protegidos (requieren JWT) — 19

| Método | Ruta | Rol mínimo | Alcance | HU |
|---|---|---|---|---|
| `GET` | `/api/auth/me` | Cualquiera | — | HU-07 |
| `GET` | `/api/olla/mi-olla` | DIRIGENTA/ADMIN | `id_olla` | HU-08 |
| `PUT` | `/api/olla/estado-diario` | DIRIGENTA/ADMIN | `id_olla` | HU-08 |
| `GET` | `/api/insumos` | Cualquiera | catálogo global | HU-11 |
| `GET` | `/api/inventario/stock` | DIRIGENTA/ADMIN | `id_olla` | HU-11 |
| `GET` | `/api/inventario/lotes` | DIRIGENTA/ADMIN | `id_olla` | HU-11 |
| `POST` | `/api/inventario/entrada` | DIRIGENTA/ADMIN | `id_olla` → `201` | HU-11 |
| `POST` | `/api/inventario/salida` | DIRIGENTA/ADMIN | `id_olla` → `200` | HU-11 |
| `POST` | `/api/inventario/descartar` | DIRIGENTA/ADMIN | `id_olla` → `200` | HU-11 |
| `GET` | `/api/donantes` | DIRIGENTA/ADMIN | `id_olla` | HU-09 |
| `POST` | `/api/donantes` | DIRIGENTA/ADMIN | `id_olla` → `201` | HU-09 |
| `GET` | `/api/donaciones` | DIRIGENTA/ADMIN | `id_olla` | HU-10 |
| `POST` | `/api/donaciones` | DIRIGENTA/ADMIN | `id_olla` → `201` | HU-10 |
| `GET` | `/api/recetas` | DIRIGENTA/ADMIN | `id_olla` | HU-12 |
| `POST` | `/api/recetas/despachar` | DIRIGENTA/ADMIN | `id_olla` → `200` | HU-12 |
| `GET` | `/api/recetas/externas` | Cualquiera | — | HU-12 |
| `GET` | `/api/movimientos` | DIRIGENTA/ADMIN | `id_olla` | HU-14 |
| `GET` | `/api/reportes/resumen` | DIRIGENTA/ADMIN | `id_olla` | HU-14 |
| `GET` | `/api/reportes/exportar-csv` | DIRIGENTA/ADMIN | `id_olla` (CSV) | HU-14 |

> **Columna «Alcance»:** para la DIRIGENTA el servidor siempre usa **su propia olla** (el parámetro se ignora); para un ADMIN es obligatorio pasar `?id_olla=N` en los recursos marcados con `id_olla` (si falta → `400`; si no existe → `404`).

### 4.3 Endpoints exclusivos de ADMIN — 4

| Método | Ruta | Descripción | HU |
|---|---|---|---|
| `GET` | `/api/admin/ollas` | Listado global de todas las ollas. | HU-14 |
| `PATCH` | `/api/admin/ollas/{id_olla}/estado` | Activar / desactivar una olla → `200`. | HU-14 |
| `GET` | `/api/admin/usuarios` | Listado de usuarios con rol, bloqueo y estado. | HU-14 |
| `PATCH` | `/api/admin/usuarios/{id_usuario}` | Cambiar rol, activar/desactivar, desbloquear → `200`. | HU-14 |

### 4.4 Convenciones de la API

| Aspecto | Convención |
|---|---|
| Formato | JSON en español · `Content-Type: application/json` (CSV en exportación). |
| Éxito | `200` (lectura/actualización) · `201` (creación) · campo **`mensaje`** obligatorio en `POST/PUT/PATCH` (HU-13). |
| Validación | `422` con mensajes en español (validadores centralizados). |
| Negocio (SQL) | `THROW 50001/50010` → **`409`** (duplicados) · resto de `50xxx` → **`400`** · fallo de conexión → **`503`** · duplicado `2627/2601` → `409` · FK/obligatorio `547/515/8152` → `400`. |
| Autenticación | `401` (sin/expirado/inválido) · `403` (permisos) · `423` (bloqueo 5 intentos/15 min). |
| CORS | Orígenes de `CORS_ORIGINS` en `.env`; `http://localhost:4200` se incluye siempre. |

---

## 5 · Modelo de datos principal

Base de datos **`AyniOllasDB`** (SQL Server), normalizada en **3FN**, creada por `database/AyniOllasDB.SQL`.

### 5.1 Tablas (11)

| # | Tabla | PK | Relaciones (FK) | Propósito |
|---|---|---|---|---|
| 1 | `ubigeos` | `id_ubigeo` | — | Catálogo departamento / provincia / distrito (único por combinación). |
| 2 | `ollas` | `id_olla` | → `ubigeos` | Olla común: `codigo_unico` (`AYNI-####`), datos de contacto, beneficiarios, estado diario, `activada`/`verificada`. |
| 3 | `usuarios` | `id_usuario` | → `ollas` (opcional) | Cuentas `ADMIN`/`DIRIGENTA`; `password_hash` (bcrypt), `intentos_fallidos`, `bloqueado_hasta`, `activo`. |
| 4 | `insumos` | `id_insumo` | — | Catálogo de insumos con `unidad_base` (`kg`/`L`/`unidades`), `stock_minimo` y `requiere_vencimiento`. |
| 5 | `donantes` | `id_donante` | → `ollas` | Donantes por olla: tipo (`PERSONA_NATURAL`, `EMPRESA`, `MERCADO`, `INSTITUCION`), documento, contacto. |
| 6 | `donaciones` | `id_donacion` | → `ollas`, `donantes` | Donaciones `ESPECIE`/`MONETARIA` con monto en soles, comprobante y descripción. |
| 7 | `lotes_inventario` | `id_lote` | → `ollas`, `insumos`, `donaciones` | Lotes `LT-#####` con cantidad inicial/disponible, vencimiento y estado (`ACTIVO`/`AGOTADO`/`DESCARTADO`). |
| 8 | `movimientos_inventario` | `id_movimiento` | → `ollas`, `insumos`, `lotes`, `usuarios` | Kardex: correlativo `E-`/`S-`/`D-`, cantidad, **saldo anterior/posterior**, motivo, autor y fecha. |
| 9 | `recetas` | `id_receta` | — | Recetas con `raciones_base` y flag `activa`. |
| 10 | `receta_ingredientes` | `id_receta_ingrediente` | → `recetas`, `insumos` | Ingredientes con `cantidad_base` (único por receta+insumo). |
| 11 | `despachos_receta` | `id_despacho` | → `ollas`, `recetas`, `usuarios` | Registro de recetas servidas: `raciones_servidas`, fecha y usuario. |

### 5.2 Relaciones principales

```text
ubigeos ──< ollas ──<┬── usuarios            (id_olla NULL = ADMIN global)
                     ├── donantes ──< donaciones
                     ├── lotes_inventario >── insumos
                     │        └── (opcional) donaciones
                     ├── movimientos_inventario >── insumos · lotes · usuarios
                     └── despachos_receta >── recetas ──< receta_ingredientes >── insumos
```

### 5.3 Procedimientos almacenados (6) y función

| SP / Función | Responsabilidad | HU |
|---|---|---|
| `sp_RegistrarOlla` | Alta de olla con código único `AYNI-####`, validación de ubigeo y de duplicado (nombre + distrito). | HU-04 |
| `sp_CrearCuentaDirigenta` | Crea usuario DIRIGENTA + olla en una sola transacción; rechaza usuario duplicado. | HU-06 |
| `sp_RegistrarEntradaInventario` | Crea lote `LT-#####`, suma stock y registra movimiento `E-#####` con saldos. | HU-11 |
| `sp_RegistrarSalidaPEPS` | Salida **PEPS/FIFO**: consume lotes por `fecha_ingreso` ascendente; valida saldo suficiente. | HU-11 |
| `sp_DescartarLote` | Marca lote `DESCARTADO` con motivo obligatorio y registra movimiento `D-#####`. | HU-11 |
| `sp_DespacharRecetaAtomica` | **Despacho todo-o-nada**: calcula requerimiento proporcional, ejecuta todas las salidas PEPS y registra el despacho en una transacción. | HU-12 |
| `fn_Correlativo(prefijo, id, dígitos)` | Genera códigos correlativos con relleno de ceros (`AYNI-0001`, `LT-00001`, `E-00001`…). | — |

### 5.4 Índices de rendimiento

| Índice | Columnas | Para qué |
|---|---|---|
| `IX_ollas_ubigeo_activa` | `ollas(id_ubigeo, activada)` | Directorio público con filtros geográficos. |
| `IX_lotes_peps` | `lotes_inventario(id_olla, id_insumo, estado, fecha_vencimiento, fecha_ingreso)` | Consultas PEPS y semáforo de vencimientos. |
| `IX_movimientos_olla_fecha` | `movimientos_inventario(id_olla, fecha_movimiento DESC)` | Kardex y reportes ordenados por fecha. |

---

## 6 · Reglas de negocio

| ID | Regla | Implementación / error asociado |
|---|---|---|
| **RN-01** | El registro de olla **sin cuenta** nace **activada y verificada** (no hay flujo de solicitudes previas); el ADMIN puede desactivarla o reactivarla después. | `sp_RegistrarOlla` · `PATCH /api/admin/ollas/{id}/estado` |
| **RN-02** | No pueden existir dos ollas con el mismo **nombre en el mismo distrito**. | `THROW 50010` → `409` |
| **RN-03** | El **username** (correo) de usuario es único. | `THROW 50001` → `409` |
| **RN-04** | **Bloqueo de cuenta**: 5 intentos fallidos de login → 15 minutos de bloqueo (`423`); se informan los intentos restantes en errores `401`. | `sp`-free lógica en `routers/auth.py` + columnas `intentos_fallidos`/`bloqueado_hasta` |
| **RN-05** | Contraseñas guardadas solo como **hash bcrypt**; la semilla `PENDING_HASH` se reemplaza al arrancar la API (lifespan). | `security.py` · `main.py` |
| **RN-06** | Sesión con **JWT** (HS256, expiración 480 minutos); token expirado/inválido → `401`. | `core/security.py` (capa en `main`) |
| **RN-07** | **Alcance por olla**: toda DIRIGENTA opera **exclusivamente** sobre su propia olla (el parámetro `id_olla` se ignora); el ADMIN debe indicar `?id_olla=N` (falta → `400`, inexistente → `404`). | `get_id_olla_contexto` |
| **RN-08** | **Inventario PEPS (FIFO)**: cada salida consume primero el lote con `fecha_ingreso` más antiguo; si el saldo total no alcanza, la operación falla **sin producir ningún efecto**. | `sp_RegistrarSalidaPEPS` · `THROW 50005` → `400` |
| **RN-09** | Toda entrada/salida/descarte genera un **movimiento de kardex** con correlativo único, saldos anterior/posterior, motivo, autor y fecha. | `movimientos_inventario` |
| **RN-10** | El **descarte** de un lote exige **motivo obligatorio** y solo aplica a lotes propios con saldo activo. | `THROW 50006/50007` → `400` |
| **RN-11** | **Despacho de receta atómico**: si algún ingrediente no alcanza por PEPS, **no se despacha nada** (todo se revierte); si alcanza, se ejecutan todas las salidas y se registra el despacho. Cantidades y recetas deben ser válidas. | `sp_DespacharRecetaAtomica` · `THROW 50008/50009` → `400` |
| **RN-12** | Las cantidades de entrada/salida deben ser **mayores a cero**. | `THROW 50003/50004` → `400` |
| **RN-13** | **Semáforo de vencimientos**: vigente / por vencer (≤ 7 días) / vencido; los vencidos se retiran mediante descarte con motivo (no automático). | `GET /api/inventario/lotes` |
| **RN-14** | Los errores de negocio usan `THROW 50xxx` con mensaje en español y se traducen a HTTP: `50001`/`50010` → **`409`**, resto de `5xxxx` → **`400`**, fallo de conexión → **`503`**. | `traducir_error_sql` |
| **RN-15** | Toda respuesta exitosa de `POST/PUT/PATCH` incluye **`mensaje`** en español (HU-13); los errores siempre son `{"detail": "…"}`. | validadores centrales + routers |

---

## 7 · Requerimientos no funcionales

| ID | Categoría | Requerimiento |
|---|---|---|
| **NFR-01** | Seguridad | JWT por roles, contraseñas bcrypt, `.env` fuera de Git (`.env.example` como plantilla), CORS restringido a `localhost:4200`, bloqueo por intentos. |
| **NFR-02** | Accesibilidad | WCAG 2.1 AA: enfoque visible, objetivos ≥ 48 px, salto al contenido, control de tamaño de letra, semántica ARIA. |
| **NFR-03** | Rendimiento | Rutas con carga diferida (bundle inicial ≈ 315 kB) e índices SQL sobre las consultas calientes. |
| **NFR-04** | Disponibilidad | La API **arranca aunque la BD esté caída** (aviso en bitácora) y responde `503` por petición hasta recuperarse. |
| **NFR-05** | Localización | Interfaz, validaciones y mensajes de negocio en **español**; montos en soles (PEN). |
| **NFR-06** | Trazabilidad | Auditoría implícita en `movimientos_inventario` (autor, fecha, saldos) y en `despachos_receta`. |
| **NFR-07** | Portabilidad | SQL Server Express local (`localhost\SQLEXPRESS`) o Docker (1433); drivers ODBC 17/18 detectados automáticamente; autenticación SQL o de Windows (`DB_TRUSTED_CONNECTION`). |
| **NFR-10** | Seguridad de datos | Credenciales de SQL Server solo en `backend/.env` (ignorado en Git); nunca se devuelven en respuestas ni en `/health/db`. El aislamiento por olla lo aplica la API (`get_id_olla_contexto`). |
| **NFR-11** | Observabilidad | `GET /health/db` para monitoreo de la BD; errores de traducción y de API Ninjas quedan en bitácora (`logger.warning`). |
| **NFR-08** | Calidad | Pruebas automatizadas (`pytest`) y compilación del frontend (`ng build`) ejecutadas en **GitHub Actions** en cada push/PR. |
| **NFR-09** | Documentación | OpenAPI en `/docs`; `README.md` y `PRD.md` **sin credenciales en texto plano**. |

---

## 8 · Criterios de aceptación para pruebas E2E

> Formato: **Dado** (contexto) / **Cuando** (acción) / **Entonces** (resultado verificable). Cubren el camino crítico de extremo a extremo: Angular → FastAPI → SQL Server.

| ID | Escenario | Dado | Cuando | Entonces |
|---|---|---|---|---|
| **CEN-01** | KPIs públicos | La API está desplegada y hay ollas sembradas | Se ejecuta `GET /api/public/kpis` sin sesión | `200` con `ollas_activas`, `beneficiarios_hoy`, `total_donaciones` y `monto_donado_soles` coherentes con los datos de la BD |
| **CEN-02** | Directorio y ficha | Existen ollas en varios distritos | Se consulta `GET /api/public/ubigeos` y luego `GET /api/public/ollas?…` con filtros en cascada, y `GET /api/public/ollas/{id}` | `200` con listado filtrable; la ficha muestra código único y estado; un `id` inexistente devuelve `404` con `detail` en español |
| **CEN-03** | Registro de olla sin cuenta | Portal público sin sesión | Se envía `POST /api/public/ollas` con datos válidos e `id_ubigeo` válido | `201` con `mensaje` y código `AYNI-####`; la olla aparece activa en el directorio. Con distrito inválido → `400` «El distrito seleccionado no es válido.»; repetir nombre+distrito → `409` |
| **CEN-04** | Registro en un paso | Formulario de registro completo | Se envía `POST /api/auth/registro-olla` | `201` con `mensaje`; con username ya usado → `409`; el nuevo usuario puede iniciar sesión de inmediato |
| **CEN-05** | Login y sesión | Cuenta semilla activa | Se envía `POST /api/auth/login` con credenciales correctas y luego `GET /api/auth/me` con el token | `200` en ambos; el perfil confirma `rol` y olla asignada. Sin token → `401`; con token manipulado → `401` «El token de acceso no es válido…» |
| **CEN-06** | Bloqueo por intentos | Cuenta sin bloquear | Se falla el login **5 veces** | Los primeros `401` informan intentos restantes; desde el 5.º → `423` con minutos de bloqueo; también `423` si se acierta la contraseña dentro de la ventana de bloqueo |
| **CEN-07** | Aislamiento por olla | Dos dirigentas distintas (ollas 1 y 2) autenticadas | Cada una llama `GET /api/olla/mi-olla` y a recursos con alcance | Cada una recibe **solo su propia olla** (el `id_olla` ajeno se ignora). Un ADMIN sin `?id_olla=N` recibe `400`; con `id_olla` inexistente, `404` |
| **CEN-08** | Entrada de inventario | DIRIGENTA autenticada, insumo existente | Se envía `POST /api/inventario/entrada` con cantidad > 0 | `201` con `mensaje`; se crea lote `LT-#####`, el stock aumenta y aparece movimiento `E-#####` con saldo anterior/posterior. Cantidad ≤ 0 → `400` |
| **CEN-09** | Salida PEPS | Dos lotes del mismo insumo con distintas fechas de ingreso | Se registra `POST /api/inventario/salida` por debajo del saldo total | Se consume **primero el lote más antiguo**; si la cantidad supera el saldo → `400` «Stock vigente insuficiente…» y **ni lotes ni kardex cambian** |
| **CEN-10** | Descarte de lote | Lote vencido de la propia olla | Se envía `POST /api/inventario/descartar` sin motivo y luego con motivo | Sin motivo → `400`; con motivo → `200`, lote en estado `DESCARTADO` y movimiento `D-#####` registrado. Lote ajeno → `400` |
| **CEN-11** | Donaciones | DIRIGENTA autenticada | Se crea un donante (`POST /api/donantes`) y una donación monetaria (`POST /api/donaciones`) | Ambos `201` con `mensaje`; el monto suma en `GET /api/reportes/resumen` y en `GET /api/public/kpis` |
| **CEN-12** | Despacho atómico de receta | Receta activa cuyo requerimiento **supera** el stock disponible | Se envía `POST /api/recetas/despachar` | `400` y **cero** movimientos/lotes modificados. Repetido con stock suficiente → `200`, salidas PEPS por cada ingrediente y fila en `despachos_receta` con las raciones servidas |
| **CEN-13** | Reportes y CSV | Movimientos existentes en la olla | Se consultan `GET /api/reportes/resumen` y `GET /api/reportes/exportar-csv` | `200` en ambos; el CSV descarga con cabeceras y filas del kardex |
| **CEN-14** | Permisos de ADMIN | Una DIRIGENTA y un ADMIN autenticados | La DIRIGENTA llama a `/api/admin/*` y el ADMIN lista y cambia el estado de una olla | DIRIGENTA → `403` «Solo el administrador…»; ADMIN → `200` con `mensaje` y la olla queda desactivada/activada (visible en el portal) |
| **CEN-15** | Gestión de usuarios | Cuenta bloqueada por intentos | El ADMIN aplica `PATCH /api/admin/usuarios/{id}` con desbloqueo/activación | `200` con `mensaje`; la cuenta puede volver a autenticarse y su contador de intentos queda en 0 |
| **CEN-16** | Frontend E2E | Angular compilado (`npm run build` sin errores) | Navegar sin sesión a una ruta protegida, iniciar sesión como DIRIGENTA y como ADMIN | Las rutas protegidas redirigen a `/login`; tras el login se entra al panel según el rol; el portal público muestra KPIs y directorio; **todo `POST/PUT/PATCH` exitoso muestra un `mensaje` en español** |
| **CEN-17** | Resiliencia | API desplegada con SQL Server detenido | Se consulta `GET /api/health` y cualquier endpoint con datos | `503` con `detail` en español (la API no se cae); al restablecer la BD, las peticiones responden `200` sin reiniciar |
| **CEN-18** | Salud de la BD | API en `:8000` con SQL Server configurado en `.env` | Se consulta `GET /health/db` | `200` `{"status": "ok"}`; con SQL Server detenido o mal configurado → `503` con mensaje corto en español y **sin credenciales** |
| **CEN-19** | Recetario externo en español | DIRIGENTA autenticada y `API_NINJAS_KEY` configurada | Se busca «lentejas» en la vista *recetas* (`GET /api/recetas/externas?q=lentejas`) | `200`; `consulta_en` en inglés; título, porciones («N porciones»), ingredientes (viñetas) y pasos (numerados) en español; una segunda búsqueda igual responde desde caché. Sin clave → recetas locales con `aviso` |

---

## 9 · Aseguramiento de calidad e integración continua

| Nivel | Herramienta | Comando | Cobertura |
|---|---|---|---|
| Unitarias/Integration API | `pytest` + `httpx` (`TestClient`) | `uv run pytest` (desde `backend/`) | 10 pruebas: `/docs`, rutas OpenAPI, salud, validación `422` en español, `401`, `403`, `404` — **no requieren base de datos** (doble de conexión en `tests/conftest.py`). |
| Build frontend | Angular CLI | `npm run build` (desde `frontend/`) | Typecheck TypeScript + build de producción (bundle inicial ≈ 315 kB). |
| CI | GitHub Actions (`.github/workflows/ci.yml`) | push a `main`/`master`/`frontend` y pull requests | Dos trabajos paralelos: **Backend** (uv → ODBC (`unixodbc-dev`) → `uv sync` → carga de la app → `pytest`) y **Frontend** (Node 22 → `npm ci` → `ng build`). |

**Pruebas E2E manuales:** usar la matriz de la sección 8 contra un entorno local (SQL Server + API en `:8000` + Angular en `:4200`), apoyándose en `/docs` para la capa HTTP y en las vistas de `frontend/` para la capa de usuario.

---

## Anexo A · Usuarios semilla (entorno local)

Definidos en `database/AyniOllasDB.SQL` (solo correo y rol; **las contraseñas no están en este documento** — se generan localmente al arrancar la API y se documentan en `backend/README.md` para desarrollo local):

| Correo | Rol | Olla vinculada |
|---|---|---|
| `admin@ayni.org` | **ADMIN** | — |
| `dirigenta@ayni.org` | **DIRIGENTA** | Olla 1 |
| `maria.condori@ayni.org` | **DIRIGENTA** | Olla 2 |

## Anexo B · Glosario

| Término | Significado |
|---|---|
| **AYNI** | Reciprocidad andina; nombre de la plataforma. |
| **Olla común** | Cocina comunitaria que alimenta a familias de un barrio. |
| **PEPS / FIFO** | Primero en entrar, primero en salir: rotación de lotes por fecha de ingreso. |
| **Kardex** | Registro cronológico de movimientos de inventario con saldos. |
| **Lote** | Conjunto de un insumo ingresado en una fecha (con vencimiento opcional). |
| **Ración** | Porción servida; base del cálculo proporcional de recetas. |
| **SP** | Procedimiento almacenado de SQL Server. |
| **SSMS** | SQL Server Management Studio: herramienta para administrar la base de datos local. |
| **HU** | Historia de usuario (HU-01 … HU-14). |
| **JWT** | Token firmado (HS256) usado en la sesión de 8 horas. |
| **WCAG** | Pautas de accesibilidad web (2.1 AA en AYNI). |
| **CI** | Integración continua con GitHub Actions. |

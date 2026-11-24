# TestSprite AI Testing Report (MCP) — AYNI

---

## 1️⃣ Document Metadata

- **Project Name:** -AYNI-
- **Date:** 2026-11-23
- **Prepared by:** TestSprite AI Team (consolidado por OpenCode)
- **Frontend:** http://localhost:4200 (Angular 22, `ng serve`, modo development)
- **Backend:** http://127.0.0.1:8000/api (FastAPI + PostgreSQL/Supabase)
- **Plan de pruebas:** `testsprite_tests/testsprite_frontend_test_plan.json` (49 casos: TC001–TC049)
- **PRD estandarizado:** `testsprite_tests/standard_prd.json` (fuente: `PRD.md`)
- **Alcance ejecutado:** lote 1 de 4 → **TC001–TC015** (15 casos). Los lotes 2–4 (TC016–TC049) **no se ejecutaron** por decisión del usuario de detener la batería.
- **Credenciales usadas:** `dirigenta@ayni.org / Dirigenta1234!` (DIRIGENTA), `admin@ayni.org / Admin1234!` (ADMIN, previsto para lotes no ejecutados).

---

## 2️⃣ Requirement Validation Summary

### Requisito R1 — Autenticación y control de acceso por roles (M2)

#### Test TC001 Iniciar sesión y entrar al panel de mi olla
- **Test Code:** [TC001_Iniciar_sesin_y_entrar_al_panel_de_mi_olla.py](./TC001_Iniciar_sesin_y_entrar_al_panel_de_mi_olla.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/e6845a97-2602-4c72-a64e-0a7adb7a3ff5
- **Status:** ✅ Passed
- **Análisis:** Login con credenciales de DIRIGENTA y redirección correcta al panel; el token JWT se inyecta vía interceptor y la ruta `/panel` responde con `authGuard` activo.

#### Test TC005 Iniciar sesión y aterrizar en Mi Olla
- **Test Code:** [TC005_Iniciar_sesin_y_aterrizar_en_Mi_Olla.py](./TC005_Iniciar_sesin_y_aterrizar_en_Mi_Olla.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/708c44c9-59e3-431e-b0c2-08f96dad1889
- **Status:** ✅ Passed
- **Análisis:** Aterrizaje verificado en `/panel/mi-olla` tras autenticarse.

#### Test TC013 Mostrar un estado diario activo en Mi Olla
- **Test Code:** [TC013_Mostrar_un_estado_diario_activo_en_Mi_Olla.py](./TC013_Mostrar_un_estado_diario_activo_en_Mi_Olla.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/cfd6bf37-a1f8-4796-8416-f2d275a27022
- **Status:** ❌ Failed
- **Detalle de fallo:** La vista “Mi olla” mostró correctamente la olla activa («Olla Común Corazón Solidario», 121 beneficiarios), pero los intentos de abrir “Panel” no confirmaron el dashboard: la página visible quedó en la portada pública. No se pudo verificar el estado diario en el panel principal.
- **Hipótesis:** fallo de navegación del script de prueba (selector “Panel”) y/o pérdida de sesión hacia la portada; requiere revisión manual.

### Requisito R2 — Portal público sin sesión (M1)

#### Test TC009 Consultar KPIs del portal público
- **Test Code:** [TC009_Consultar_KPIs_del_portal_pblico.py](./TC009_Consultar_KPIs_del_portal_pblico.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/abd2f9b2-0c4c-4067-9e17-eb380c5d4967
- **Status:** ✅ Passed

#### Test TC014 Explorar el directorio público de ollas
- **Test Code:** [TC014_Explorar_el_directorio_pblico_de_ollas.py](./TC014_Explorar_el_directorio_pblico_de_ollas.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/05aa3636-add6-4df5-915c-d45f7c34650f
- **Status:** ✅ Passed

#### Test TC015 Abrir la ficha pública de una olla
- **Test Code:** [TC015_Abrir_la_ficha_pblica_de_una_olla.py](./TC015_Abrir_la_ficha_pblica_de_una_olla.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/da0164a3-cad1-46ec-a631-2e9b26f247cc
- **Status:** ✅ Passed

#### Test TC011 Ver KPI del portal público
- **Test Code:** [TC011_Ver_KPI_del_portal_pblico.py](./TC011_Ver_KPI_del_portal_pblico.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/bccd5bcf-fb9f-4602-b51c-6c376ca00e15
- **Status:** ❌ Failed
- **Detalle de fallo:** La sección «Indicadores de impacto en vivo» no mostró cifras. La página indicó: *«No se pudo conectar con la base de datos PostgreSQL. Verifique la conexión en .env.»*
- **Causa raíz:** `GET /api/public/kpis` devolvió 503 durante la ventana de ejecución (el endpoint `/health/db` respondió 503 justo antes de la batería y luego se recuperó). **Fallo ambiental (Supabase), no del código de la vista.**

#### Test TC004 Registrar una olla sin sesión
- **Test Code:** [TC004_Registrar_una_olla_sin_sesin.py](./TC004_Registrar_una_olla_sin_sesin.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/fe025214-eae7-43c9-9537-a13f94fdcc19
- **Status:** ⛔ Blocked
- **Detalle de fallo:** El selector «Departamento» solo mostró «Seleccione…» y Provincia/Distrito quedaron deshabilitados; no se pudo enviar el formulario.
- **Causa raíz:** `GET /api/public/ubigeos` no devolvió datos durante la misma ventana de inestabilidad de BD (verificado posteriormente: el endpoint responde `len=601` en 6/6 intentos). **Fallo ambiental.**

### Requisito R3 — Inventario PEPS: entradas (M4)

#### Test TC002 Registrar una entrada de inventario con éxito
- **Test Code:** [TC002_Registrar_una_entrada_de_inventario_con_xito.py](./TC002_Registrar_una_entrada_de_inventario_con_xito.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/c89c5c30-a88a-4634-86e8-c220cbd965aa
- **Status:** ✅ Passed
- **Análisis:** `POST /api/inventario/entrada` registró el lote y la interfaz confirmó en español.

#### Test TC010 Registrar una entrada de inventario válida
- **Test Code:** [TC010_Registrar_una_entrada_de_inventario_vlida.py](./TC010_Registrar_una_entrada_de_inventario_vlida.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/b41bf034-754e-4bc4-a572-df148dc4c419
- **Status:** ✅ Passed

### Requisito R4 — Panel “Mi Olla”: resumen y estado diario (M3)

#### Test TC007 Ver el resumen y los indicadores de la olla
- **Test Code:** [TC007_Ver_el_resumen_y_los_indicadores_de_la_olla.py](./TC007_Ver_el_resumen_y_los_indicadores_de_la_olla.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/dd91cd1f-1075-4174-9413-4fa8a3cd2866
- **Status:** ✅ Passed

#### Test TC012 Actualizar el estado diario de la olla
- **Test Code:** [TC012_Actualizar_el_estado_diario_de_la_olla.py](./TC012_Actualizar_el_estado_diario_de_la_olla.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/011afee5-9156-43ed-8389-ca0d94d9eb9e
- **Status:** ✅ Passed
- **Análisis:** `PUT /api/olla/estado-diario` persistió los cambios.

### Requisito R5 — Despacho de recetas con stock PEPS (M6)

#### Test TC006 Despachar una receta consumiendo stock PEPS
- **Test Code:** [TC006_Despachar_una_receta_consumiendo_stock_PEPS.py](./TC006_Despachar_una_receta_consumiendo_stock_PEPS.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/ce087739-7c26-4c91-a1e3-04c21ae845e9
- **Status:** ✅ Passed
- **Análisis:** Despacho confirmado y stock descontado según PEPS.

#### Test TC003 Despachar una receta consumiendo stock de forma atómica
- **Test Code:** [TC003_Despachar_una_receta_consumiendo_stock_de_forma_atmica.py](./TC003_Despachar_una_receta_consumiendo_stock_de_forma_atmica.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/83155e1a-e632-4153-8958-7a9003da4738
- **Status:** ⛔ Blocked
- **Detalle de fallo:** Tras el intento de despacho de «Saltado de Atún con Papa y Arroz», la página quedó vacía: sin confirmación ni inventario actualizado; no se pudo comprobar el consumo atómico.
- **Hipótesis:** ventana de 503 de BD durante la ejecución (misma ventana que TC011/TC004) dejó la recarga de recetas sin datos. El handler de errores de `recetas.ts` está implementado (`toast.error`) y **TC006 pasó en el mismo flujo**, por lo que no se observa un bug reproducido del flujo.

#### Test TC008 Despachar una receta con stock suficiente
- **Test Code:** [TC008_Despachar_una_receta_con_stock_suficiente.py](./TC008_Despachar_una_receta_con_stock_suficiente.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard-v3/o/80d6203d-da5b-569c-8d3c-f496b9c94ced/projects/mcp/4e557e36-ed4a-54db-991c-1a97f97e4b5b/test/c10aede8-bd6c-4661-9574-c568e532ea0f
- **Status:** ❌ Failed
- **Detalle de fallo:** Despacho de 40 raciones de «Saltado de Atún con Papa y Arroz»: el diálogo de confirmación indicó el descuento PEPS, pero la página final no mostró confirmación de éxito ni comidas servidas.
- **Hipótesis:** misma ventana de inestabilidad; el despacho puede haberse completado o no en backend sin que la vista lo reflejara. Requiere verificación manual del kardex.

---

## 3️⃣ Coverage & Matching Metrics

- **66.67% of tests passed** (10 de 15 ejecutados)
- **Ejecutados:** 15 · **Aprobados:** 10 · **Fallidos:** 4 · **Bloqueados:** 1
- **No ejecutados:** 34 (TC016–TC049) — batería detenida por el usuario

| Requirement | Total Tests | ✅ Passed | ❌ Failed | ⛔ Blocked | ⚪ No ejecutado |
|---|---|---|---|---|---|
| R1 Autenticación y control de acceso | 3 | 2 | 1 | 0 | 0 |
| R2 Portal público sin sesión | 5 | 3 | 1 | 1 | 0 |
| R3 Inventario PEPS (entradas) | 2 | 2 | 0 | 0 | 0 |
| R4 Panel Mi Olla (resumen/estado diario) | 2 | 2 | 0 | 0 | 0 |
| R5 Despacho de recetas | 3 | 1 | 1 | 1 | 0 |
| Cobertura de flujos críticos 1–5 (resto) | 34 | 0 | 0 | 0 | 34 |

### Estado de los 5 flujos críticos

| # | Flujo crítico | Estado | Detalle |
|---|---|---|---|
| 1 | Autenticación por roles + `authGuard`/`roleGuard` + aislamiento por olla | **Parcial** | Login y aterrizaje ✅ (TC001, TC005); TC013 ❌; pruebas de rol ADMIN y aislamiento quedaron en los lotes no ejecutados (TC029, TC030, TC040–TC042) |
| 2 | Inventario PEPS (entradas, lotes, salidas, descartes) | **Parcial** | Entradas ✅ (TC002, TC010); salidas/descartes/lotes sin ejecutar (TC016, TC021, TC031, TC036) |
| 3 | Despacho atómico y stock insuficiente | **Parcial** | TC006 ✅, TC003 ⛔, TC008 ❌; el bloqueo por stock insuficiente (TC019) no se ejecutó |
| 4 | Recetas externas API Ninjas traducidas | **No ejecutado** | TC045, TC047, TC048 pendientes (se prevé inglés por 429 del traductor de Google) |
| 5 | Gestión ADMIN con `admin@ayni.org` | **No ejecutado** | TC029, TC030, TC032, TC040–TC042, TC044 pendientes |

---

## 4️⃣ Key Gaps / Risks

1. **Inestabilidad de Supabase durante la ejecución (riesgo alto):** `/health/db` respondió 503 al inicio de la batería y los endpoints públicos fallaron dentro de la ventana de tests. Explica con alta probabilidad TC011, TC004 y posiblemente TC003/TC008. Verificado después: `/api/public/kpis`, `/api/public/ubigeos` y `/health/db` responden OK en 6/6 intentos. **Recomendación:** reintentar los 4 casos fallidos con la BD estable antes de darlos por definitivos.
2. **Modo development (`ng serve`):** TestSprite limita la ejecución a 15 pruebas de alta prioridad por lote; además el propio dev server es mono-hilo y puede degradar bajo carga concurrente (se registraron timeouts TCP al puerto 4200). Para cubrir los 49 casos hacen falta 4 lotes o pasar a build de producción servido en el puerto 4200.
3. **Flujos 4 y 5 sin cobertura:** las recetas externas (API Ninjas) y toda la gestión ADMIN quedaron fuera de la ejecución; el reporte no permite validar esos requerimientos del PRD.
4. **Traductor de Google bloqueado (429):** las recetas externas se esperan en inglés con aviso; es comportamiento conocido, no una regresión.
5. **TC013 sin confirmar:** el dashboard principal no se pudo verificar aunque “Mi olla” mostró datos correctos; conviene revisión manual del selector de navegación usado por el test.
6. **Artefactos disponibles:** plan completo (`testsprite_tests/testsprite_frontend_test_plan.json`, 49 casos), scripts generados TC001–TC015 en `testsprite_tests/`, reporte crudo (`testsprite_tests/tmp/raw_report.md`), resultados por caso (`testsprite_tests/tmp/test_results_lote1.json`) y enlaces de visualización por test en la sección 2.

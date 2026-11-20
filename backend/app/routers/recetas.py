"""HU-12: Calculadora de recetas locales, despacho atómico y recetario nutricional (API Ninjas)."""

import logging
import os
import unicodedata
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

import httpx
import pyodbc
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.database import consultar, ejecutar_sp, get_db
from app.schemas import DespacharReceta
from app.security import get_id_olla_contexto, get_usuario_actual

logger = logging.getLogger("ayni.recetas")
router = APIRouter(prefix="/api/recetas", tags=["Recetas"])

API_NINJAS_URL = "https://api.api-ninjas.com/v3/recipe"
CENTESIMA = Decimal("0.01")

SQL_RECETAS = """
SELECT r.id_receta, r.nombre, r.descripcion, r.raciones_base,
       ri.id_insumo, i.nombre AS insumo, i.unidad_base, ri.cantidad_base,
       ISNULL(s.stock_vigente, 0) AS stock_vigente
FROM dbo.recetas r
LEFT JOIN dbo.receta_ingredientes ri ON ri.id_receta = r.id_receta
LEFT JOIN dbo.insumos i ON i.id_insumo = ri.id_insumo
LEFT JOIN (
    SELECT id_insumo, SUM(cantidad_disponible) AS stock_vigente
    FROM dbo.lotes_inventario
    WHERE id_olla = ? AND estado = 'ACTIVO'
      AND (fecha_vencimiento IS NULL OR fecha_vencimiento >= CAST(GETDATE() AS DATE))
    GROUP BY id_insumo
) s ON s.id_insumo = ri.id_insumo
WHERE r.activa = 1
"""


def _cantidad_requerida(cantidad_base: Decimal, raciones: int, raciones_base: int) -> Decimal:
    """Misma fórmula que sp_DespacharRecetaAtomica (redondeo a 2 decimales, mínimo 0.01)."""
    valor = (Decimal(cantidad_base) * raciones / Decimal(raciones_base)).quantize(CENTESIMA, rounding=ROUND_HALF_UP)
    return max(valor, CENTESIMA)


def _armar_recetas(filas: list[dict[str, Any]], raciones: int | None) -> list[dict[str, Any]]:
    recetas: dict[int, dict[str, Any]] = {}
    for fila in filas:
        receta = recetas.setdefault(
            fila["id_receta"],
            {
                "id_receta": fila["id_receta"],
                "nombre": fila["nombre"],
                "descripcion": fila["descripcion"],
                "raciones_base": fila["raciones_base"],
                "raciones_calculadas": raciones or fila["raciones_base"],
                "ingredientes": [],
            },
        )
        if fila["id_insumo"] is None:
            continue
        requerida = _cantidad_requerida(fila["cantidad_base"], receta["raciones_calculadas"], fila["raciones_base"])
        stock = Decimal(fila["stock_vigente"])
        receta["ingredientes"].append(
            {
                "id_insumo": fila["id_insumo"],
                "insumo": fila["insumo"],
                "unidad_base": fila["unidad_base"],
                "cantidad_base": fila["cantidad_base"],
                "cantidad_requerida": requerida,
                "stock_vigente": stock,
                "alcanza": stock >= requerida,
                "faltante": max(requerida - stock, Decimal("0")),
            }
        )

    for receta in recetas.values():
        ingredientes = receta["ingredientes"]
        receta["se_puede_preparar"] = bool(ingredientes) and all(i["alcanza"] for i in ingredientes)
        if ingredientes:
            receta["raciones_maximas"] = int(
                min(i["stock_vigente"] * receta["raciones_base"] / Decimal(i["cantidad_base"]) for i in ingredientes)
            )
        else:
            receta["raciones_maximas"] = 0
    return list(recetas.values())


@router.get("", summary="Recetas activas con ingredientes, cálculo proporcional y stock vigente")
def listar_recetas(
    raciones: int | None = Query(default=None, gt=0, le=10000, description="Raciones a preparar (por defecto: raciones base)"),
    id_olla: int = Depends(get_id_olla_contexto),
    conn: pyodbc.Connection = Depends(get_db),
):
    filas = consultar(conn, SQL_RECETAS + " ORDER BY r.id_receta, i.nombre", id_olla)
    return _armar_recetas(filas, raciones)


@router.post("/despachar", summary="Servir receta: descuenta todos los ingredientes por PEPS o revierte todo")
def despachar(
    datos: DespacharReceta,
    usuario: dict = Depends(get_usuario_actual),
    id_olla: int = Depends(get_id_olla_contexto),
    conn: pyodbc.Connection = Depends(get_db),
):
    filas = consultar(conn, SQL_RECETAS + " AND r.id_receta = ? ORDER BY i.nombre", id_olla, datos.id_receta)
    if not filas:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="La receta seleccionada no existe o no está activa.")
    receta = _armar_recetas(filas, datos.raciones)[0]
    if not receta["ingredientes"]:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="La receta no tiene ingredientes configurados.")

    faltantes = [i for i in receta["ingredientes"] if not i["alcanza"]]
    if faltantes:
        detalle = ", ".join(f"{i['faltante']} {i['unidad_base']} de {i['insumo']}" for i in faltantes)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"No hay stock vigente suficiente para preparar {datos.raciones} raciones de «{receta['nombre']}». "
            f"Falta: {detalle}. No se descontó ningún insumo. Puede preparar como máximo {receta['raciones_maximas']} raciones.",
        )

    resultado = ejecutar_sp(
        conn,
        "EXEC dbo.sp_DespacharRecetaAtomica @id_olla = ?, @id_receta = ?, @id_usuario = ?, @raciones = ?",
        id_olla,
        datos.id_receta,
        usuario["id_usuario"],
        datos.raciones,
    )
    return {
        "mensaje": f"Se sirvieron {datos.raciones} raciones de «{receta['nombre']}». "
        "Los ingredientes fueron descontados del almacén por PEPS.",
        **resultado,
        "ingredientes_descontados": [
            {"id_insumo": i["id_insumo"], "insumo": i["insumo"], "cantidad": i["cantidad_requerida"], "unidad_base": i["unidad_base"]}
            for i in receta["ingredientes"]
        ],
    }


# ---------------------------------------------------------------------------
# Recetario externo (API Ninjas /v3/recipe) con respaldo local
# ---------------------------------------------------------------------------

TRADUCCIONES = {
    "lentejas": "lentil soup",
    "lenteja": "lentil soup",
    "pollo": "chicken",
    "arroz": "rice",
    "papa": "potato",
    "papas": "potato",
    "atun": "tuna",
    "fideo": "pasta",
    "fideos": "pasta",
    "tallarin": "pasta",
    "tallarines": "pasta",
    "sopa": "soup",
    "frejol": "beans",
    "frejoles": "beans",
    "menestra": "beans",
    "huevo": "egg",
    "pescado": "fish",
    "verduras": "vegetables",
    "quinua": "quinoa",
    "avena": "oatmeal",
    "carne": "beef",
}
PALABRAS_VACIAS = {"de", "con", "y", "a", "al", "la", "el", "los", "las", "en", "para"}


def _sin_tildes(texto: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", texto) if unicodedata.category(c) != "Mn")


def traducir_consulta(q: str) -> str:
    texto = _sin_tildes(q.lower().strip())
    if texto in TRADUCCIONES:
        return TRADUCCIONES[texto]
    palabras = [TRADUCCIONES.get(p, p) for p in texto.split() if p not in PALABRAS_VACIAS]
    # "sopa de pollo" -> "chicken soup"
    if "soup" in palabras and len(palabras) > 1:
        palabras = [p for p in palabras if p != "soup"] + ["soup"]
    resultado: list[str] = []
    for palabra in " ".join(palabras).split():
        if palabra not in resultado:
            resultado.append(palabra)
    return " ".join(resultado) or texto


RESPALDO_LOCAL: list[dict[str, Any]] = [
    {
        "claves": ["lentil", "soup", "beans"],
        "title": "Guiso de lentejas con arroz (receta comunitaria)",
        "servings": "50 raciones",
        "ingredients": ["4.5 kg de lentejas", "5 kg de arroz", "0.8 L de aceite vegetal", "3 cebollas grandes", "Ajo, comino y sal al gusto"],
        "instructions": "Remojar las lentejas 2 horas. Preparar un aderezo con cebolla, ajo y comino. Agregar las lentejas con agua y cocinar 40 minutos a fuego medio. Servir con arroz graneado.",
        "nutrition": {"calorias_kcal": 420, "proteinas_g": 18, "carbohidratos_g": 72, "grasas_g": 7, "hierro_mg": 5.2, "por": "ración"},
    },
    {
        "claves": ["chicken", "rice"],
        "title": "Arroz con pollo comunitario",
        "servings": "50 raciones",
        "ingredients": ["6 kg de arroz", "7 kg de pollo", "4 kg de papa", "1 L de aceite vegetal", "Culantro, arvejas y zanahoria"],
        "instructions": "Dorar las presas de pollo y reservar. Licuar culantro y preparar el aderezo. Añadir arroz, verduras y agua; cocinar tapado 20 minutos. Servir con el pollo y papa sancochada.",
        "nutrition": {"calorias_kcal": 560, "proteinas_g": 32, "carbohidratos_g": 70, "grasas_g": 14, "hierro_mg": 2.1, "por": "ración"},
    },
    {
        "claves": ["tuna", "potato"],
        "title": "Saltado de atún con papa y arroz",
        "servings": "50 raciones",
        "ingredients": ["25 latas de atún", "6 kg de papa", "5.5 kg de arroz", "0.7 L de aceite vegetal", "Cebolla, tomate y sillao"],
        "instructions": "Freír la papa en bastones. Saltear cebolla y tomate, agregar el atún escurrido y sazonar. Mezclar con la papa y servir con arroz.",
        "nutrition": {"calorias_kcal": 480, "proteinas_g": 24, "carbohidratos_g": 66, "grasas_g": 12, "hierro_mg": 1.8, "por": "ración"},
    },
    {
        "claves": ["pasta", "soup"],
        "title": "Sopa de fideos con verduras",
        "servings": "50 raciones",
        "ingredients": ["4 kg de fideo", "5 kg de papa", "3 kg de zanahoria", "2 kg de zapallo", "0.5 L de aceite vegetal"],
        "instructions": "Hervir agua con las verduras picadas por 20 minutos. Añadir el fideo y la papa en cubos; cocinar 12 minutos más. Sazonar y servir caliente.",
        "nutrition": {"calorias_kcal": 350, "proteinas_g": 10, "carbohidratos_g": 64, "grasas_g": 6, "hierro_mg": 1.5, "por": "ración"},
    },
]


def _respaldo(query_en: str) -> list[dict[str, Any]]:
    palabras = set(query_en.split())
    coincidencias = [r for r in RESPALDO_LOCAL if palabras & set(r["claves"])] or RESPALDO_LOCAL
    return [{k: v for k, v in r.items() if k != "claves"} for r in coincidencias]


def _ingrediente_a_texto(valor: Any) -> str:
    """v3 devuelve {"name", "quantity", "unit"}; v1 devolvía texto plano."""
    if isinstance(valor, dict):
        cantidad = valor.get("quantity")
        unidad = valor.get("unit")
        if unidad in (None, "", "unit"):
            unidad = ""
        partes = [str(cantidad) if cantidad not in (None, "") else "", str(unidad), str(valor.get("name") or "")]
        return " ".join(p for p in partes if p).strip()
    return str(valor).strip()


def _como_lista(valor: Any) -> list[str]:
    if valor is None:
        return []
    if isinstance(valor, list):
        return [t for t in (_ingrediente_a_texto(v) for v in valor) if t]
    return [p.strip() for p in str(valor).split("|") if p.strip()]


def _normalizar(item: dict[str, Any]) -> dict[str, Any]:
    instrucciones = item.get("instructions")
    pasos = [str(p).strip() for p in instrucciones if str(p).strip()] if isinstance(instrucciones, list) else (
        [instrucciones.strip()] if isinstance(instrucciones, str) and instrucciones.strip() else []
    )
    nutricion = item.get("nutrition") or item.get("nutrition_info")
    nota = None
    if nutricion is not None and not isinstance(nutricion, (dict, list)):
        # El plan gratuito de API Ninjas devuelve un texto en lugar de los valores nutricionales.
        nota = "La información nutricional de esta receta no está disponible en el plan actual de API Ninjas."
        nutricion = None
    return {
        "title": item.get("title") or item.get("name"),
        "servings": item.get("servings"),
        "ingredients": _como_lista(item.get("ingredients")),
        "instructions": " ".join(pasos) or None,
        "pasos": pasos,
        "nutrition": nutricion,
        "nutrition_nota": nota,
    }


@router.get("/externas", summary="Sugerencias de recetas con información nutricional (API Ninjas)")
async def recetas_externas(
    q: str = Query(..., min_length=2, max_length=80, description="Ej.: lentejas, pollo, arroz, papa, atún, fideo, sopa"),
    _: dict = Depends(get_usuario_actual),
):
    query_en = traducir_consulta(q)
    api_key = os.getenv("API_NINJAS_KEY", "").strip()
    aviso = None

    if api_key:
        try:
            async with httpx.AsyncClient(timeout=8.0) as cliente:
                respuesta = await cliente.get(API_NINJAS_URL, params={"title": query_en}, headers={"X-Api-Key": api_key})
            respuesta.raise_for_status()
            datos = respuesta.json()
            if isinstance(datos, dict):
                datos = datos.get("results") or datos.get("data") or datos.get("recipes") or [datos]
            recetas = [_normalizar(r) for r in datos if isinstance(r, dict)]
            recetas = [r for r in recetas if r["title"]]
            if recetas:
                return {"consulta": q, "consulta_en": query_en, "fuente": "API Ninjas", "total": len(recetas), "recetas": recetas}
            aviso = "API Ninjas no encontró recetas para su búsqueda. Se muestran sugerencias locales."
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("Fallo al consultar API Ninjas: %s", exc)
            aviso = "No se pudo conectar con el recetario externo. Se muestran sugerencias locales."
    else:
        aviso = "No se configuró API_NINJAS_KEY. Se muestran sugerencias locales."

    recetas = _respaldo(query_en)
    return {
        "consulta": q,
        "consulta_en": query_en,
        "fuente": "respaldo_local",
        "aviso": aviso,
        "total": len(recetas),
        "recetas": recetas,
    }

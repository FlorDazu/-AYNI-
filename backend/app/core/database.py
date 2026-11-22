"""Conexión a SQL Server (Docker o Express local) mediante pyodbc y utilidades de acceso a datos."""

import logging
import os
import re
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

import pyodbc
from dotenv import load_dotenv
from fastapi import HTTPException, status

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

logger = logging.getLogger("ayni.database")

DB_LOGIN_TIMEOUT = 5  # segundos para no bloquear la API si Docker está apagado
DRIVERS_SOPORTADOS = ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server")


def detectar_driver() -> str:
    """Devuelve el driver ODBC instalado: prioriza el del .env y luego 18 → 17."""
    preferido = os.getenv("DB_DRIVER", DRIVERS_SOPORTADOS[0]).strip()
    instalados = pyodbc.drivers()
    for candidato in (preferido, *DRIVERS_SOPORTADOS):
        if candidato in instalados:
            return candidato
    logger.warning(
        "No se encontró ODBC Driver 18/17 for SQL Server instalado (drivers: %s). Se usará '%s'.",
        instalados,
        preferido,
    )
    return preferido


def _escapar(valor: str) -> str:
    """Envuelve un valor entre llaves para soportar ';', '=' o '}' en la contraseña."""
    return "{" + valor.replace("}", "}}") + "}"


def construir_cadena_conexion() -> str:
    driver = detectar_driver()
    return (
        f"DRIVER={{{driver}}};"
        f"SERVER={os.getenv('DB_SERVER', 'localhost,1433')};"
        f"DATABASE={os.getenv('DB_NAME', 'AyniOllasDB')};"
        f"UID={os.getenv('DB_USER', 'sa')};"
        f"PWD={_escapar(os.getenv('DB_PASSWORD', ''))};"
        "Encrypt=yes;"
        "TrustServerCertificate=yes;"
    )


def obtener_conexion() -> pyodbc.Connection:
    """Abre una conexión en modo autocommit.

    Cada procedimiento almacenado gestiona su propia transacción; cuando se necesita
    agrupar varias operaciones se usa el context manager `transaccion`.
    """
    return pyodbc.connect(construir_cadena_conexion(), autocommit=True, timeout=DB_LOGIN_TIMEOUT)


def get_db() -> Iterator[pyodbc.Connection]:
    """Dependencia de FastAPI: entrega una conexión y la cierra al terminar."""
    conn = obtener_conexion()
    try:
        yield conn
    finally:
        conn.close()


@contextmanager
def transaccion(conn: pyodbc.Connection) -> Iterator[pyodbc.Cursor]:
    """Agrupa varias sentencias/SPs en una transacción explícita (todo o nada)."""
    cursor = conn.cursor()
    cursor.execute("BEGIN TRANSACTION;")
    try:
        yield cursor
        cursor.execute("IF @@TRANCOUNT > 0 COMMIT TRANSACTION;")
    except Exception:
        try:
            cursor.execute("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
        except pyodbc.Error:
            logger.exception("No se pudo revertir la transacción")
        raise
    finally:
        cursor.close()


# ---------------------------------------------------------------------------
# Helpers de lectura / ejecución
#
# La conexión NO usa MARS: si un cursor deja result sets pendientes (por ejemplo, el
# SELECT final de un SP o los conteos de filas de un INSERT ... OUTPUT), la siguiente
# sentencia en la misma conexión falla con "Connection is busy with results for another
# command". Por eso cada helper avanza hasta el primer result set con columnas, lee las
# filas y luego DRENA todos los conjuntos restantes (lo que además hace aflorar cualquier
# THROW lanzado después del primer SELECT) antes de cerrar el cursor.
# ---------------------------------------------------------------------------

def _ir_a_resultado(cursor: pyodbc.Cursor) -> bool:
    """Salta los conjuntos sin columnas (conteos de filas). True si hay un result set."""
    while cursor.description is None:
        if not cursor.nextset():
            return False
    return True


def _drenar(cursor: pyodbc.Cursor) -> None:
    while cursor.nextset():
        pass


def _a_dict(cursor: pyodbc.Cursor, fila: pyodbc.Row) -> dict[str, Any]:
    return dict(zip([c[0] for c in cursor.description], fila))


def ejecutar_en_cursor(cursor: pyodbc.Cursor, sql: str, *params: Any) -> list[dict[str, Any]]:
    """Ejecuta en un cursor existente (p. ej. dentro de `transaccion`) y consume TODO."""
    cursor.execute(sql, params)
    filas: list[dict[str, Any]] = []
    if _ir_a_resultado(cursor):
        filas = [_a_dict(cursor, f) for f in cursor.fetchall()]
    _drenar(cursor)
    return filas


def consultar(conn: pyodbc.Connection, sql: str, *params: Any) -> list[dict[str, Any]]:
    cursor = conn.cursor()
    try:
        return ejecutar_en_cursor(cursor, sql, *params)
    finally:
        cursor.close()


def consultar_uno(conn: pyodbc.Connection, sql: str, *params: Any) -> dict[str, Any] | None:
    filas = consultar(conn, sql, *params)
    return filas[0] if filas else None


def ejecutar_sp(conn: pyodbc.Connection, sql: str, *params: Any) -> dict[str, Any]:
    """Ejecuta un EXEC sp_... / INSERT ... OUTPUT y devuelve la primera fila del resultado."""
    return consultar_uno(conn, sql, *params) or {}


def ejecutar(conn: pyodbc.Connection, sql: str, *params: Any) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(sql, params)
        filas = cursor.rowcount
        _drenar(cursor)
        return filas
    finally:
        cursor.close()


# ---------------------------------------------------------------------------
# Traducción de errores de SQL Server a mensajes claros en español (HU-05)
# ---------------------------------------------------------------------------

_RE_NEGOCIO = re.compile(r"\[SQL Server\](?P<msg>.+?)\s*\((?P<num>5\d{4})\)")
_RE_NUMERO = re.compile(r"\((?P<num>\d{3,5})\)\s*\(SQL")
_CODIGOS_CONEXION = {"08001", "08S01", "HYT00", "HYT01", "28000", "IM002"}


def _texto(error: pyodbc.Error) -> str:
    return " ".join(str(a) for a in error.args)


def _mensaje_negocio(error: pyodbc.Error) -> tuple[int, str] | None:
    coincidencia = _RE_NEGOCIO.search(_texto(error))
    if not coincidencia:
        return None
    return int(coincidencia.group("num")), coincidencia.group("msg").strip()


def traducir_error_sql(error: pyodbc.Error) -> HTTPException:
    """Convierte un error de pyodbc en una HTTPException con mensaje en español."""
    negocio = _mensaje_negocio(error)
    if negocio:
        numero, mensaje = negocio
        codigo = status.HTTP_409_CONFLICT if numero in (50001, 50010) else status.HTTP_400_BAD_REQUEST
        return HTTPException(status_code=codigo, detail=mensaje)

    texto = _texto(error)
    sqlstate = str(error.args[0]) if error.args else ""
    numero = _RE_NUMERO.search(texto)
    numero = int(numero.group("num")) if numero else None

    if isinstance(error, pyodbc.InterfaceError) or sqlstate in _CODIGOS_CONEXION or numero == 18456:
        logger.error("Error de conexión a SQL Server: %s", texto)
        return HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No se pudo conectar con la base de datos. Verifique que SQL Server esté encendido "
            "y que los datos de conexión del archivo .env sean correctos.",
        )
    if numero in (2627, 2601):
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ya existe un registro con esos datos. Revise que no esté duplicado.",
        )
    if numero == 547:
        return HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Alguno de los datos enviados hace referencia a un registro que no existe o no cumple las reglas de la base de datos.",
        )
    if numero in (515, 8152, 2628):
        return HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Falta un dato obligatorio o algún texto supera la longitud permitida.",
        )
    if sqlstate == "23000":
        return HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="La operación entra en conflicto con datos existentes (registro duplicado o referencia inválida).",
        )
    logger.error("Error de base de datos no controlado: %s", texto, exc_info=error)
    return HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Ocurrió un error interno en la base de datos. Intente nuevamente en unos minutos.",
    )

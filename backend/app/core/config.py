"""Configuración centralizada de la API AYNI (pydantic-settings).

Todas las variables de entorno se leen **solo aquí** (desde `backend/.env`).
El resto del código importa el objeto `settings`:

    from app.core.config import settings
    settings.db_server

Cada campo tiene un valor por defecto seguro, de modo que la app y los tests
unitarios cargan aunque no exista `.env` (la BD responderá 503 por petición).
"""

import logging
from pathlib import Path
from typing import Annotated, Any

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

logger = logging.getLogger("ayni.config")

# backend/.env con ruta absoluta (parents[0]=core, parents[1]=app, parents[2]=backend),
# así funciona igual al lanzar uvicorn/pytest desde cualquier carpeta.
ENV_FILE = Path(__file__).resolve().parents[2] / ".env"

JWT_SECRET_EJEMPLO = "ayni_super_secret_jwt_key_2026_cambiar"
ORIGEN_FRONTEND = "http://localhost:4200"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ENV_FILE, env_file_encoding="utf-8", extra="ignore")

    # --- Base de datos: Microsoft SQL Server (SSMS) --------------------------
    # Instancia Express local: "localhost\\SQLEXPRESS" · Docker: "localhost,1433"
    db_server: str = "localhost,1433"
    db_name: str = "AyniOllasDB"
    db_user: str = "sa"
    db_password: str = ""
    db_driver: str = "ODBC Driver 18 for SQL Server"
    # true = autenticación de Windows (Trusted_Connection), sin usuario/contraseña.
    db_trusted_connection: bool = False
    db_timeout: int = 5  # segundos para no bloquear la API si SQL Server está apagado

    # --- Seguridad (JWT) -------------------------------------------------------
    jwt_secret: str = JWT_SECRET_EJEMPLO
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 480

    # --- CORS: "http://localhost:4200,http://127.0.0.1:4200" -------------------
    cors_origins: Annotated[list[str], NoDecode] = []

    # --- Recetario externo -------------------------------------------------------
    api_ninjas_key: str = ""
    # Opcional: clave de Google Cloud Translation API (traducción oficial y estable).
    # Sin ella se usan traductores gratuitos (Google sin clave → MyMemory).
    google_translate_api_key: str = ""

    @field_validator("cors_origins", mode="before")
    @classmethod
    def separar_origenes(cls, valor: Any) -> Any:
        """Convierte la lista separada por comas del .env en list[str]."""
        if isinstance(valor, str):
            return [origen.strip() for origen in valor.split(",") if origen.strip()]
        return valor

    @field_validator("db_server", "db_name", "db_user", "db_driver", "api_ninjas_key", "google_translate_api_key", "jwt_secret", mode="before")
    @classmethod
    def recortar(cls, valor: Any) -> Any:
        return valor.strip() if isinstance(valor, str) else valor

    @model_validator(mode="after")
    def incluir_frontend(self) -> "Settings":
        # http://localhost:4200 (Angular) siempre está permitido.
        if ORIGEN_FRONTEND not in self.cors_origins:
            self.cors_origins.append(ORIGEN_FRONTEND)
        return self

    @property
    def db_configurada(self) -> bool:
        """True si hay datos mínimos para intentar conectar a SQL Server."""
        return bool(self.db_server and self.db_name and (self.db_trusted_connection or self.db_user))

    def advertencias(self) -> list[str]:
        """Problemas de configuración que conviene revisar (sin exponer secretos)."""
        avisos = []
        if not self.db_trusted_connection and not self.db_password:
            avisos.append("DB_PASSWORD está vacía; configure la contraseña de SQL Server en backend/.env.")
        if self.jwt_secret == JWT_SECRET_EJEMPLO:
            avisos.append("JWT_SECRET usa el valor de ejemplo; cámbielo en backend/.env.")
        if not self.api_ninjas_key:
            avisos.append("API_NINJAS_KEY no está definida; el recetario externo usará recetas locales.")
        return avisos


settings = Settings()

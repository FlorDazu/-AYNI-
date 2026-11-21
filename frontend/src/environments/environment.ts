/**
 * Configuración global del entorno.
 *
 * El backend CORS solo permite el origen `http://localhost:4200` (ver
 * backend/app/main.py), por lo que el dev server de Angular corre en el
 * puerto 4200 por defecto y NO necesita proxy: las llamadas salen en
 * absolutos hacia la API.
 */
export const environment = {
  apiUrl: 'http://127.0.0.1:8000/api',
};

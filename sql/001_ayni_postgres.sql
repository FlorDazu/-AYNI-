-- ============================================================================
-- AYNI - Esquema de Base de Datos PostgreSQL / Supabase
-- Archivo de referencia: sql/001_ayni_postgres.sql
-- Compatible con PostgreSQL 14+, PL/pgSQL y Supabase (Session Pooler)
-- ============================================================================

-- Habilitar extensión para generación de identificadores únicos
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Esquema dbo para compatibilidad directa con las consultas del sistema
CREATE SCHEMA IF NOT EXISTS dbo;
SET search_path TO dbo, public;

-- ============================================================================
-- 1. TABLAS NORMALIZADAS (3FN - 11 TABLAS)
-- ============================================================================

-- 1.1 Ubigeos (Departamento, Provincia, Distrito)
CREATE TABLE IF NOT EXISTS dbo.ubigeos (
    id_ubigeo SERIAL PRIMARY KEY,
    departamento VARCHAR(80) NOT NULL,
    provincia VARCHAR(80) NOT NULL,
    distrito VARCHAR(80) NOT NULL,
    CONSTRAINT uq_ubigeos UNIQUE (departamento, provincia, distrito)
);

-- 1.2 Ollas Comunes (Registro directo activo, sin flujo de solicitudes previas)
CREATE TABLE IF NOT EXISTS dbo.ollas (
    id_olla SERIAL PRIMARY KEY,
    codigo_unico VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(150) NOT NULL,
    id_ubigeo INT NOT NULL,
    direccion VARCHAR(250) NOT NULL,
    referencia VARCHAR(250) NULL,
    telefono VARCHAR(20) NOT NULL,
    beneficiarios INT NOT NULL DEFAULT 0 CHECK (beneficiarios >= 0),
    atiende_hoy BOOLEAN NOT NULL DEFAULT TRUE,
    recibe_frescos BOOLEAN NOT NULL DEFAULT TRUE,
    necesidades_urgentes VARCHAR(500) NULL,
    activada BOOLEAN NOT NULL DEFAULT TRUE,
    verificada BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_registro TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ollas_ubigeo FOREIGN KEY (id_ubigeo) REFERENCES dbo.ubigeos(id_ubigeo)
);

-- 1.3 Usuarios (DIRIGENTA vinculada a su olla / ADMIN global)
CREATE TABLE IF NOT EXISTS dbo.usuarios (
    id_usuario SERIAL PRIMARY KEY,
    id_olla INT NULL,
    nombre_completo VARCHAR(150) NOT NULL,
    username VARCHAR(100) NOT NULL UNIQUE,
    telefono VARCHAR(20) NULL,
    password_hash VARCHAR(255) NOT NULL,
    rol VARCHAR(20) NOT NULL CHECK (rol IN ('ADMIN', 'DIRIGENTA')),
    intentos_fallidos INT NOT NULL DEFAULT 0,
    bloqueado_hasta TIMESTAMPTZ NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_usuarios_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla)
);

-- 1.4 Catálogo de Insumos
CREATE TABLE IF NOT EXISTS dbo.insumos (
    id_insumo SERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL UNIQUE,
    categoria VARCHAR(60) NOT NULL,
    unidad_base VARCHAR(20) NOT NULL CHECK (unidad_base IN ('kg', 'L', 'unidades')),
    requiere_vencimiento BOOLEAN NOT NULL DEFAULT TRUE,
    stock_minimo NUMERIC(10,2) NOT NULL DEFAULT 5.00 CHECK (stock_minimo >= 0)
);

-- 1.5 Donantes (Registro manual por olla)
CREATE TABLE IF NOT EXISTS dbo.donantes (
    id_donante SERIAL PRIMARY KEY,
    id_olla INT NOT NULL,
    tipo_donante VARCHAR(30) NOT NULL CHECK (tipo_donante IN ('PERSONA_NATURAL', 'EMPRESA', 'MERCADO', 'INSTITUCION')),
    nombre_razon_social VARCHAR(150) NOT NULL,
    documento VARCHAR(20) NULL,
    telefono VARCHAR(20) NULL,
    direccion VARCHAR(250) NULL,
    es_frecuente BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_registro TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_donantes_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla)
);

-- 1.6 Donaciones (Monetarias o en Especie)
CREATE TABLE IF NOT EXISTS dbo.donaciones (
    id_donacion SERIAL PRIMARY KEY,
    id_olla INT NOT NULL,
    id_donante INT NULL,
    tipo_donacion VARCHAR(20) NOT NULL CHECK (tipo_donacion IN ('ESPECIE', 'MONETARIA')),
    monto_soles NUMERIC(10,2) NULL CHECK (monto_soles IS NULL OR monto_soles >= 0),
    comprobante VARCHAR(80) NULL,
    descripcion VARCHAR(300) NOT NULL,
    fecha_donacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_donaciones_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla),
    CONSTRAINT fk_donaciones_donante FOREIGN KEY (id_donante) REFERENCES dbo.donantes(id_donante)
);

-- 1.7 Lotes de Inventario (Control PEPS y vencimientos)
CREATE TABLE IF NOT EXISTS dbo.lotes_inventario (
    id_lote SERIAL PRIMARY KEY,
    codigo_lote VARCHAR(30) NOT NULL UNIQUE,
    id_olla INT NOT NULL,
    id_insumo INT NOT NULL,
    id_donacion INT NULL,
    cantidad_inicial NUMERIC(10,2) NOT NULL CHECK (cantidad_inicial > 0),
    cantidad_disponible NUMERIC(10,2) NOT NULL CHECK (cantidad_disponible >= 0),
    fecha_ingreso TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_vencimiento DATE NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'AGOTADO', 'DESCARTADO')),
    CONSTRAINT fk_lotes_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla),
    CONSTRAINT fk_lotes_insumo FOREIGN KEY (id_insumo) REFERENCES dbo.insumos(id_insumo),
    CONSTRAINT fk_lotes_donacion FOREIGN KEY (id_donacion) REFERENCES dbo.donaciones(id_donacion)
);

-- 1.8 Movimientos de Inventario (Kardex correlativo #E-, #S-, #D-)
CREATE TABLE IF NOT EXISTS dbo.movimientos_inventario (
    id_movimiento SERIAL PRIMARY KEY,
    codigo_correlativo VARCHAR(30) NOT NULL UNIQUE,
    id_olla INT NOT NULL,
    id_insumo INT NOT NULL,
    id_lote INT NULL,
    id_usuario INT NOT NULL,
    tipo_movimiento VARCHAR(20) NOT NULL CHECK (tipo_movimiento IN ('ENTRADA', 'SALIDA', 'DESCARTE')),
    cantidad NUMERIC(10,2) NOT NULL CHECK (cantidad > 0),
    saldo_anterior NUMERIC(10,2) NOT NULL,
    saldo_posterior NUMERIC(10,2) NOT NULL,
    motivo VARCHAR(250) NOT NULL,
    fecha_movimiento TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_mov_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla),
    CONSTRAINT fk_mov_insumo FOREIGN KEY (id_insumo) REFERENCES dbo.insumos(id_insumo),
    CONSTRAINT fk_mov_lote FOREIGN KEY (id_lote) REFERENCES dbo.lotes_inventario(id_lote),
    CONSTRAINT fk_mov_usuario FOREIGN KEY (id_usuario) REFERENCES dbo.usuarios(id_usuario)
);

-- 1.9 Recetas Locales
CREATE TABLE IF NOT EXISTS dbo.recetas (
    id_receta SERIAL PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    descripcion VARCHAR(300) NULL,
    raciones_base INT NOT NULL DEFAULT 50 CHECK (raciones_base > 0),
    activa BOOLEAN NOT NULL DEFAULT TRUE
);

-- 1.10 Ingredientes por Receta
CREATE TABLE IF NOT EXISTS dbo.receta_ingredientes (
    id_receta_ingrediente SERIAL PRIMARY KEY,
    id_receta INT NOT NULL,
    id_insumo INT NOT NULL,
    cantidad_base NUMERIC(10,2) NOT NULL CHECK (cantidad_base > 0),
    CONSTRAINT fk_recing_receta FOREIGN KEY (id_receta) REFERENCES dbo.recetas(id_receta) ON DELETE CASCADE,
    CONSTRAINT fk_recing_insumo FOREIGN KEY (id_insumo) REFERENCES dbo.insumos(id_insumo),
    CONSTRAINT uq_receta_insumo UNIQUE (id_receta, id_insumo)
);

-- 1.11 Despachos de Recetas Servidas
CREATE TABLE IF NOT EXISTS dbo.despachos_receta (
    id_despacho SERIAL PRIMARY KEY,
    id_olla INT NOT NULL,
    id_receta INT NOT NULL,
    id_usuario INT NOT NULL,
    raciones_servidas INT NOT NULL CHECK (raciones_servidas > 0),
    fecha_despacho TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_desp_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla),
    CONSTRAINT fk_desp_receta FOREIGN KEY (id_receta) REFERENCES dbo.recetas(id_receta),
    CONSTRAINT fk_desp_usuario FOREIGN KEY (id_usuario) REFERENCES dbo.usuarios(id_usuario)
);

-- Índices de rendimiento
CREATE INDEX IF NOT EXISTS ix_ollas_ubigeo_activa ON dbo.ollas(id_ubigeo, activada);
CREATE INDEX IF NOT EXISTS ix_lotes_peps ON dbo.lotes_inventario(id_olla, id_insumo, estado, fecha_vencimiento, fecha_ingreso);
CREATE INDEX IF NOT EXISTS ix_movimientos_olla_fecha ON dbo.movimientos_inventario(id_olla, fecha_movimiento DESC);

-- ============================================================================
-- 2. FUNCIONES DE UTILIDAD (fn_correlativo, dateadd)
-- ============================================================================

CREATE OR REPLACE FUNCTION dbo.fn_correlativo(prefijo VARCHAR, id INT, digitos INT)
RETURNS VARCHAR AS $$
DECLARE
    num VARCHAR := id::VARCHAR;
BEGIN
    IF LENGTH(num) >= digitos THEN
        RETURN prefijo || num;
    END IF;
    RETURN prefijo || LPAD(num, digitos, '0');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Función de compatibilidad dateadd para facilitar consultas que usen DATEADD
CREATE OR REPLACE FUNCTION dbo.dateadd(datepart TEXT, num INT, ts TIMESTAMPTZ)
RETURNS TIMESTAMPTZ AS $$
BEGIN
    IF LOWER(datepart) IN ('minute', 'm', 'mi', 'n') THEN
        RETURN ts + (num || ' minutes')::INTERVAL;
    ELSIF LOWER(datepart) IN ('day', 'd', 'dd') THEN
        RETURN ts + (num || ' days')::INTERVAL;
    ELSIF LOWER(datepart) IN ('hour', 'hh') THEN
        RETURN ts + (num || ' hours')::INTERVAL;
    ELSIF LOWER(datepart) IN ('second', 's', 'ss') THEN
        RETURN ts + (num || ' seconds')::INTERVAL;
    ELSE
        RETURN ts + (num || ' ' || datepart)::INTERVAL;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- 3. PROCEDIMIENTOS Y FUNCIONES ATÓMICAS (6 PROCEDIMIENTOS EN PL/pgSQL)
-- ============================================================================

-- 3.0 Registro directo de Olla Común sin cuenta (HU-04)
CREATE OR REPLACE FUNCTION dbo.sp_registrar_olla(
    p_nombre VARCHAR(150),
    p_id_ubigeo INT,
    p_direccion VARCHAR(250),
    p_telefono VARCHAR(20),
    p_referencia VARCHAR(250) DEFAULT NULL,
    p_beneficiarios INT DEFAULT 0
)
RETURNS TABLE (
    id_olla INT,
    codigo_unico VARCHAR(20)
) AS $$
DECLARE
    v_nuevo_id_olla INT;
    v_codigo_generado VARCHAR(20);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ubigeos WHERE ubigeos.id_ubigeo = p_id_ubigeo) THEN
        RAISE EXCEPTION 'El distrito seleccionado no es válido. (50002)';
    END IF;

    IF EXISTS (SELECT 1 FROM dbo.ollas WHERE TRIM(ollas.nombre) ILIKE TRIM(p_nombre) AND ollas.id_ubigeo = p_id_ubigeo) THEN
        RAISE EXCEPTION 'Ya existe una olla común registrada con ese nombre en el distrito seleccionado. (50010)';
    END IF;

    INSERT INTO dbo.ollas (
        codigo_unico, nombre, id_ubigeo, direccion, referencia, telefono,
        beneficiarios, atiende_hoy, recibe_frescos, activada, verificada
    )
    VALUES (
        'TMP-' || SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8),
        TRIM(p_nombre), p_id_ubigeo, TRIM(p_direccion),
        NULLIF(TRIM(p_referencia), ''), p_telefono,
        COALESCE(p_beneficiarios, 0), TRUE, TRUE, TRUE, TRUE
    )
    RETURNING ollas.id_olla INTO v_nuevo_id_olla;

    v_codigo_generado := dbo.fn_correlativo('AYNI-', v_nuevo_id_olla, 4);

    UPDATE dbo.ollas
    SET codigo_unico = v_codigo_generado
    WHERE ollas.id_olla = v_nuevo_id_olla;

    RETURN QUERY SELECT v_nuevo_id_olla, v_codigo_generado;
END;
$$ LANGUAGE plpgsql;


-- 3.1 Registro directo de Olla Común + Cuenta Dirigenta en 1 solo paso (HU-04 / HU-06)
CREATE OR REPLACE FUNCTION dbo.sp_crear_cuenta_dirigenta(
    p_nombre_completo VARCHAR(150),
    p_username VARCHAR(100),
    p_telefono VARCHAR(20),
    p_password_hash VARCHAR(255),
    p_nombre_olla VARCHAR(150),
    p_id_ubigeo INT,
    p_direccion VARCHAR(250) DEFAULT 'Dirección por actualizar',
    p_referencia VARCHAR(250) DEFAULT NULL
)
RETURNS TABLE (
    id_usuario INT,
    id_olla INT,
    codigo_unico VARCHAR(20)
) AS $$
DECLARE
    v_nuevo_id_olla INT;
    v_nuevo_id_usuario INT;
    v_codigo_generado VARCHAR(20);
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.usuarios WHERE usuarios.username = p_username) THEN
        RAISE EXCEPTION 'El correo o usuario ya se encuentra registrado. (50001)';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.ubigeos WHERE ubigeos.id_ubigeo = p_id_ubigeo) THEN
        RAISE EXCEPTION 'El distrito seleccionado no es válido. (50002)';
    END IF;

    IF EXISTS (SELECT 1 FROM dbo.ollas WHERE TRIM(ollas.nombre) ILIKE TRIM(p_nombre_olla) AND ollas.id_ubigeo = p_id_ubigeo) THEN
        RAISE EXCEPTION 'Ya existe una olla común registrada con ese nombre en el distrito seleccionado. (50010)';
    END IF;

    INSERT INTO dbo.ollas (
        codigo_unico, nombre, id_ubigeo, direccion, referencia, telefono,
        beneficiarios, atiende_hoy, recibe_frescos, activada, verificada
    )
    VALUES (
        'TMP-' || SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8),
        TRIM(p_nombre_olla),
        p_id_ubigeo,
        COALESCE(NULLIF(TRIM(p_direccion), ''), 'Dirección por actualizar'),
        NULLIF(TRIM(p_referencia), ''),
        p_telefono,
        0, TRUE, TRUE, TRUE, TRUE
    )
    RETURNING ollas.id_olla INTO v_nuevo_id_olla;

    v_codigo_generado := dbo.fn_correlativo('AYNI-', v_nuevo_id_olla, 4);

    UPDATE dbo.ollas
    SET codigo_unico = v_codigo_generado
    WHERE ollas.id_olla = v_nuevo_id_olla;

    INSERT INTO dbo.usuarios (
        id_olla, nombre_completo, username, telefono, password_hash, rol, activo
    )
    VALUES (
        v_nuevo_id_olla, p_nombre_completo, p_username, p_telefono, p_password_hash, 'DIRIGENTA', TRUE
    )
    RETURNING usuarios.id_usuario INTO v_nuevo_id_usuario;

    RETURN QUERY SELECT v_nuevo_id_usuario, v_nuevo_id_olla, v_codigo_generado;
END;
$$ LANGUAGE plpgsql;


-- 3.2 Entrada de Inventario (Crea Lote #LT- y Movimiento #E-)
CREATE OR REPLACE FUNCTION dbo.sp_registrar_entrada_inventario(
    p_id_olla INT,
    p_id_insumo INT,
    p_id_usuario INT,
    p_id_donacion INT DEFAULT NULL,
    p_cantidad NUMERIC(10,2) DEFAULT 0,
    p_fecha_vencimiento DATE DEFAULT NULL,
    p_motivo VARCHAR(250) DEFAULT 'Ingreso de inventario'
)
RETURNS TABLE (
    id_lote INT,
    codigo_lote VARCHAR(30),
    id_movimiento INT,
    codigo_correlativo VARCHAR(30),
    saldo_posterior NUMERIC(10,2)
) AS $$
DECLARE
    v_saldo_anterior NUMERIC(10,2) := 0;
    v_saldo_posterior NUMERIC(10,2) := 0;
    v_nuevo_id_lote INT;
    v_nuevo_id_mov INT;
    v_codigo_lote VARCHAR(30);
    v_codigo_correlativo VARCHAR(30);
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad de entrada debe ser mayor a cero. (50003)';
    END IF;

    SELECT COALESCE(SUM(cantidad_disponible), 0)
    INTO v_saldo_anterior
    FROM dbo.lotes_inventario
    WHERE id_olla = p_id_olla AND id_insumo = p_id_insumo AND estado = 'ACTIVO';

    INSERT INTO dbo.lotes_inventario (
        codigo_lote, id_olla, id_insumo, id_donacion,
        cantidad_inicial, cantidad_disponible, fecha_vencimiento, estado
    )
    VALUES (
        'TMP-LT-' || SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8),
        p_id_olla, p_id_insumo, p_id_donacion,
        p_cantidad, p_cantidad, p_fecha_vencimiento, 'ACTIVO'
    )
    RETURNING lotes_inventario.id_lote INTO v_nuevo_id_lote;

    v_codigo_lote := dbo.fn_correlativo('LT-', v_nuevo_id_lote, 5);

    UPDATE dbo.lotes_inventario
    SET codigo_lote = v_codigo_lote
    WHERE lotes_inventario.id_lote = v_nuevo_id_lote;

    v_saldo_posterior := v_saldo_anterior + p_cantidad;

    INSERT INTO dbo.movimientos_inventario (
        codigo_correlativo, id_olla, id_insumo, id_lote, id_usuario,
        tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
    )
    VALUES (
        'TMP-E-' || SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8),
        p_id_olla, p_id_insumo, v_nuevo_id_lote, p_id_usuario,
        'ENTRADA', p_cantidad, v_saldo_anterior, v_saldo_posterior,
        COALESCE(NULLIF(TRIM(p_motivo), ''), 'Ingreso de inventario')
    )
    RETURNING movimientos_inventario.id_movimiento INTO v_nuevo_id_mov;

    v_codigo_correlativo := dbo.fn_correlativo('E-', v_nuevo_id_mov, 5);

    UPDATE dbo.movimientos_inventario
    SET codigo_correlativo = v_codigo_correlativo
    WHERE movimientos_inventario.id_movimiento = v_nuevo_id_mov;

    RETURN QUERY SELECT v_nuevo_id_lote, v_codigo_lote, v_nuevo_id_mov, v_codigo_correlativo, v_saldo_posterior;
END;
$$ LANGUAGE plpgsql;


-- 3.3 Salida PEPS (Primero en Vencer / Primero en Entrar -> Movimiento #S-)
CREATE OR REPLACE FUNCTION dbo.sp_registrar_salida_peps(
    p_id_olla INT,
    p_id_insumo INT,
    p_id_usuario INT,
    p_cantidad NUMERIC(10,2),
    p_motivo VARCHAR(250) DEFAULT 'Salida de almacén',
    p_silencioso BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    cantidad_retirada NUMERIC(10,2),
    saldo_restante NUMERIC(10,2)
) AS $$
DECLARE
    v_hoy DATE := CURRENT_DATE;
    v_stock_vigente NUMERIC(10,2) := 0;
    v_saldo_corriente NUMERIC(10,2) := 0;
    v_restante NUMERIC(10,2) := p_cantidad;
    v_consumir NUMERIC(10,2);
    v_nuevo_id_mov INT;
    v_codigo_mov VARCHAR(30);
    r_lote RECORD;
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad de salida debe ser mayor a cero. (50004)';
    END IF;

    -- Solo se despacha stock activo y no vencido por seguridad alimentaria
    SELECT COALESCE(SUM(cantidad_disponible), 0)
    INTO v_stock_vigente
    FROM dbo.lotes_inventario
    WHERE id_olla = p_id_olla
      AND id_insumo = p_id_insumo
      AND estado = 'ACTIVO'
      AND (fecha_vencimiento IS NULL OR fecha_vencimiento >= v_hoy);

    IF v_stock_vigente < p_cantidad THEN
        RAISE EXCEPTION 'Stock vigente insuficiente para cubrir la salida solicitada. (50005)';
    END IF;

    SELECT COALESCE(SUM(cantidad_disponible), 0)
    INTO v_saldo_corriente
    FROM dbo.lotes_inventario
    WHERE id_olla = p_id_olla
      AND id_insumo = p_id_insumo
      AND estado = 'ACTIVO';

    -- Recorrer lotes por orden PEPS (vencimiento próximo primero, luego fecha de ingreso)
    FOR r_lote IN
        SELECT id_lote, cantidad_disponible
        FROM dbo.lotes_inventario
        WHERE id_olla = p_id_olla
          AND id_insumo = p_id_insumo
          AND estado = 'ACTIVO'
          AND cantidad_disponible > 0
          AND (fecha_vencimiento IS NULL OR fecha_vencimiento >= v_hoy)
        ORDER BY
            CASE WHEN fecha_vencimiento IS NULL THEN 1 ELSE 0 END ASC,
            fecha_vencimiento ASC,
            fecha_ingreso ASC,
            id_lote ASC
        FOR UPDATE
    LOOP
        EXIT WHEN v_restante <= 0;

        IF r_lote.cantidad_disponible >= v_restante THEN
            v_consumir := v_restante;
        ELSE
            v_consumir := r_lote.cantidad_disponible;
        END IF;

        UPDATE dbo.lotes_inventario
        SET cantidad_disponible = cantidad_disponible - v_consumir,
            estado = CASE WHEN (cantidad_disponible - v_consumir) <= 0 THEN 'AGOTADO' ELSE 'ACTIVO' END
        WHERE id_lote = r_lote.id_lote;

        INSERT INTO dbo.movimientos_inventario (
            codigo_correlativo, id_olla, id_insumo, id_lote, id_usuario,
            tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
        )
        VALUES (
            'TMP-S-' || SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8),
            p_id_olla, p_id_insumo, r_lote.id_lote, p_id_usuario,
            'SALIDA', v_consumir, v_saldo_corriente, (v_saldo_corriente - v_consumir),
            COALESCE(NULLIF(TRIM(p_motivo), ''), 'Salida PEPS')
        )
        RETURNING id_movimiento INTO v_nuevo_id_mov;

        v_codigo_mov := dbo.fn_correlativo('S-', v_nuevo_id_mov, 5);

        UPDATE dbo.movimientos_inventario
        SET codigo_correlativo = v_codigo_mov
        WHERE id_movimiento = v_nuevo_id_mov;

        v_saldo_corriente := v_saldo_corriente - v_consumir;
        v_restante := v_restante - v_consumir;
    END LOOP;

    IF NOT p_silencioso THEN
        RETURN QUERY SELECT p_cantidad, v_saldo_corriente;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- 3.4 Descarte de Lote con Motivo Obligatorio (Movimiento #D-)
CREATE OR REPLACE FUNCTION dbo.sp_descartar_lote(
    p_id_olla INT,
    p_id_lote INT,
    p_id_usuario INT,
    p_motivo VARCHAR(250)
)
RETURNS TABLE (
    id_lote INT,
    codigo_lote VARCHAR(30),
    cantidad_descartada NUMERIC(10,2),
    codigo_correlativo VARCHAR(30),
    saldo_posterior NUMERIC(10,2)
) AS $$
DECLARE
    v_id_insumo INT;
    v_codigo_lote VARCHAR(30);
    v_cantidad_descartada NUMERIC(10,2);
    v_saldo_anterior NUMERIC(10,2) := 0;
    v_saldo_posterior NUMERIC(10,2) := 0;
    v_nuevo_id_mov INT;
    v_codigo_correlativo VARCHAR(30);
BEGIN
    IF LENGTH(TRIM(COALESCE(p_motivo, ''))) = 0 THEN
        RAISE EXCEPTION 'Debe indicar un motivo obligatorio para descartar el lote. (50006)';
    END IF;

    SELECT
        lotes_inventario.id_insumo,
        lotes_inventario.codigo_lote,
        lotes_inventario.cantidad_disponible
    INTO
        v_id_insumo, v_codigo_lote, v_cantidad_descartada
    FROM dbo.lotes_inventario
    WHERE lotes_inventario.id_lote = p_id_lote
      AND lotes_inventario.id_olla = p_id_olla
      AND lotes_inventario.estado = 'ACTIVO';

    IF v_id_insumo IS NULL OR v_cantidad_descartada <= 0 THEN
        RAISE EXCEPTION 'El lote no existe, no pertenece a su olla o ya no tiene saldo activo. (50007)';
    END IF;

    SELECT COALESCE(SUM(cantidad_disponible), 0)
    INTO v_saldo_anterior
    FROM dbo.lotes_inventario
    WHERE id_olla = p_id_olla AND id_insumo = v_id_insumo AND estado = 'ACTIVO';

    UPDATE dbo.lotes_inventario
    SET cantidad_disponible = 0,
        estado = 'DESCARTADO'
    WHERE lotes_inventario.id_lote = p_id_lote;

    v_saldo_posterior := v_saldo_anterior - v_cantidad_descartada;

    INSERT INTO dbo.movimientos_inventario (
        codigo_correlativo, id_olla, id_insumo, id_lote, id_usuario,
        tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
    )
    VALUES (
        'TMP-D-' || SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8),
        p_id_olla, v_id_insumo, p_id_lote, p_id_usuario,
        'DESCARTE', v_cantidad_descartada, v_saldo_anterior, v_saldo_posterior,
        TRIM(p_motivo)
    )
    RETURNING movimientos_inventario.id_movimiento INTO v_nuevo_id_mov;

    v_codigo_correlativo := dbo.fn_correlativo('D-', v_nuevo_id_mov, 5);

    UPDATE dbo.movimientos_inventario
    SET codigo_correlativo = v_codigo_correlativo
    WHERE movimientos_inventario.id_movimiento = v_nuevo_id_mov;

    RETURN QUERY SELECT p_id_lote, v_codigo_lote, v_cantidad_descartada, v_codigo_correlativo, v_saldo_posterior;
END;
$$ LANGUAGE plpgsql;


-- 3.5 Despacho Atómico de Receta (Descuenta todos los ingredientes por PEPS o revierte todo)
CREATE OR REPLACE FUNCTION dbo.sp_despachar_receta_atomica(
    p_id_olla INT,
    p_id_receta INT,
    p_id_usuario INT,
    p_raciones INT
)
RETURNS TABLE (
    id_despacho INT,
    raciones_servidas INT,
    receta VARCHAR(150)
) AS $$
DECLARE
    v_nombre_receta VARCHAR(150);
    v_raciones_base INT;
    v_motivo_despacho VARCHAR(250);
    v_cantidad_requerida NUMERIC(10,2);
    v_nuevo_id_despacho INT;
    r_ing RECORD;
BEGIN
    IF p_raciones <= 0 THEN
        RAISE EXCEPTION 'El número de raciones debe ser mayor a cero. (50008)';
    END IF;

    SELECT nombre, raciones_base
    INTO v_nombre_receta, v_raciones_base
    FROM dbo.recetas
    WHERE id_receta = p_id_receta AND activa = TRUE;

    IF v_nombre_receta IS NULL THEN
        RAISE EXCEPTION 'La receta seleccionada no existe o no está activa. (50009)';
    END IF;

    v_motivo_despacho := 'Preparación de receta: ' || v_nombre_receta || ' (' || p_raciones::TEXT || ' raciones)';

    -- Descontar cada ingrediente por PEPS de forma atómica
    FOR r_ing IN
        SELECT id_insumo, cantidad_base
        FROM dbo.receta_ingredientes
        WHERE id_receta = p_id_receta
    LOOP
        v_cantidad_requerida := ROUND((r_ing.cantidad_base * p_raciones)::NUMERIC / v_raciones_base::NUMERIC, 2);
        IF v_cantidad_requerida < 0.01 THEN
            v_cantidad_requerida := 0.01;
        END IF;

        PERFORM dbo.sp_registrar_salida_peps(
            p_id_olla,
            r_ing.id_insumo,
            p_id_usuario,
            v_cantidad_requerida,
            v_motivo_despacho,
            TRUE
        );
    END LOOP;

    INSERT INTO dbo.despachos_receta (id_olla, id_receta, id_usuario, raciones_servidas)
    VALUES (p_id_olla, p_id_receta, p_id_usuario, p_raciones)
    RETURNING despachos_receta.id_despacho INTO v_nuevo_id_despacho;

    RETURN QUERY SELECT v_nuevo_id_despacho, p_raciones, v_nombre_receta;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 4. DATOS SEMILLA INICIALES
-- ============================================================================

-- 4.1 Ubigeos
INSERT INTO dbo.ubigeos (departamento, provincia, distrito) VALUES
('Lima', 'Lima', 'San Juan de Lurigancho'),
('Lima', 'Lima', 'Villa El Salvador'),
('Lima', 'Lima', 'Comas'),
('Lima', 'Lima', 'Villa María del Triunfo'),
('Lima', 'Lima', 'Ate'),
('Cusco', 'Cusco', 'Santiago'),
('Arequipa', 'Arequipa', 'Cerro Colorado')
ON CONFLICT (departamento, provincia, distrito) DO NOTHING;

-- 4.2 Ollas Comunes
INSERT INTO dbo.ollas (
    codigo_unico, nombre, id_ubigeo, direccion, referencia, telefono,
    beneficiarios, atiende_hoy, recibe_frescos, necesidades_urgentes, activada, verificada
) VALUES
(
    'AYNI-0001', 'Olla Común Corazón Solidario', 1,
    'Mz. K Lt. 14 AA.HH. Bayóvar, San Juan de Lurigancho',
    'A dos cuadras del paradero 10 de Canto Grande',
    '987654321', 120, TRUE, TRUE,
    'Lentejas, aceite vegetal, pollo fresco y papas', TRUE, TRUE
),
(
    'AYNI-0002', 'Olla Común Manos Unidas del Sur', 2,
    'Sector 3 Grupo 15 Mz. C Lt. 8, Villa El Salvador',
    'Frente a la losa deportiva comunal',
    '987111222', 95, TRUE, TRUE,
    'Arroz, leche evaporada y verduras frescas', TRUE, TRUE
),
(
    'AYNI-0003', 'Olla Común Nueva Esperanza', 3,
    'Av. Túpac Amaru Km 14.5, Comas',
    'Altura del mercado zonal',
    '987333444', 70, FALSE, FALSE,
    'Menestras y conservas de pescado', FALSE, TRUE
)
ON CONFLICT (codigo_unico) DO NOTHING;

-- 4.3 Usuarios (PENDING_HASH es reemplazado automáticamente por bcrypt al arrancar la API)
INSERT INTO dbo.usuarios (id_olla, nombre_completo, username, telefono, password_hash, rol, activo) VALUES
(NULL, 'Administrador General AYNI', 'admin@ayni.org', '999000111', 'PENDING_HASH', 'ADMIN', TRUE),
(1, 'Rosa Huamán Quispe', 'dirigenta@ayni.org', '987654321', 'PENDING_HASH', 'DIRIGENTA', TRUE),
(2, 'María Elena Condori', 'maria.condori@ayni.org', '987111222', 'PENDING_HASH', 'DIRIGENTA', TRUE)
ON CONFLICT (username) DO NOTHING;

-- 4.4 Catálogo de Insumos
INSERT INTO dbo.insumos (nombre, categoria, unidad_base, requiere_vencimiento, stock_minimo) VALUES
('Arroz Superior', 'Granos y Cereales', 'kg', TRUE, 15.00),
('Lenteja Serrana', 'Menestras', 'kg', TRUE, 10.00),
('Aceite Vegetal', 'Aceites y Condimentos', 'L', TRUE, 6.00),
('Filete de Pollo', 'Proteínas', 'kg', TRUE, 8.00),
('Papa Blanca', 'Tubérculos y Verduras', 'kg', FALSE, 12.00),
('Leche Evaporada', 'Lácteos', 'unidades', TRUE, 12.00),
('Fideo Tallarín', 'Granos y Cereales', 'kg', TRUE, 8.00),
('Conserva de Atún', 'Proteínas', 'unidades', TRUE, 10.00)
ON CONFLICT (nombre) DO NOTHING;

-- 4.5 Donantes Manuales (Olla 1)
INSERT INTO dbo.donantes (id_olla, tipo_donante, nombre_razon_social, documento, telefono, direccion, es_frecuente) VALUES
(1, 'MERCADO', 'Asociación de Comerciantes Mercado Bayóvar', '20512345678', '981234567', 'Av. Canto Grande Cdra. 10', TRUE),
(1, 'PERSONA_NATURAL', 'Carlos Mendoza Rojas', '41258963', '982345678', 'Jr. Los Jazmines 245, SJL', TRUE),
(1, 'EMPRESA', 'Distribuidora Alimentos del Perú S.A.C.', '20601234567', '014567890', 'Av. Industrial 450, Ate', FALSE);

-- 4.6 Donaciones Iniciales (Olla 1)
INSERT INTO dbo.donaciones (id_olla, id_donante, tipo_donacion, monto_soles, comprobante, descripcion) VALUES
(1, 1, 'ESPECIE', NULL, 'GUIA-001', 'Donación semanal de arroz, lentejas y papas'),
(1, 2, 'MONETARIA', 250.00, 'YAPE-88412', 'Aporte solidario para compra de gas y frescos'),
(1, 3, 'ESPECIE', NULL, 'BOL-0045', 'Cajas de aceite vegetal, leche y conservas');

-- 4.7 Lotes Iniciales en Olla 1
INSERT INTO dbo.lotes_inventario (
    codigo_lote, id_olla, id_insumo, id_donacion,
    cantidad_inicial, cantidad_disponible, fecha_vencimiento, estado
) VALUES
('LT-00001', 1, 1, 1, 30.00, 24.00, CURRENT_DATE + INTERVAL '120 days', 'ACTIVO'),
('LT-00002', 1, 2, 1, 15.00, 12.00, CURRENT_DATE + INTERVAL '5 days',   'ACTIVO'),
('LT-00003', 1, 3, 3, 8.00,  4.00,  CURRENT_DATE + INTERVAL '90 days',  'ACTIVO'),
('LT-00004', 1, 4, 1, 12.00, 10.00, CURRENT_DATE + INTERVAL '3 days',   'ACTIVO'),
('LT-00005', 1, 5, 1, 25.00, 20.00, NULL,                             'ACTIVO'),
('LT-00006', 1, 6, 3, 24.00, 18.00, CURRENT_DATE + INTERVAL '150 days', 'ACTIVO'),
('LT-00007', 1, 8, 3, 12.00, 6.00,  CURRENT_DATE - INTERVAL '2 days',   'ACTIVO')
ON CONFLICT (codigo_lote) DO NOTHING;

-- 4.8 Movimientos Correlativos Iniciales (Olla 1)
INSERT INTO dbo.movimientos_inventario (
    codigo_correlativo, id_olla, id_insumo, id_lote, id_usuario,
    tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
) VALUES
('E-00001', 1, 1, 1, 2, 'ENTRADA', 30.00, 0.00, 30.00, 'Ingreso por donación Mercado Bayóvar'),
('S-00001', 1, 1, 1, 2, 'SALIDA',   6.00, 30.00, 24.00, 'Almuerzo comunitario del día'),
('E-00002', 1, 2, 2, 2, 'ENTRADA', 15.00, 0.00, 15.00, 'Ingreso por donación Mercado Bayóvar'),
('S-00002', 1, 2, 2, 2, 'SALIDA',   3.00, 15.00, 12.00, 'Menestra para almuerzo'),
('E-00003', 1, 3, 3, 2, 'ENTRADA',  8.00, 0.00,  8.00, 'Ingreso por donación Distribuidora Alimentos'),
('S-00003', 1, 3, 3, 2, 'SALIDA',   4.00,  8.00,  4.00, 'Consumo semanal de cocina'),
('E-00004', 1, 4, 4, 2, 'ENTRADA', 12.00, 0.00, 12.00, 'Ingreso de pollo fresco'),
('S-00004', 1, 4, 4, 2, 'SALIDA',   2.00, 12.00, 10.00, 'Preparación de segundo')
ON CONFLICT (codigo_correlativo) DO NOTHING;

-- 4.9 Recetas Comunitarias Base (50 raciones)
INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa) VALUES
('Guiso de Lentejas con Pollo y Arroz', 'Menestra rica en hierro acompañada de arroz graneado y presa de pollo.', 50, TRUE),
('Arroz con Pollo Comunitario', 'Plato tradicional rendidor con pollo y papa sancochada.', 50, TRUE),
('Saltado de Atún con Papa y Arroz', 'Preparación rápida y proteica con conserva de atún y papa.', 50, TRUE);

INSERT INTO dbo.receta_ingredientes (id_receta, id_insumo, cantidad_base) VALUES
-- Receta 1: Guiso de Lentejas con Pollo y Arroz (50 raciones)
(1, 2, 4.50), -- 4.5 kg Lenteja
(1, 1, 5.00), -- 5.0 kg Arroz
(1, 4, 6.00), -- 6.0 kg Pollo
(1, 3, 0.80), -- 0.8 L Aceite
-- Receta 2: Arroz con Pollo Comunitario (50 raciones)
(2, 1, 6.00), -- 6.0 kg Arroz
(2, 4, 7.00), -- 7.0 kg Pollo
(2, 5, 4.00), -- 4.0 kg Papa
(2, 3, 1.00), -- 1.0 L Aceite
-- Receta 3: Saltado de Atún con Papa y Arroz (50 raciones)
(3, 1, 5.50), -- 5.5 kg Arroz
(3, 5, 6.00), -- 6.0 kg Papa
(3, 3, 0.70)  -- 0.7 L Aceite
ON CONFLICT (id_receta, id_insumo) DO NOTHING;

-- Verificación final
SELECT
    (SELECT COUNT(*) FROM dbo.ubigeos) AS ubigeos,
    (SELECT COUNT(*) FROM dbo.ollas) AS ollas,
    (SELECT COUNT(*) FROM dbo.usuarios) AS usuarios,
    (SELECT COUNT(*) FROM dbo.insumos) AS insumos,
    (SELECT COUNT(*) FROM dbo.lotes_inventario) AS lotes,
    (SELECT COUNT(*) FROM dbo.recetas) AS recetas;

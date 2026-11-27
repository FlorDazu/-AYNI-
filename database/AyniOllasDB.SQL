USE master;
GO

-- Eliminar la base de datos anterior si existiera para empezar 100 % limpio
IF DB_ID('AyniOllasDB') IS NOT NULL
BEGIN
    ALTER DATABASE AyniOllasDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE AyniOllasDB;
END
GO

CREATE DATABASE AyniOllasDB;
GO

USE AyniOllasDB;
GO

-- ============================================================================
-- 1. TABLAS NORMALIZADAS (3FN - 11 TABLAS)
-- ============================================================================

-- 1.1 Ubigeos (Departamento, Provincia, Distrito)
CREATE TABLE dbo.ubigeos (
    id_ubigeo INT IDENTITY(1,1) PRIMARY KEY,
    departamento NVARCHAR(80) NOT NULL,
    provincia NVARCHAR(80) NOT NULL,
    distrito NVARCHAR(80) NOT NULL,
    CONSTRAINT UQ_ubigeos UNIQUE (departamento, provincia, distrito)
);
GO

-- 1.2 Ollas Comunes (Registro directo activo, sin flujo de solicitudes previas)
CREATE TABLE dbo.ollas (
    id_olla INT IDENTITY(1,1) PRIMARY KEY,
    codigo_unico NVARCHAR(20) NOT NULL UNIQUE,
    nombre NVARCHAR(150) NOT NULL,
    id_ubigeo INT NOT NULL,
    direccion NVARCHAR(250) NOT NULL,
    referencia NVARCHAR(250) NULL,
    telefono NVARCHAR(20) NOT NULL,
    beneficiarios INT NOT NULL DEFAULT 0 CHECK (beneficiarios >= 0),
    atiende_hoy BIT NOT NULL DEFAULT 1,
    recibe_frescos BIT NOT NULL DEFAULT 1,
    necesidades_urgentes NVARCHAR(500) NULL,
    activada BIT NOT NULL DEFAULT 1,
    verificada BIT NOT NULL DEFAULT 1,
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_ollas_ubigeo FOREIGN KEY (id_ubigeo) REFERENCES dbo.ubigeos(id_ubigeo)
);
GO

-- 1.3 Usuarios (DIRIGENTA vinculada a su olla / ADMIN global)
CREATE TABLE dbo.usuarios (
    id_usuario INT IDENTITY(1,1) PRIMARY KEY,
    id_olla INT NULL,
    nombre_completo NVARCHAR(150) NOT NULL,
    username NVARCHAR(100) NOT NULL UNIQUE,
    telefono NVARCHAR(20) NULL,
    password_hash NVARCHAR(255) NOT NULL,
    rol NVARCHAR(20) NOT NULL CHECK (rol IN ('ADMIN', 'DIRIGENTA')),
    intentos_fallidos INT NOT NULL DEFAULT 0,
    bloqueado_hasta DATETIME2 NULL,
    activo BIT NOT NULL DEFAULT 1,
    fecha_creacion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_usuarios_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla)
);
GO

-- 1.4 Catálogo de Insumos
CREATE TABLE dbo.insumos (
    id_insumo INT IDENTITY(1,1) PRIMARY KEY,
    nombre NVARCHAR(120) NOT NULL UNIQUE,
    categoria NVARCHAR(60) NOT NULL,
    unidad_base NVARCHAR(20) NOT NULL CHECK (unidad_base IN ('kg', 'L', 'unidades')),
    requiere_vencimiento BIT NOT NULL DEFAULT 1,
    stock_minimo DECIMAL(10,2) NOT NULL DEFAULT 5.00 CHECK (stock_minimo >= 0)
);
GO

-- 1.5 Donantes (Registro 100 % manual por olla)
CREATE TABLE dbo.donantes (
    id_donante INT IDENTITY(1,1) PRIMARY KEY,
    id_olla INT NOT NULL,
    tipo_donante NVARCHAR(30) NOT NULL CHECK (tipo_donante IN ('PERSONA_NATURAL', 'EMPRESA', 'MERCADO', 'INSTITUCION')),
    nombre_razon_social NVARCHAR(150) NOT NULL,
    documento NVARCHAR(20) NULL,
    telefono NVARCHAR(20) NULL,
    direccion NVARCHAR(250) NULL,
    es_frecuente BIT NOT NULL DEFAULT 0,
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_donantes_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla)
);
GO

-- 1.6 Donaciones (Monetarias o en Especie)
CREATE TABLE dbo.donaciones (
    id_donacion INT IDENTITY(1,1) PRIMARY KEY,
    id_olla INT NOT NULL,
    id_donante INT NULL, -- Referencia lógica a donantes (sin FK para evitar bucles; la API valida que sea de la misma olla)
    tipo_donacion NVARCHAR(20) NOT NULL CHECK (tipo_donacion IN ('ESPECIE', 'MONETARIA')),
    monto_soles DECIMAL(10,2) NULL CHECK (monto_soles IS NULL OR monto_soles >= 0),
    comprobante NVARCHAR(80) NULL,
    descripcion NVARCHAR(300) NOT NULL,
    fecha_donacion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_donaciones_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla)
);
GO

-- 1.7 Lotes de Inventario (Control PEPS y vencimientos)
CREATE TABLE dbo.lotes_inventario (
    id_lote INT IDENTITY(1,1) PRIMARY KEY,
    codigo_lote NVARCHAR(30) NOT NULL UNIQUE,
    id_olla INT NOT NULL,
    id_insumo INT NOT NULL,
    id_donacion INT NULL, -- Referencia lógica a donaciones (sin FK para evitar bucles; la valida sp_RegistrarEntradaInventario)
    cantidad_inicial DECIMAL(10,2) NOT NULL CHECK (cantidad_inicial > 0),
    cantidad_disponible DECIMAL(10,2) NOT NULL CHECK (cantidad_disponible >= 0),
    fecha_ingreso DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    fecha_vencimiento DATE NULL,
    estado NVARCHAR(20) NOT NULL DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'AGOTADO', 'DESCARTADO')),
    CONSTRAINT FK_lotes_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla),
    CONSTRAINT FK_lotes_insumo FOREIGN KEY (id_insumo) REFERENCES dbo.insumos(id_insumo)
);
GO

-- 1.8 Movimientos de Inventario (Kardex correlativo #E-, #S-, #D-)
CREATE TABLE dbo.movimientos_inventario (
    id_movimiento INT IDENTITY(1,1) PRIMARY KEY,
    codigo_correlativo NVARCHAR(30) NOT NULL UNIQUE,
    id_lote INT NOT NULL,    -- La olla y el insumo se obtienen del lote (3FN, sin datos repetidos)
    id_usuario INT NOT NULL, -- Referencia lógica a usuarios (sin FK para evitar bucles; la validan los procedimientos)
    tipo_movimiento NVARCHAR(20) NOT NULL CHECK (tipo_movimiento IN ('ENTRADA', 'SALIDA', 'DESCARTE')),
    cantidad DECIMAL(10,2) NOT NULL CHECK (cantidad > 0),
    saldo_anterior DECIMAL(10,2) NOT NULL,
    saldo_posterior DECIMAL(10,2) NOT NULL,
    motivo NVARCHAR(250) NOT NULL,
    fecha_movimiento DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_mov_lote FOREIGN KEY (id_lote) REFERENCES dbo.lotes_inventario(id_lote)
);
GO

-- 1.9 Recetas Locales
CREATE TABLE dbo.recetas (
    id_receta INT IDENTITY(1,1) PRIMARY KEY,
    nombre NVARCHAR(150) NOT NULL,
    descripcion NVARCHAR(300) NULL,
    raciones_base INT NOT NULL DEFAULT 50 CHECK (raciones_base > 0),
    activa BIT NOT NULL DEFAULT 1
);
GO

-- 1.10 Ingredientes por Receta
CREATE TABLE dbo.receta_ingredientes (
    id_receta_ingrediente INT IDENTITY(1,1) PRIMARY KEY,
    id_receta INT NOT NULL,
    id_insumo INT NOT NULL,
    cantidad_base DECIMAL(10,2) NOT NULL CHECK (cantidad_base > 0),
    CONSTRAINT FK_recing_receta FOREIGN KEY (id_receta) REFERENCES dbo.recetas(id_receta),
    CONSTRAINT FK_recing_insumo FOREIGN KEY (id_insumo) REFERENCES dbo.insumos(id_insumo),
    CONSTRAINT UQ_receta_insumo UNIQUE (id_receta, id_insumo)
);
GO

-- 1.11 Despachos de Recetas Servidas
CREATE TABLE dbo.despachos_receta (
    id_despacho INT IDENTITY(1,1) PRIMARY KEY,
    id_olla INT NOT NULL,
    id_receta INT NOT NULL,  -- Referencia lógica a recetas (sin FK para evitar bucles; la valida sp_DespacharRecetaAtomica)
    id_usuario INT NOT NULL, -- Referencia lógica a usuarios (sin FK para evitar bucles; la valida sp_DespacharRecetaAtomica)
    raciones_servidas INT NOT NULL CHECK (raciones_servidas > 0),
    fecha_despacho DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_desp_olla FOREIGN KEY (id_olla) REFERENCES dbo.ollas(id_olla)
);
GO

-- Índices de rendimiento
CREATE INDEX IX_ollas_ubigeo_activa ON dbo.ollas(id_ubigeo, activada);
CREATE INDEX IX_lotes_peps ON dbo.lotes_inventario(id_olla, id_insumo, estado, fecha_vencimiento, fecha_ingreso);
CREATE INDEX IX_movimientos_lote_fecha ON dbo.movimientos_inventario(id_lote, fecha_movimiento DESC);
CREATE INDEX IX_lotes_donacion ON dbo.lotes_inventario(id_donacion);
GO

-- ============================================================================
-- 2. FUNCIÓN DE CÓDIGOS CORRELATIVOS (AYNI-0001, LT-00001, E-00001, ...)
--    Rellena con ceros a la izquierda sin truncar cuando el id supera los dígitos.
-- ============================================================================
CREATE FUNCTION dbo.fn_Correlativo (@prefijo NVARCHAR(10), @id INT, @digitos INT)
RETURNS NVARCHAR(30)
AS
BEGIN
    DECLARE @num NVARCHAR(12) = CAST(@id AS NVARCHAR(12));
    IF LEN(@num) >= @digitos RETURN @prefijo + @num;
    RETURN @prefijo + REPLICATE(N'0', @digitos - LEN(@num)) + @num;
END;
GO

-- ============================================================================
-- 3. PROCEDIMIENTOS ALMACENADOS ATÓMICOS (6 SPs)
-- ============================================================================

-- 3.0 Registro directo de Olla Común sin cuenta (HU-04: activada y verificada al instante)
CREATE PROCEDURE dbo.sp_RegistrarOlla
    @nombre NVARCHAR(150),
    @id_ubigeo INT,
    @direccion NVARCHAR(250),
    @telefono NVARCHAR(20),
    @referencia NVARCHAR(250) = NULL,
    @beneficiarios INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.ubigeos WHERE id_ubigeo = @id_ubigeo)
            THROW 50002, 'El distrito seleccionado no es válido.', 1;

        IF EXISTS (SELECT 1 FROM dbo.ollas WHERE nombre = LTRIM(RTRIM(@nombre)) AND id_ubigeo = @id_ubigeo)
            THROW 50010, 'Ya existe una olla común registrada con ese nombre en el distrito seleccionado.', 1;

        BEGIN TRANSACTION;

        DECLARE @nuevo_id_olla INT;
        DECLARE @codigo_generado NVARCHAR(20);

        INSERT INTO dbo.ollas (
            codigo_unico, nombre, id_ubigeo, direccion, referencia, telefono,
            beneficiarios, atiende_hoy, recibe_frescos, activada, verificada
        )
        VALUES (
            'TMP-' + LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(36)), '-', ''), 8),
            LTRIM(RTRIM(@nombre)), @id_ubigeo, LTRIM(RTRIM(@direccion)),
            NULLIF(LTRIM(RTRIM(@referencia)), ''), @telefono,
            ISNULL(@beneficiarios, 0), 1, 1, 1, 1
        );

        SET @nuevo_id_olla = SCOPE_IDENTITY();
        SET @codigo_generado = dbo.fn_Correlativo(N'AYNI-', @nuevo_id_olla, 4);

        UPDATE dbo.ollas SET codigo_unico = @codigo_generado WHERE id_olla = @nuevo_id_olla;

        COMMIT TRANSACTION;

        SELECT @nuevo_id_olla AS id_olla, @codigo_generado AS codigo_unico;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3.1 Registro directo de Olla Común + Cuenta Dirigenta en 1 solo paso (HU-04 / HU-06)
CREATE PROCEDURE dbo.sp_CrearCuentaDirigenta
    @nombre_completo NVARCHAR(150),
    @username NVARCHAR(100),
    @telefono NVARCHAR(20),
    @password_hash NVARCHAR(255),
    @nombre_olla NVARCHAR(150),
    @id_ubigeo INT,
    @direccion NVARCHAR(250) = N'Dirección por actualizar',
    @referencia NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.usuarios WHERE username = @username)
            THROW 50001, 'El correo o usuario ya se encuentra registrado.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.ubigeos WHERE id_ubigeo = @id_ubigeo)
            THROW 50002, 'El distrito seleccionado no es válido.', 1;

        IF EXISTS (SELECT 1 FROM dbo.ollas WHERE nombre = LTRIM(RTRIM(@nombre_olla)) AND id_ubigeo = @id_ubigeo)
            THROW 50010, 'Ya existe una olla común registrada con ese nombre en el distrito seleccionado.', 1;

        DECLARE @nuevo_id_olla INT;
        DECLARE @nuevo_id_usuario INT;
        DECLARE @codigo_generado NVARCHAR(20);

        INSERT INTO dbo.ollas (
            codigo_unico, nombre, id_ubigeo, direccion, referencia, telefono,
            beneficiarios, atiende_hoy, recibe_frescos, activada, verificada
        )
        VALUES (
            'TMP-' + LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(36)), '-', ''), 8),
            LTRIM(RTRIM(@nombre_olla)),
            @id_ubigeo,
            ISNULL(NULLIF(LTRIM(RTRIM(@direccion)), ''), N'Dirección por actualizar'),
            NULLIF(LTRIM(RTRIM(@referencia)), ''),
            @telefono,
            0, 1, 1, 1, 1
        );

        SET @nuevo_id_olla = SCOPE_IDENTITY();
        SET @codigo_generado = dbo.fn_Correlativo(N'AYNI-', @nuevo_id_olla, 4);

        UPDATE dbo.ollas
        SET codigo_unico = @codigo_generado
        WHERE id_olla = @nuevo_id_olla;

        INSERT INTO dbo.usuarios (
            id_olla, nombre_completo, username, telefono, password_hash, rol, activo
        )
        VALUES (
            @nuevo_id_olla, @nombre_completo, @username, @telefono, @password_hash, 'DIRIGENTA', 1
        );

        SET @nuevo_id_usuario = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        SELECT
            @nuevo_id_usuario AS id_usuario,
            @nuevo_id_olla AS id_olla,
            @codigo_generado AS codigo_unico;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3.2 Entrada de Inventario (Crea Lote #LT- y Movimiento #E-)
CREATE PROCEDURE dbo.sp_RegistrarEntradaInventario
    @id_olla INT,
    @id_insumo INT,
    @id_usuario INT,
    @id_donacion INT = NULL,
    @cantidad DECIMAL(10,2),
    @fecha_vencimiento DATE = NULL,
    @motivo NVARCHAR(250) = N'Ingreso de inventario'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @in_nested_tx BIT = CASE WHEN @@TRANCOUNT > 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @cantidad <= 0
            THROW 50003, 'La cantidad de entrada debe ser mayor a cero.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.usuarios WHERE id_usuario = @id_usuario AND activo = 1)
            THROW 50012, 'El usuario que registra la operación no existe o está inactivo.', 1;

        IF @id_donacion IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.donaciones WHERE id_donacion = @id_donacion AND id_olla = @id_olla)
            THROW 50011, 'La donación indicada no existe o no pertenece a su olla.', 1;

        IF @in_nested_tx = 0 BEGIN TRANSACTION;

        DECLARE @saldo_anterior DECIMAL(10,2);
        DECLARE @saldo_posterior DECIMAL(10,2);
        DECLARE @nuevo_id_lote INT;
        DECLARE @nuevo_id_mov INT;
        DECLARE @codigo_lote NVARCHAR(30);
        DECLARE @codigo_correlativo NVARCHAR(30);

        SELECT @saldo_anterior = ISNULL(SUM(cantidad_disponible), 0)
        FROM dbo.lotes_inventario
        WHERE id_olla = @id_olla AND id_insumo = @id_insumo AND estado = 'ACTIVO';

        INSERT INTO dbo.lotes_inventario (
            codigo_lote, id_olla, id_insumo, id_donacion,
            cantidad_inicial, cantidad_disponible, fecha_vencimiento, estado
        )
        VALUES (
            'TMP-LT-' + LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(36)), '-', ''), 8),
            @id_olla, @id_insumo, @id_donacion,
            @cantidad, @cantidad, @fecha_vencimiento, 'ACTIVO'
        );

        SET @nuevo_id_lote = SCOPE_IDENTITY();
        SET @codigo_lote = dbo.fn_Correlativo(N'LT-', @nuevo_id_lote, 5);

        UPDATE dbo.lotes_inventario
        SET codigo_lote = @codigo_lote
        WHERE id_lote = @nuevo_id_lote;

        SET @saldo_posterior = @saldo_anterior + @cantidad;

        INSERT INTO dbo.movimientos_inventario (
            codigo_correlativo, id_lote, id_usuario,
            tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
        )
        VALUES (
            'TMP-E-' + LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(36)), '-', ''), 8),
            @nuevo_id_lote, @id_usuario,
            'ENTRADA', @cantidad, @saldo_anterior, @saldo_posterior,
            ISNULL(NULLIF(LTRIM(RTRIM(@motivo)), ''), N'Ingreso de inventario')
        );

        SET @nuevo_id_mov = SCOPE_IDENTITY();
        SET @codigo_correlativo = dbo.fn_Correlativo(N'E-', @nuevo_id_mov, 5);

        UPDATE dbo.movimientos_inventario
        SET codigo_correlativo = @codigo_correlativo
        WHERE id_movimiento = @nuevo_id_mov;

        IF @in_nested_tx = 0 COMMIT TRANSACTION;

        SELECT
            @nuevo_id_lote AS id_lote,
            @codigo_lote AS codigo_lote,
            @nuevo_id_mov AS id_movimiento,
            @codigo_correlativo AS codigo_correlativo,
            @saldo_posterior AS saldo_posterior;
    END TRY
    BEGIN CATCH
        IF @in_nested_tx = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3.3 Salida PEPS (Primero en Vencer / Primero en Entrar -> Movimiento #S-)
CREATE PROCEDURE dbo.sp_RegistrarSalidaPEPS
    @id_olla INT,
    @id_insumo INT,
    @id_usuario INT,
    @cantidad DECIMAL(10,2),
    @motivo NVARCHAR(250) = N'Salida de almacén',
    @silencioso BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @in_nested_tx BIT = CASE WHEN @@TRANCOUNT > 0 THEN 1 ELSE 0 END;

    BEGIN TRY
        IF @cantidad <= 0
            THROW 50004, 'La cantidad de salida debe ser mayor a cero.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.usuarios WHERE id_usuario = @id_usuario AND activo = 1)
            THROW 50012, 'El usuario que registra la operación no existe o está inactivo.', 1;

        IF @in_nested_tx = 0 BEGIN TRANSACTION;

        DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
        DECLARE @stock_vigente DECIMAL(10,2);
        DECLARE @saldo_corriente DECIMAL(10,2);

        -- Solo se despacha stock activo y no vencido por seguridad alimentaria
        SELECT @stock_vigente = ISNULL(SUM(cantidad_disponible), 0)
        FROM dbo.lotes_inventario
        WHERE id_olla = @id_olla
          AND id_insumo = @id_insumo
          AND estado = 'ACTIVO'
          AND (fecha_vencimiento IS NULL OR fecha_vencimiento >= @hoy);

        IF @stock_vigente < @cantidad
            THROW 50005, 'Stock vigente insuficiente para cubrir la salida solicitada.', 1;

        SELECT @saldo_corriente = ISNULL(SUM(cantidad_disponible), 0)
        FROM dbo.lotes_inventario
        WHERE id_olla = @id_olla AND id_insumo = @id_insumo AND estado = 'ACTIVO';

        DECLARE @restante DECIMAL(10,2) = @cantidad;
        DECLARE @lote_id INT;
        DECLARE @lote_disp DECIMAL(10,2);
        DECLARE @consumir DECIMAL(10,2);
        DECLARE @nuevo_id_mov INT;

        DECLARE cur_peps CURSOR LOCAL FAST_FORWARD FOR
            SELECT id_lote, cantidad_disponible
            FROM dbo.lotes_inventario
            WHERE id_olla = @id_olla
              AND id_insumo = @id_insumo
              AND estado = 'ACTIVO'
              AND cantidad_disponible > 0
              AND (fecha_vencimiento IS NULL OR fecha_vencimiento >= @hoy)
            ORDER BY
                CASE WHEN fecha_vencimiento IS NULL THEN 1 ELSE 0 END ASC,
                fecha_vencimiento ASC,
                fecha_ingreso ASC,
                id_lote ASC;

        OPEN cur_peps;
        FETCH NEXT FROM cur_peps INTO @lote_id, @lote_disp;

        WHILE @@FETCH_STATUS = 0 AND @restante > 0
        BEGIN
            SET @consumir = CASE WHEN @lote_disp >= @restante THEN @restante ELSE @lote_disp END;

            UPDATE dbo.lotes_inventario
            SET cantidad_disponible = cantidad_disponible - @consumir,
                estado = CASE WHEN (cantidad_disponible - @consumir) <= 0 THEN 'AGOTADO' ELSE 'ACTIVO' END
            WHERE id_lote = @lote_id;

            INSERT INTO dbo.movimientos_inventario (
                codigo_correlativo, id_lote, id_usuario,
                tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
            )
            VALUES (
                'TMP-S-' + LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(36)), '-', ''), 8),
                @lote_id, @id_usuario,
                'SALIDA', @consumir, @saldo_corriente, (@saldo_corriente - @consumir),
                ISNULL(NULLIF(LTRIM(RTRIM(@motivo)), ''), N'Salida PEPS')
            );

            SET @nuevo_id_mov = SCOPE_IDENTITY();

            UPDATE dbo.movimientos_inventario
            SET codigo_correlativo = dbo.fn_Correlativo(N'S-', @nuevo_id_mov, 5)
            WHERE id_movimiento = @nuevo_id_mov;

            SET @saldo_corriente = @saldo_corriente - @consumir;
            SET @restante = @restante - @consumir;

            FETCH NEXT FROM cur_peps INTO @lote_id, @lote_disp;
        END

        CLOSE cur_peps;
        DEALLOCATE cur_peps;

        IF @in_nested_tx = 0 COMMIT TRANSACTION;

        IF @silencioso = 0
        BEGIN
            SELECT
                @cantidad AS cantidad_retirada,
                @saldo_corriente AS saldo_restante;
        END
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'cur_peps') >= 0
        BEGIN
            CLOSE cur_peps;
            DEALLOCATE cur_peps;
        END
        IF @in_nested_tx = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3.4 Descarte de Lote con Motivo Obligatorio (Movimiento #D-)
CREATE PROCEDURE dbo.sp_DescartarLote
    @id_olla INT,
    @id_lote INT,
    @id_usuario INT,
    @motivo NVARCHAR(250)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF LEN(LTRIM(RTRIM(ISNULL(@motivo, '')))) = 0
            THROW 50006, 'Debe indicar un motivo obligatorio para descartar el lote.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.usuarios WHERE id_usuario = @id_usuario AND activo = 1)
            THROW 50012, 'El usuario que registra la operación no existe o está inactivo.', 1;

        BEGIN TRANSACTION;

        DECLARE @id_insumo INT;
        DECLARE @codigo_lote NVARCHAR(30);
        DECLARE @cantidad_descartada DECIMAL(10,2);
        DECLARE @saldo_anterior DECIMAL(10,2);
        DECLARE @saldo_posterior DECIMAL(10,2);
        DECLARE @nuevo_id_mov INT;
        DECLARE @codigo_correlativo NVARCHAR(30);

        SELECT
            @id_insumo = id_insumo,
            @codigo_lote = codigo_lote,
            @cantidad_descartada = cantidad_disponible
        FROM dbo.lotes_inventario
        WHERE id_lote = @id_lote AND id_olla = @id_olla AND estado = 'ACTIVO';

        IF @id_insumo IS NULL OR @cantidad_descartada <= 0
            THROW 50007, 'El lote no existe, no pertenece a su olla o ya no tiene saldo activo.', 1;

        SELECT @saldo_anterior = ISNULL(SUM(cantidad_disponible), 0)
        FROM dbo.lotes_inventario
        WHERE id_olla = @id_olla AND id_insumo = @id_insumo AND estado = 'ACTIVO';

        UPDATE dbo.lotes_inventario
        SET cantidad_disponible = 0,
            estado = 'DESCARTADO'
        WHERE id_lote = @id_lote;

        SET @saldo_posterior = @saldo_anterior - @cantidad_descartada;

        INSERT INTO dbo.movimientos_inventario (
            codigo_correlativo, id_lote, id_usuario,
            tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
        )
        VALUES (
            'TMP-D-' + LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(36)), '-', ''), 8),
            @id_lote, @id_usuario,
            'DESCARTE', @cantidad_descartada, @saldo_anterior, @saldo_posterior,
            LTRIM(RTRIM(@motivo))
        );

        SET @nuevo_id_mov = SCOPE_IDENTITY();
        SET @codigo_correlativo = dbo.fn_Correlativo(N'D-', @nuevo_id_mov, 5);

        UPDATE dbo.movimientos_inventario
        SET codigo_correlativo = @codigo_correlativo
        WHERE id_movimiento = @nuevo_id_mov;

        COMMIT TRANSACTION;

        SELECT
            @id_lote AS id_lote,
            @codigo_lote AS codigo_lote,
            @cantidad_descartada AS cantidad_descartada,
            @codigo_correlativo AS codigo_correlativo,
            @saldo_posterior AS saldo_posterior;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3.5 Despacho Atómico de Receta (Descuenta todos los ingredientes por PEPS o revierte todo)
CREATE PROCEDURE dbo.sp_DespacharRecetaAtomica
    @id_olla INT,
    @id_receta INT,
    @id_usuario INT,
    @raciones INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @raciones <= 0
            THROW 50008, 'El número de raciones debe ser mayor a cero.', 1;

        DECLARE @nombre_receta NVARCHAR(150);
        DECLARE @raciones_base INT;

        SELECT @nombre_receta = nombre, @raciones_base = raciones_base
        FROM dbo.recetas
        WHERE id_receta = @id_receta AND activa = 1;

        IF @nombre_receta IS NULL
            THROW 50009, 'La receta seleccionada no existe o no está activa.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.usuarios WHERE id_usuario = @id_usuario AND activo = 1)
            THROW 50012, 'El usuario que registra la operación no existe o está inactivo.', 1;

        BEGIN TRANSACTION;

        DECLARE @id_insumo INT;
        DECLARE @cantidad_base DECIMAL(10,2);
        DECLARE @cantidad_requerida DECIMAL(10,2);
        DECLARE @motivo_despacho NVARCHAR(250) = N'Preparación de receta: ' + @nombre_receta + N' (' + CAST(@raciones AS NVARCHAR(10)) + N' raciones)';

        DECLARE cur_ing CURSOR LOCAL FAST_FORWARD FOR
            SELECT id_insumo, cantidad_base
            FROM dbo.receta_ingredientes
            WHERE id_receta = @id_receta;

        OPEN cur_ing;
        FETCH NEXT FROM cur_ing INTO @id_insumo, @cantidad_base;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @cantidad_requerida = ROUND((@cantidad_base * @raciones) / CAST(@raciones_base AS DECIMAL(10,4)), 2);
            IF @cantidad_requerida < 0.01 SET @cantidad_requerida = 0.01;

            EXEC dbo.sp_RegistrarSalidaPEPS
                @id_olla = @id_olla,
                @id_insumo = @id_insumo,
                @id_usuario = @id_usuario,
                @cantidad = @cantidad_requerida,
                @motivo = @motivo_despacho,
                @silencioso = 1;

            FETCH NEXT FROM cur_ing INTO @id_insumo, @cantidad_base;
        END

        CLOSE cur_ing;
        DEALLOCATE cur_ing;

        INSERT INTO dbo.despachos_receta (id_olla, id_receta, id_usuario, raciones_servidas)
        VALUES (@id_olla, @id_receta, @id_usuario, @raciones);

        DECLARE @nuevo_id_despacho INT = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        SELECT
            @nuevo_id_despacho AS id_despacho,
            @raciones AS raciones_servidas,
            @nombre_receta AS receta;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'cur_ing') >= 0
        BEGIN
            CLOSE cur_ing;
            DEALLOCATE cur_ing;
        END
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- 4. DATOS SEMILLA INICIALES (CON FECHAS DINÁMICAS)
-- ============================================================================

-- 4.1 Ubigeos
INSERT INTO dbo.ubigeos (departamento, provincia, distrito) VALUES
(N'Lima', N'Lima', N'San Juan de Lurigancho'),
(N'Lima', N'Lima', N'Villa El Salvador'),
(N'Lima', N'Lima', N'Comas'),
(N'Lima', N'Lima', N'Villa María del Triunfo'),
(N'Lima', N'Lima', N'Ate'),
(N'Cusco', N'Cusco', N'Santiago'),
(N'Arequipa', N'Arequipa', N'Cerro Colorado');
GO

-- 4.2 Ollas Comunes (2 activas + 1 desactivada para probar gestión Admin)
INSERT INTO dbo.ollas (
    codigo_unico, nombre, id_ubigeo, direccion, referencia, telefono,
    beneficiarios, atiende_hoy, recibe_frescos, necesidades_urgentes, activada, verificada
) VALUES
(
    'AYNI-0001', N'Olla Común Corazón Solidario', 1,
    N'Mz. K Lt. 14 AA.HH. Bayóvar, San Juan de Lurigancho',
    N'A dos cuadras del paradero 10 de Canto Grande',
    '987654321', 120, 1, 1,
    N'Lentejas, aceite vegetal, pollo fresco y papas', 1, 1
),
(
    'AYNI-0002', N'Olla Común Manos Unidas del Sur', 2,
    N'Sector 3 Grupo 15 Mz. C Lt. 8, Villa El Salvador',
    N'Frente a la losa deportiva comunal',
    '987111222', 95, 1, 1,
    N'Arroz, leche evaporada y verduras frescas', 1, 1
),
(
    'AYNI-0003', N'Olla Común Nueva Esperanza', 3,
    N'Av. Túpac Amaru Km 14.5, Comas',
    N'Altura del mercado zonal',
    '987333444', 70, 0, 0,
    N'Menestras y conservas de pescado', 0, 1
);
GO

-- 4.3 Usuarios ('PENDING_HASH' será actualizado automáticamente por FastAPI al arrancar)
INSERT INTO dbo.usuarios (id_olla, nombre_completo, username, telefono, password_hash, rol, activo) VALUES
(NULL, N'Administrador General AYNI', 'admin@ayni.org', '999000111', 'PENDING_HASH', 'ADMIN', 1),
(1, N'Rosa Huamán Quispe', 'dirigenta@ayni.org', '987654321', 'PENDING_HASH', 'DIRIGENTA', 1),
(2, N'María Elena Condori', 'maria.condori@ayni.org', '987111222', 'PENDING_HASH', 'DIRIGENTA', 1);
GO

-- 4.4 Catálogo de Insumos
INSERT INTO dbo.insumos (nombre, categoria, unidad_base, requiere_vencimiento, stock_minimo) VALUES
(N'Arroz Superior', N'Granos y Cereales', 'kg', 1, 15.00),
(N'Lenteja Serrana', N'Menestras', 'kg', 1, 10.00),
(N'Aceite Vegetal', N'Aceites y Condimentos', 'L', 1, 6.00),
(N'Filete de Pollo', N'Proteínas', 'kg', 1, 8.00),
(N'Papa Blanca', N'Tubérculos y Verduras', 'kg', 0, 12.00),
(N'Leche Evaporada', N'Lácteos', 'unidades', 1, 12.00),
(N'Fideo Tallarín', N'Granos y Cereales', 'kg', 1, 8.00),
(N'Conserva de Atún', N'Proteínas', 'unidades', 1, 10.00);
GO

-- 4.5 Donantes Manuales (Olla 1)
INSERT INTO dbo.donantes (id_olla, tipo_donante, nombre_razon_social, documento, telefono, direccion, es_frecuente) VALUES
(1, 'MERCADO', N'Asociación de Comerciantes Mercado Bayóvar', '20512345678', '981234567', N'Av. Canto Grande Cdra. 10', 1),
(1, 'PERSONA_NATURAL', N'Carlos Mendoza Rojas', '41258963', '982345678', N'Jr. Los Jazmines 245, SJL', 1),
(1, 'EMPRESA', N'Distribuidora Alimentos del Perú S.A.C.', '20601234567', '014567890', N'Av. Industrial 450, Ate', 0);
GO

-- 4.6 Donaciones Iniciales (Olla 1)
INSERT INTO dbo.donaciones (id_olla, id_donante, tipo_donacion, monto_soles, comprobante, descripcion) VALUES
(1, 1, 'ESPECIE', NULL, 'GUIA-001', N'Donación semanal de arroz, lentejas y papas'),
(1, 2, 'MONETARIA', 250.00, 'YAPE-88412', N'Aporte solidario para compra de gas y frescos'),
(1, 3, 'ESPECIE', NULL, 'BOL-0045', N'Cajas de aceite vegetal, leche y conservas');
GO

-- 4.7 Lotes Iniciales en Olla 1 (Incluye Vigentes, Por Vencer <= 7 días y 1 Vencido para probar descarte)
DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

INSERT INTO dbo.lotes_inventario (
    codigo_lote, id_olla, id_insumo, id_donacion,
    cantidad_inicial, cantidad_disponible, fecha_vencimiento, estado
) VALUES
('LT-00001', 1, 1, 1, 30.00, 24.00, DATEADD(DAY, 120, @hoy), 'ACTIVO'), -- Arroz (Vigente)
('LT-00002', 1, 2, 1, 15.00, 12.00, DATEADD(DAY, 5, @hoy),   'ACTIVO'), -- Lentejas (Por vencer en 5 días)
('LT-00003', 1, 3, 3, 8.00,  4.00,  DATEADD(DAY, 90, @hoy),  'ACTIVO'), -- Aceite (Stock bajo: 4 < 6)
('LT-00004', 1, 4, 1, 12.00, 10.00, DATEADD(DAY, 3, @hoy),   'ACTIVO'), -- Pollo (Por vencer en 3 días)
('LT-00005', 1, 5, 1, 25.00, 20.00, NULL,                    'ACTIVO'), -- Papa Blanca (Sin vencimiento fijo)
('LT-00006', 1, 6, 3, 24.00, 18.00, DATEADD(DAY, 150, @hoy), 'ACTIVO'), -- Leche (Vigente)
('LT-00007', 1, 8, 3, 12.00, 6.00,  DATEADD(DAY, -2, @hoy),  'ACTIVO'); -- Atún (Vencido hace 2 días para probar sp_DescartarLote)
GO

-- 4.8 Movimientos Correlativos Iniciales (Olla 1)
INSERT INTO dbo.movimientos_inventario (
    codigo_correlativo, id_lote, id_usuario,
    tipo_movimiento, cantidad, saldo_anterior, saldo_posterior, motivo
) VALUES
('E-00001', 1, 2, 'ENTRADA', 30.00, 0.00, 30.00, N'Ingreso por donación Mercado Bayóvar'),
('S-00001', 1, 2, 'SALIDA',   6.00, 30.00, 24.00, N'Almuerzo comunitario del día'),
('E-00002', 2, 2, 'ENTRADA', 15.00, 0.00, 15.00, N'Ingreso por donación Mercado Bayóvar'),
('S-00002', 2, 2, 'SALIDA',   3.00, 15.00, 12.00, N'Menestra para almuerzo'),
('E-00003', 3, 2, 'ENTRADA',  8.00, 0.00,  8.00, N'Ingreso por donación Distribuidora Alimentos'),
('S-00003', 3, 2, 'SALIDA',   4.00,  8.00,  4.00, N'Consumo semanal de cocina'),
('E-00004', 4, 2, 'ENTRADA', 12.00, 0.00, 12.00, N'Ingreso de pollo fresco'),
('S-00004', 4, 2, 'SALIDA',   2.00, 12.00, 10.00, N'Preparación de segundo');
GO

-- 4.9 Recetas Comunitarias Base (50 raciones)
INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa) VALUES
(N'Guiso de Lentejas con Pollo y Arroz', N'Menestra rica en hierro acompañada de arroz graneado y presa de pollo.', 50, 1),
(N'Arroz con Pollo Comunitario', N'Plato tradicional rendidor con pollo y papa sancochada.', 50, 1),
(N'Saltado de Atún con Papa y Arroz', N'Preparación rápida y proteica con conserva de atún y papa.', 50, 1);
GO

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
(3, 3, 0.70); -- 0.7 L Aceite
GO

SET NOCOUNT ON;

INSERT INTO dbo.insumos (nombre, categoria, unidad_base, requiere_vencimiento, stock_minimo)
SELECT v.nombre, v.categoria, v.unidad_base, v.requiere_vencimiento, v.stock_minimo
FROM (VALUES
    (N'Azúcar Rubia', N'Abarrotes', 'kg', 1, 5.00),
    (N'Sal de Cocina', N'Aceites y Condimentos', 'kg', 0, 2.00),
    (N'Ajo', N'Aceites y Condimentos', 'kg', 0, 0.50),
    (N'Harina de Trigo', N'Granos y Cereales', 'kg', 1, 5.00),
    (N'Avena en Hojuelas', N'Granos y Cereales', 'kg', 1, 5.00),
    (N'Quinua', N'Granos y Cereales', 'kg', 1, 5.00),
    (N'Frejol Canario', N'Menestras', 'kg', 1, 8.00),
    (N'Cebolla Roja', N'Tubérculos y Verduras', 'kg', 0, 5.00),
    (N'Zanahoria', N'Tubérculos y Verduras', 'kg', 0, 4.00),
    (N'Pescado Bonito', N'Proteínas', 'kg', 1, 5.00),
    (N'Huevos', N'Proteínas', 'unidades', 1, 60.00),
    (N'Leche Fresca', N'Lácteos', 'L', 1, 10.00)
) AS v(nombre, categoria, unidad_base, requiere_vencimiento, stock_minimo)
WHERE NOT EXISTS (SELECT 1 FROM dbo.insumos i WHERE i.nombre = v.nombre);
GO
-- ============================================================================
-- AYNI · 002 · Regiones del Perú y recetas adicionales (SQL Server)
-- Ejecutar en SSMS DESPUÉS de database/AyniOllasDB.SQL.
-- Es INCREMENTAL e IDEMPOTENTE: no borra nada y se puede ejecutar varias veces
-- (solo inserta lo que falta). Los id_ubigeo existentes no cambian.
-- 162 ubigeos: 24 departamentos + Callao; foco en Junín (Huancayo con
-- sus 28 distritos) y Lima (43 distritos de Lima Metropolitana).
-- ============================================================================


SET NOCOUNT ON;

-- 1) Ubigeos ------------------------------------------------------------------
INSERT INTO dbo.ubigeos (departamento, provincia, distrito)
SELECT v.departamento, v.provincia, v.distrito
FROM (VALUES
    (N'Junín', N'Huancayo', N'Huancayo'),
    (N'Junín', N'Huancayo', N'El Tambo'),
    (N'Junín', N'Huancayo', N'Chilca'),
    (N'Junín', N'Huancayo', N'Carhuacallanga'),
    (N'Junín', N'Huancayo', N'Chacapampa'),
    (N'Junín', N'Huancayo', N'Chicche'),
    (N'Junín', N'Huancayo', N'Chongos Alto'),
    (N'Junín', N'Huancayo', N'Chupuro'),
    (N'Junín', N'Huancayo', N'Colca'),
    (N'Junín', N'Huancayo', N'Cullhuas'),
    (N'Junín', N'Huancayo', N'Huacrapuquio'),
    (N'Junín', N'Huancayo', N'Hualhuas'),
    (N'Junín', N'Huancayo', N'Huancán'),
    (N'Junín', N'Huancayo', N'Huasicancha'),
    (N'Junín', N'Huancayo', N'Huayucachi'),
    (N'Junín', N'Huancayo', N'Ingenio'),
    (N'Junín', N'Huancayo', N'Pariahuanca'),
    (N'Junín', N'Huancayo', N'Pilcomayo'),
    (N'Junín', N'Huancayo', N'Pucará'),
    (N'Junín', N'Huancayo', N'Quichuay'),
    (N'Junín', N'Huancayo', N'Quilcas'),
    (N'Junín', N'Huancayo', N'San Agustín'),
    (N'Junín', N'Huancayo', N'San Jerónimo de Tunán'),
    (N'Junín', N'Huancayo', N'Saño'),
    (N'Junín', N'Huancayo', N'Sapallanga'),
    (N'Junín', N'Huancayo', N'Sicaya'),
    (N'Junín', N'Huancayo', N'Santo Domingo de Acobamba'),
    (N'Junín', N'Huancayo', N'Viques'),
    (N'Junín', N'Concepción', N'Concepción'),
    (N'Junín', N'Chupaca', N'Chupaca'),
    (N'Junín', N'Jauja', N'Jauja'),
    (N'Junín', N'Tarma', N'Tarma'),
    (N'Junín', N'Yauli', N'La Oroya'),
    (N'Junín', N'Chanchamayo', N'Chanchamayo'),
    (N'Junín', N'Chanchamayo', N'Perené'),
    (N'Junín', N'Satipo', N'Satipo'),
    (N'Junín', N'Junín', N'Junín'),
    (N'Lima', N'Lima', N'Lima'),
    (N'Lima', N'Lima', N'Ancón'),
    (N'Lima', N'Lima', N'Ate'),
    (N'Lima', N'Lima', N'Barranco'),
    (N'Lima', N'Lima', N'Breña'),
    (N'Lima', N'Lima', N'Carabayllo'),
    (N'Lima', N'Lima', N'Chaclacayo'),
    (N'Lima', N'Lima', N'Chorrillos'),
    (N'Lima', N'Lima', N'Cieneguilla'),
    (N'Lima', N'Lima', N'Comas'),
    (N'Lima', N'Lima', N'El Agustino'),
    (N'Lima', N'Lima', N'Independencia'),
    (N'Lima', N'Lima', N'Jesús María'),
    (N'Lima', N'Lima', N'La Molina'),
    (N'Lima', N'Lima', N'La Victoria'),
    (N'Lima', N'Lima', N'Lince'),
    (N'Lima', N'Lima', N'Los Olivos'),
    (N'Lima', N'Lima', N'Lurigancho'),
    (N'Lima', N'Lima', N'Lurín'),
    (N'Lima', N'Lima', N'Magdalena del Mar'),
    (N'Lima', N'Lima', N'Miraflores'),
    (N'Lima', N'Lima', N'Pachacámac'),
    (N'Lima', N'Lima', N'Pucusana'),
    (N'Lima', N'Lima', N'Pueblo Libre'),
    (N'Lima', N'Lima', N'Puente Piedra'),
    (N'Lima', N'Lima', N'Punta Hermosa'),
    (N'Lima', N'Lima', N'Punta Negra'),
    (N'Lima', N'Lima', N'Rímac'),
    (N'Lima', N'Lima', N'San Bartolo'),
    (N'Lima', N'Lima', N'San Borja'),
    (N'Lima', N'Lima', N'San Isidro'),
    (N'Lima', N'Lima', N'San Juan de Lurigancho'),
    (N'Lima', N'Lima', N'San Juan de Miraflores'),
    (N'Lima', N'Lima', N'San Luis'),
    (N'Lima', N'Lima', N'San Martín de Porres'),
    (N'Lima', N'Lima', N'San Miguel'),
    (N'Lima', N'Lima', N'Santa Anita'),
    (N'Lima', N'Lima', N'Santa María del Mar'),
    (N'Lima', N'Lima', N'Santa Rosa'),
    (N'Lima', N'Lima', N'Santiago de Surco'),
    (N'Lima', N'Lima', N'Surquillo'),
    (N'Lima', N'Lima', N'Villa El Salvador'),
    (N'Lima', N'Lima', N'Villa María del Triunfo'),
    (N'Lima', N'Barranca', N'Barranca'),
    (N'Lima', N'Cañete', N'San Vicente de Cañete'),
    (N'Lima', N'Huaral', N'Huaral'),
    (N'Lima', N'Huaura', N'Huacho'),
    (N'Lima', N'Huarochirí', N'Matucana'),
    (N'Callao', N'Callao', N'Callao'),
    (N'Callao', N'Callao', N'Bellavista'),
    (N'Callao', N'Callao', N'Carmen de la Legua Reynoso'),
    (N'Callao', N'Callao', N'La Perla'),
    (N'Callao', N'Callao', N'La Punta'),
    (N'Callao', N'Callao', N'Ventanilla'),
    (N'Callao', N'Callao', N'Mi Perú'),
    (N'Amazonas', N'Chachapoyas', N'Chachapoyas'),
    (N'Amazonas', N'Bagua', N'Bagua'),
    (N'Áncash', N'Huaraz', N'Huaraz'),
    (N'Áncash', N'Huaraz', N'Independencia'),
    (N'Áncash', N'Santa', N'Chimbote'),
    (N'Áncash', N'Santa', N'Nuevo Chimbote'),
    (N'Apurímac', N'Abancay', N'Abancay'),
    (N'Apurímac', N'Andahuaylas', N'Andahuaylas'),
    (N'Arequipa', N'Arequipa', N'Arequipa'),
    (N'Arequipa', N'Arequipa', N'Cerro Colorado'),
    (N'Arequipa', N'Arequipa', N'Paucarpata'),
    (N'Arequipa', N'Arequipa', N'Cayma'),
    (N'Arequipa', N'Arequipa', N'José Luis Bustamante y Rivero'),
    (N'Arequipa', N'Islay', N'Mollendo'),
    (N'Ayacucho', N'Huamanga', N'Ayacucho'),
    (N'Ayacucho', N'Huamanga', N'San Juan Bautista'),
    (N'Ayacucho', N'Huamanga', N'Carmen Alto'),
    (N'Ayacucho', N'Huanta', N'Huanta'),
    (N'Cajamarca', N'Cajamarca', N'Cajamarca'),
    (N'Cajamarca', N'Cajamarca', N'Baños del Inca'),
    (N'Cajamarca', N'Jaén', N'Jaén'),
    (N'Cusco', N'Cusco', N'Cusco'),
    (N'Cusco', N'Cusco', N'Santiago'),
    (N'Cusco', N'Cusco', N'Wanchaq'),
    (N'Cusco', N'Cusco', N'San Sebastián'),
    (N'Cusco', N'Cusco', N'San Jerónimo'),
    (N'Cusco', N'La Convención', N'Santa Ana'),
    (N'Huancavelica', N'Huancavelica', N'Huancavelica'),
    (N'Huánuco', N'Huánuco', N'Huánuco'),
    (N'Huánuco', N'Huánuco', N'Amarilis'),
    (N'Huánuco', N'Huánuco', N'Pillco Marca'),
    (N'Huánuco', N'Leoncio Prado', N'Rupa-Rupa'),
    (N'Ica', N'Ica', N'Ica'),
    (N'Ica', N'Ica', N'Parcona'),
    (N'Ica', N'Chincha', N'Chincha Alta'),
    (N'Ica', N'Pisco', N'Pisco'),
    (N'La Libertad', N'Trujillo', N'Trujillo'),
    (N'La Libertad', N'Trujillo', N'La Esperanza'),
    (N'La Libertad', N'Trujillo', N'El Porvenir'),
    (N'La Libertad', N'Trujillo', N'Víctor Larco Herrera'),
    (N'Lambayeque', N'Chiclayo', N'Chiclayo'),
    (N'Lambayeque', N'Chiclayo', N'José Leonardo Ortiz'),
    (N'Lambayeque', N'Chiclayo', N'La Victoria'),
    (N'Lambayeque', N'Lambayeque', N'Lambayeque'),
    (N'Loreto', N'Maynas', N'Iquitos'),
    (N'Loreto', N'Maynas', N'Punchana'),
    (N'Loreto', N'Maynas', N'Belén'),
    (N'Loreto', N'Maynas', N'San Juan Bautista'),
    (N'Madre de Dios', N'Tambopata', N'Tambopata'),
    (N'Moquegua', N'Mariscal Nieto', N'Moquegua'),
    (N'Moquegua', N'Ilo', N'Ilo'),
    (N'Pasco', N'Pasco', N'Chaupimarca'),
    (N'Pasco', N'Pasco', N'Yanacancha'),
    (N'Piura', N'Piura', N'Piura'),
    (N'Piura', N'Piura', N'Castilla'),
    (N'Piura', N'Piura', N'Veintiséis de Octubre'),
    (N'Piura', N'Sullana', N'Sullana'),
    (N'Puno', N'Puno', N'Puno'),
    (N'Puno', N'San Román', N'Juliaca'),
    (N'San Martín', N'Moyobamba', N'Moyobamba'),
    (N'San Martín', N'San Martín', N'Tarapoto'),
    (N'San Martín', N'San Martín', N'Morales'),
    (N'Tacna', N'Tacna', N'Tacna'),
    (N'Tacna', N'Tacna', N'Alto de la Alianza'),
    (N'Tacna', N'Tacna', N'Ciudad Nueva'),
    (N'Tacna', N'Tacna', N'Gregorio Albarracín Lanchipa'),
    (N'Tumbes', N'Tumbes', N'Tumbes'),
    (N'Ucayali', N'Coronel Portillo', N'Callería'),
    (N'Ucayali', N'Coronel Portillo', N'Yarinacocha'),
    (N'Ucayali', N'Coronel Portillo', N'Manantay')
) AS v(departamento, provincia, distrito)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.ubigeos u
    WHERE u.departamento = v.departamento AND u.provincia = v.provincia AND u.distrito = v.distrito
);
GO

-- 2) Recetas (50 raciones base) -------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.recetas WHERE nombre = N'Tallarines con Pollo')
    INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa)
    VALUES (N'Tallarines con Pollo', N'Fideos guisados con presa de pollo, rendidores y del gusto de los niños.', 50, 1);

INSERT INTO dbo.receta_ingredientes (id_receta, id_insumo, cantidad_base)
SELECT r.id_receta, i.id_insumo, v.cantidad
FROM (VALUES
    (N'Fideo Tallarín', 5.00),
    (N'Filete de Pollo', 6.50),
    (N'Aceite Vegetal', 0.70),
    (N'Papa Blanca', 3.00)
) AS v(insumo, cantidad)
JOIN dbo.insumos i ON i.nombre = v.insumo
JOIN dbo.recetas r ON r.nombre = N'Tallarines con Pollo'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.receta_ingredientes ri WHERE ri.id_receta = r.id_receta AND ri.id_insumo = i.id_insumo
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.recetas WHERE nombre = N'Sopa de Fideos con Pollo')
    INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa)
    VALUES (N'Sopa de Fideos con Pollo', N'Sopa caliente y nutritiva, ideal para los días fríos de la sierra.', 50, 1);

INSERT INTO dbo.receta_ingredientes (id_receta, id_insumo, cantidad_base)
SELECT r.id_receta, i.id_insumo, v.cantidad
FROM (VALUES
    (N'Fideo Tallarín', 3.00),
    (N'Filete de Pollo', 4.00),
    (N'Papa Blanca', 5.00),
    (N'Aceite Vegetal', 0.30)
) AS v(insumo, cantidad)
JOIN dbo.insumos i ON i.nombre = v.insumo
JOIN dbo.recetas r ON r.nombre = N'Sopa de Fideos con Pollo'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.receta_ingredientes ri WHERE ri.id_receta = r.id_receta AND ri.id_insumo = i.id_insumo
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.recetas WHERE nombre = N'Tacu Tacu de Lentejas')
    INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa)
    VALUES (N'Tacu Tacu de Lentejas', N'Clásico criollo que aprovecha arroz y menestra; alto en hierro.', 50, 1);

INSERT INTO dbo.receta_ingredientes (id_receta, id_insumo, cantidad_base)
SELECT r.id_receta, i.id_insumo, v.cantidad
FROM (VALUES
    (N'Lenteja Serrana', 4.00),
    (N'Arroz Superior', 5.00),
    (N'Aceite Vegetal', 1.00)
) AS v(insumo, cantidad)
JOIN dbo.insumos i ON i.nombre = v.insumo
JOIN dbo.recetas r ON r.nombre = N'Tacu Tacu de Lentejas'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.receta_ingredientes ri WHERE ri.id_receta = r.id_receta AND ri.id_insumo = i.id_insumo
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.recetas WHERE nombre = N'Ají de Atún con Papa y Arroz')
    INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa)
    VALUES (N'Ají de Atún con Papa y Arroz', N'Versión económica del ají de gallina con conserva de atún.', 50, 1);

INSERT INTO dbo.receta_ingredientes (id_receta, id_insumo, cantidad_base)
SELECT r.id_receta, i.id_insumo, v.cantidad
FROM (VALUES
    (N'Conserva de Atún', 25.00),
    (N'Papa Blanca', 5.00),
    (N'Arroz Superior', 5.00),
    (N'Leche Evaporada', 6.00),
    (N'Aceite Vegetal', 0.60)
) AS v(insumo, cantidad)
JOIN dbo.insumos i ON i.nombre = v.insumo
JOIN dbo.recetas r ON r.nombre = N'Ají de Atún con Papa y Arroz'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.receta_ingredientes ri WHERE ri.id_receta = r.id_receta AND ri.id_insumo = i.id_insumo
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.recetas WHERE nombre = N'Arroz con Leche')
    INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa)
    VALUES (N'Arroz con Leche', N'Postre tradicional para acompañar el almuerzo comunitario.', 50, 1);

INSERT INTO dbo.receta_ingredientes (id_receta, id_insumo, cantidad_base)
SELECT r.id_receta, i.id_insumo, v.cantidad
FROM (VALUES
    (N'Arroz Superior', 2.50),
    (N'Leche Evaporada', 12.00)
) AS v(insumo, cantidad)
JOIN dbo.insumos i ON i.nombre = v.insumo
JOIN dbo.recetas r ON r.nombre = N'Arroz con Leche'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.receta_ingredientes ri WHERE ri.id_receta = r.id_receta AND ri.id_insumo = i.id_insumo
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.recetas WHERE nombre = N'Lentejas con Arroz y Papa')
    INSERT INTO dbo.recetas (nombre, descripcion, raciones_base, activa)
    VALUES (N'Lentejas con Arroz y Papa', N'Menestra sencilla con papa sancochada y arroz graneado.', 50, 1);

INSERT INTO dbo.receta_ingredientes (id_receta, id_insumo, cantidad_base)
SELECT r.id_receta, i.id_insumo, v.cantidad
FROM (VALUES
    (N'Lenteja Serrana', 4.50),
    (N'Arroz Superior', 5.00),
    (N'Papa Blanca', 4.00),
    (N'Aceite Vegetal', 0.50)
) AS v(insumo, cantidad)
JOIN dbo.insumos i ON i.nombre = v.insumo
JOIN dbo.recetas r ON r.nombre = N'Lentejas con Arroz y Papa'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.receta_ingredientes ri WHERE ri.id_receta = r.id_receta AND ri.id_insumo = i.id_insumo
);
GO

-- Verificación
SELECT departamento, COUNT(*) AS distritos FROM dbo.ubigeos GROUP BY departamento ORDER BY departamento;
SELECT COUNT(*) AS recetas_activas FROM dbo.recetas WHERE activa = 1;
GO


-- Verificación
SELECT nombre, categoria, unidad_base, stock_minimo FROM dbo.insumos ORDER BY categoria, nombre;
GO


-- Verificación final
SELECT
    (SELECT COUNT(*) FROM dbo.ubigeos) AS ubigeos,
    (SELECT COUNT(*) FROM dbo.ollas) AS ollas,
    (SELECT COUNT(*) FROM dbo.usuarios) AS usuarios,
    (SELECT COUNT(*) FROM dbo.insumos) AS insumos,
    (SELECT COUNT(*) FROM dbo.lotes_inventario) AS lotes,
    (SELECT COUNT(*) FROM dbo.recetas) AS recetas;
GO
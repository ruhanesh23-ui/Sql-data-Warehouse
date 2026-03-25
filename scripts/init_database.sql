-- ============================================================
-- Script  : Create DataWarehouse Database with Layered Schemas
-- Purpose : Sets up a fresh DataWarehouse database using a
--           medallion architecture (Bronze → Silver → Gold).
--           If the database already exists, it is safely
--           dropped and recreated from scratch.
-- ============================================================


-- ============================================================
-- STEP 1: Drop the existing DataWarehouse database (if any)
-- ============================================================
-- Before creating, we check whether a database named
-- 'DataWarehouse' already exists in sys.databases (the system
-- catalog view that lists all databases on the server).
-- If it does, we force all active connections to disconnect
-- (SINGLE_USER mode + ROLLBACK IMMEDIATE) before dropping it,
-- preventing the DROP from being blocked by open sessions.

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouse')
BEGIN
    -- Switch to single-user mode to kick out any active connections.
    -- ROLLBACK IMMEDIATE rolls back any open transactions immediately,
    -- ensuring no pending work blocks the DROP.
    ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

    -- Now safe to drop the database entirely.
    DROP DATABASE DataWarehouse;
END;
GO
-- GO is a batch separator. The IF/ALTER/DROP must complete as one
-- batch before the CREATE DATABASE runs in the next batch.


-- ============================================================
-- STEP 2: Create the DataWarehouse database
-- ============================================================
-- Creates a new, empty database with default settings.
-- All subsequent objects will be created inside this database.

CREATE DATABASE DataWarehouse;
GO


-- ============================================================
-- STEP 3: Switch context to the new database
-- ============================================================
-- All schema creation statements below must execute inside
-- DataWarehouse, not in the previous default database (master).

USE DataWarehouse;
GO


-- ============================================================
-- STEP 4: Create the Bronze schema  (raw / landing layer)
-- ============================================================
-- The Bronze schema stores raw, unprocessed data ingested
-- directly from source systems. No transformations are applied
-- at this layer — data is kept as-is for traceability and
-- reprocessing purposes.

CREATE SCHEMA bronze;
GO


-- ============================================================
-- STEP 5: Create the Silver schema  (cleansed / conformed layer)
-- ============================================================
-- The Silver schema holds data that has been cleansed,
-- deduplicated, and lightly transformed from the Bronze layer.
-- It serves as the single source of truth for downstream use.

CREATE SCHEMA silver;
GO


-- ============================================================
-- STEP 6: Create the Gold schema  (aggregated / business layer)
-- ============================================================
-- The Gold schema contains business-ready data: aggregated
-- fact tables, dimension tables, and reporting views built
-- on top of the Silver layer. This is what BI tools and
-- analysts typically query.

CREATE SCHEMA gold;
GO

-- ============================================================
-- Procedure : bronze.load_bronze
-- Schema    : bronze (raw / landing layer)
-- Purpose   : Loads all Bronze layer tables by truncating each
--             table and bulk inserting raw CSV data from the
--             source CRM and ERP systems.
--             No transformations are applied — data is landed
--             as-is for traceability and reprocessing.
-- Usage     : EXEC bronze.load_bronze;
-- ============================================================

CREATE OR ALTER PROCEDURE bronze.load_bronze
AS
BEGIN
    -- Suppress "rows affected" messages from appearing in the
    -- output — keeps the PRINT log clean and readable.
    SET NOCOUNT ON;

    -- --------------------------------------------------------
    -- Timing Variables
    -- @start_time       : Captures start of each individual table load
    -- @end_time         : Captures end of each individual table load
    -- @batch_start_time : Captures start of the entire Bronze load batch
    -- @batch_end_time   : Captures end of the entire Bronze load batch
    -- --------------------------------------------------------
    DECLARE 
        @start_time        DATETIME,
        @end_time          DATETIME,
        @batch_start_time  DATETIME,
        @batch_end_time    DATETIME;

    -- --------------------------------------------------------
    -- TRY block: All load logic runs here.
    -- If any statement fails, execution jumps to CATCH.
    -- --------------------------------------------------------
    BEGIN TRY

        -- Record the start time of the entire batch
        SET @batch_start_time = GETDATE();

        PRINT '=====================================';
        PRINT 'Loading Bronze Layer';
        PRINT '=====================================';


        -- ====================================================
        -- CRM TABLES
        -- Source : CRM System
        -- Files  : source_crm folder
        -- ====================================================
        PRINT '--- Loading CRM Tables ---';


        -- ----------------------------------------------------
        -- Table : bronze.crm_cust_info
        -- Source: source_crm/cust_info.csv
        -- Desc  : Raw customer master data — names, gender,
        --         marital status, and account creation date.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: bronze.crm_cust_info';
        -- Remove all existing rows before reloading.
        -- TRUNCATE is faster than DELETE as it does not log
        -- individual row deletions.
        TRUNCATE TABLE bronze.crm_cust_info;

        PRINT '>> Inserting: bronze.crm_cust_info';
        -- Bulk insert raw CSV data directly into the table.
        -- FIRSTROW = 2    : Skip the header row in the CSV.
        -- FIELDTERMINATOR : Columns are comma-separated.
        -- TABLOCK         : Acquire a table-level lock for
        --                   faster bulk load performance.
        BULK INSERT bronze.crm_cust_info
        FROM 'G:\My Drive\SQL\sql-data-warehouse-project\datasets\source_crm\cust_info.csv'
        WITH (
            FIRSTROW        = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();
        -- Log how long this individual table load took in seconds
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : bronze.crm_prd_info
        -- Source: source_crm/prd_info.csv
        -- Desc  : Raw product master data — product keys,
        --         names, costs, lines, and date ranges.
        --         All columns are NVARCHAR to handle NULL and
        --         misformatted date values in the source CSV.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: bronze.crm_prd_info';
        TRUNCATE TABLE bronze.crm_prd_info;

        PRINT '>> Inserting: bronze.crm_prd_info';
        BULK INSERT bronze.crm_prd_info
        FROM 'G:\My Drive\SQL\sql-data-warehouse-project\datasets\source_crm\prd_info.csv'
        WITH (
            FIRSTROW        = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : bronze.crm_sales_details
        -- Source: source_crm/sales_details.csv
        -- Desc  : Raw sales transaction data — order numbers,
        --         product keys, customer IDs, dates (stored as
        --         INT e.g. 20260325), quantities, and prices.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: bronze.crm_sales_details';
        TRUNCATE TABLE bronze.crm_sales_details;

        PRINT '>> Inserting: bronze.crm_sales_details';
        BULK INSERT bronze.crm_sales_details
        FROM 'G:\My Drive\SQL\sql-data-warehouse-project\datasets\source_crm\sales_details.csv'
        WITH (
            FIRSTROW        = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ====================================================
        -- ERP TABLES
        -- Source : ERP System
        -- Files  : source_erp folder
        -- Note   : Column names kept as-is from source.
        --          Renamed to standard conventions in Silver.
        -- ====================================================
        PRINT '--- Loading ERP Tables ---';


        -- ----------------------------------------------------
        -- Table : bronze.erp_CUST_AZ12
        -- Source: source_erp/CUST_AZ12.csv
        -- Desc  : Raw customer demographic data from ERP.
        --         Contains customer birth dates and gender codes.
        --         Joined to CRM customer data in Silver via CID.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: bronze.erp_CUST_AZ12';
        TRUNCATE TABLE bronze.erp_CUST_AZ12;

        PRINT '>> Inserting: bronze.erp_CUST_AZ12';
        BULK INSERT bronze.erp_CUST_AZ12
        FROM 'G:\My Drive\SQL\sql-data-warehouse-project\datasets\source_erp\CUST_AZ12.csv'
        WITH (
            FIRSTROW        = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : bronze.erp_LOC_A101
        -- Source: source_erp/LOC_A101.csv
        -- Desc  : Raw customer location data from ERP.
        --         Contains country codes/names per customer.
        --         Used to enrich customer records in Silver.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: bronze.erp_LOC_A101';
        TRUNCATE TABLE bronze.erp_LOC_A101;

        PRINT '>> Inserting: bronze.erp_LOC_A101';
        BULK INSERT bronze.erp_LOC_A101
        FROM 'G:\My Drive\SQL\sql-data-warehouse-project\datasets\source_erp\LOC_A101.csv'
        WITH (
            FIRSTROW        = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : bronze.erp_PX_CAT_G1V2
        -- Source: source_erp/PX_CAT_G1V2.csv
        -- Desc  : Raw product category and subcategory data
        --         from ERP. Used to enrich product records
        --         with category hierarchy in Silver.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: bronze.erp_PX_CAT_G1V2';
        TRUNCATE TABLE bronze.erp_PX_CAT_G1V2;

        PRINT '>> Inserting: bronze.erp_PX_CAT_G1V2';
        BULK INSERT bronze.erp_PX_CAT_G1V2
        FROM 'G:\My Drive\SQL\sql-data-warehouse-project\datasets\source_erp\PX_CAT_G1V2.csv'
        WITH (
            FIRSTROW        = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


    END TRY

    -- --------------------------------------------------------
    -- CATCH block: Catches any error thrown inside the TRY block.
    -- Prints a structured error summary to help diagnose which
    -- table failed and why, without crashing the entire session.
    -- --------------------------------------------------------
    BEGIN CATCH
        PRINT '=====================================';
        PRINT 'ERROR: Bronze Load Failed';
        PRINT 'Message: ' + ERROR_MESSAGE();  -- Human-readable error description
        PRINT 'Number : ' + CAST(ERROR_NUMBER()  AS NVARCHAR);  -- SQL Server error code
        PRINT 'State  : ' + CAST(ERROR_STATE()   AS NVARCHAR);  -- Error state for diagnostics
        PRINT '=====================================';
    END CATCH;

    -- --------------------------------------------------------
    -- Log the total elapsed time for the entire Bronze batch.
    -- Useful for monitoring load performance over time.
    -- --------------------------------------------------------
    SET @batch_end_time = GETDATE();

    PRINT '=====================================';
    PRINT 'Total Batch Duration: '
          + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR)
          + ' sec';
    PRINT '=====================================';

END;

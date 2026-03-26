-- ============================================================
-- Procedure : silver.load_silver
-- Schema    : silver (cleansed / conformed layer)
-- Purpose   : Loads all Silver layer tables by truncating each
--             table and inserting cleansed, transformed data
--             from the Bronze layer.
--             Transformations applied at this layer include:
--               - Deduplication via ROW_NUMBER()
--               - Trimming of whitespace from string columns
--               - Normalisation of coded values (gender, etc.)
--               - Date casting and validation
--               - Derivation of missing/invalid numeric values
-- Usage     : EXEC silver.load_silver;
-- ============================================================

CREATE OR ALTER PROCEDURE silver.load_silver
AS
BEGIN
    -- Suppress "rows affected" messages from appearing in the
    -- output — keeps the PRINT log clean and readable.
    SET NOCOUNT ON;

    -- --------------------------------------------------------
    -- Timing Variables
    -- @start_time       : Captures start of each individual table load
    -- @end_time         : Captures end of each individual table load
    -- @batch_start_time : Captures start of the entire Silver load batch
    -- @batch_end_time   : Captures end of the entire Silver load batch
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
        PRINT 'Loading Silver Layer';
        PRINT '=====================================';


        -- ====================================================
        -- CRM TABLES
        -- Source : bronze (CRM tables)
        -- ====================================================
        PRINT '--- Loading CRM Tables ---';


        -- ----------------------------------------------------
        -- Table : silver.crm_cust_info
        -- Source: bronze.crm_cust_info
        -- Desc  : Deduplicated and cleansed customer master
        --         data. Whitespace trimmed, gender and marital
        --         status codes decoded to readable labels.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: silver.crm_cust_info';
        -- Remove all existing rows before reloading.
        -- TRUNCATE is faster than DELETE as it does not log
        -- individual row deletions.
        TRUNCATE TABLE silver.crm_cust_info;

        PRINT '>> Inserting: silver.crm_cust_info';
        INSERT INTO silver.crm_cust_info (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        SELECT
            cst_id,
            cst_key,

            -- Remove leading/trailing whitespace from first name
            TRIM(cst_firstname) AS cst_firstname,

            -- Remove leading/trailing whitespace from last name
            TRIM(cst_lastname)  AS cst_lastname,

            -- Decode marital status code into a readable label.
            -- UPPER + TRIM ensures codes like ' m', 'M', 'M ' all match.
            CASE 
                WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
                WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
                ELSE 'n/a'  -- Catch NULLs, empty strings, or unknown codes
            END AS cst_marital_status,

            -- Decode gender code into a readable label.
            -- UPPER + TRIM ensures codes like ' f', 'F', 'F ' all match.
            CASE 
                WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
                WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
                ELSE 'n/a'  -- Catch NULLs, empty strings, or unknown codes
            END AS cst_gndr,

            cst_create_date

        FROM (
            -- Subquery: assign row numbers to detect duplicates.
            -- The most recent record per cst_id gets flag_last = 1.
            SELECT *,
                ROW_NUMBER() OVER (
                    PARTITION BY cst_id           -- One group per customer
                    ORDER BY cst_create_date DESC  -- Latest record ranked first
                ) AS flag_last
            FROM bronze.crm_cust_info
        ) t
        WHERE flag_last = 1; -- Only insert the most recent record per customer

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : silver.crm_prd_info
        -- Source: bronze.crm_prd_info
        -- Desc  : Cleansed product master data. Category ID
        --         extracted from product key, costs defaulted
        --         to 0 where NULL, product line codes decoded,
        --         and end dates derived via LEAD().
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: silver.crm_prd_info';
        TRUNCATE TABLE silver.crm_prd_info;

        PRINT '>> Inserting: silver.crm_prd_info';
        INSERT INTO silver.crm_prd_info (
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        SELECT
            prd_id,

            -- Extract the category ID from the first 5 characters of prd_key.
            -- Replace '-' with '_' so the format matches the ERP category ID
            -- (e.g. 'AC-HE' becomes 'AC_HE' to join with erp_PX_CAT_G1V2).
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,

            -- Extract the product key by stripping the category prefix.
            -- Characters from position 7 onward give the clean product key
            -- (e.g. 'AC-HE-HL-U509' becomes 'HL-U509').
            SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,

            prd_nm,

            -- Replace NULL costs with 0 to avoid downstream calculation errors.
            -- A NULL price would cause SUM/AVG aggregations to silently drop rows.
            ISNULL(prd_cost, 0) AS prd_cost,

            -- Decode single-letter product line codes into readable labels.
            -- UPPER + TRIM ensures codes with extra spaces or mixed casing match.
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'n/a'  -- Catch NULLs, empty strings, or unknown codes
            END AS prd_line,

            -- Cast the raw NVARCHAR start date to a proper DATE type.
            CAST(prd_start_dt AS DATE) AS prd_start_dt,

            -- Derive the end date as 1 day before the next product version's
            -- start date using LEAD(). Prevents overlapping date ranges between
            -- consecutive product versions.
            -- NULL result means this is the current/active product record.
            DATEADD(DAY, -1,
                LEAD(CONVERT(DATE, prd_start_dt)) OVER (
                    PARTITION BY prd_key                  -- Group by product key
                    ORDER BY CONVERT(DATE, prd_start_dt)  -- Order versions chronologically
                )
            ) AS prd_end_dt

        FROM bronze.crm_prd_info;

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : silver.crm_sales_details
        -- Source: bronze.crm_sales_details
        -- Desc  : Cleansed sales transactions. Integer dates
        --         converted to DATE with invalid values set to
        --         NULL. Sales and price derived where missing
        --         or inconsistent with quantity.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: silver.crm_sales_details';
        TRUNCATE TABLE silver.crm_sales_details;

        PRINT '>> Inserting: silver.crm_sales_details';
        INSERT INTO silver.crm_sales_details (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT
            sls_ord_num,  -- Sales order number — no transformation needed
            sls_prd_key,  -- Product key — no transformation needed
            sls_cust_id,  -- Customer ID — no transformation needed

            -- Date Conversion: Integer → DATE
            -- Dates stored as 8-digit integers (e.g. 20260325).
            -- Two-step cast: INT → VARCHAR → DATE.
            -- Value = 0 or LEN() != 8 indicates invalid/missing date → NULL.
            CASE 
                WHEN sls_order_dt = 0 
                  OR LEN(sls_order_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
            END AS sls_order_dt,

            CASE 
                WHEN sls_ship_dt = 0 
                  OR LEN(sls_ship_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
            END AS sls_ship_dt,

            CASE 
                WHEN sls_due_dt = 0 
                  OR LEN(sls_due_dt) != 8 THEN NULL
                ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
            END AS sls_due_dt,

            -- Sales Amount Validation:
            -- Recalculate from quantity * ABS(price) when NULL,
            -- zero, negative, or inconsistent with components.
            CASE 
                WHEN sls_sales IS NULL 
                  OR sls_sales <= 0 
                  OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price)  -- Derive from components
                ELSE sls_sales                          -- Trust the source value
            END AS sls_sales,

            sls_quantity, -- Quantity — no transformation needed

            -- Unit Price Validation:
            -- Derive from sales / quantity when NULL or invalid.
            -- NULLIF(sls_quantity, 0) prevents division by zero.
            CASE 
                WHEN sls_price IS NULL 
                  OR sls_price <= 0
                    THEN sls_sales / NULLIF(sls_quantity, 0)  -- Derive from sales/qty
                ELSE sls_price                                 -- Trust the source value
            END AS sls_price

        FROM bronze.crm_sales_details;

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ====================================================
        -- ERP TABLES
        -- Source : bronze (ERP tables)
        -- ====================================================
        PRINT '--- Loading ERP Tables ---';


        -- ----------------------------------------------------
        -- Table : silver.erp_CUST_AZ12
        -- Source: bronze.erp_CUST_AZ12
        -- Desc  : Cleansed ERP customer demographics. 'NAS'
        --         prefix stripped from CID, future birth dates
        --         set to NULL, gender codes normalised.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: silver.erp_CUST_AZ12';
        TRUNCATE TABLE silver.erp_CUST_AZ12;

        PRINT '>> Inserting: silver.erp_CUST_AZ12';
        INSERT INTO silver.erp_CUST_AZ12 (
            cid,
            bdate,
            gen
        )
        SELECT

            -- Strip the 'NAS' prefix where present so ERP customer IDs
            -- align with CRM customer keys for joining in Silver/Gold.
            CASE 
                WHEN cid LIKE 'NAS%' 
                    THEN SUBSTRING(cid, 4, LEN(cid))  -- Remove first 3 'NAS' characters
                ELSE cid                               -- Keep the value unchanged
            END AS cid,

            -- TRY_CAST safely converts NVARCHAR to DATE (returns NULL on failure).
            -- Future birth dates are logically invalid and set to NULL.
            CASE 
                WHEN TRY_CAST(bdate AS DATE) > GETDATE() 
                    THEN NULL                     -- Future date is invalid
                ELSE TRY_CAST(bdate AS DATE)      -- Valid date — cast and keep
            END AS bdate,

            -- Normalise inconsistent gender codes to 'Male', 'Female', or 'n/a'.
            -- Handles full words, single letters, mixed casing, and extra spaces.
            CASE 
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
                ELSE 'n/a'  -- Catch NULLs, empty strings, or unknown codes
            END AS gen

        FROM bronze.erp_CUST_AZ12;

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : silver.erp_LOC_A101
        -- Source: bronze.erp_LOC_A101
        -- Desc  : Cleansed ERP customer location data.
        --         Hyphens removed from CID to align with CRM
        --         format. Country codes decoded to full names.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: silver.erp_LOC_A101';
        TRUNCATE TABLE silver.erp_LOC_A101;

        PRINT '>> Inserting: silver.erp_LOC_A101';
        INSERT INTO silver.erp_LOC_A101 (
            cid,
            cntry
        )
        SELECT
            -- Remove hyphens from CID to match the format used
            -- in CRM and other ERP tables for consistent joining.
            REPLACE(cid, '-', '') AS cid,

            -- Decode country codes into full country names.
            -- Handles abbreviations, empty strings, and NULLs.
            CASE 
                WHEN TRIM(cntry) = 'DE'                  THEN 'Germany'
                WHEN TRIM(cntry) IN ('US', 'USA')        THEN 'United States'
                WHEN TRIM(cntry) = '' OR cntry IS NULL   THEN 'n/a'
                ELSE TRIM(cntry)  -- Keep any other valid country name as-is
            END AS cntry

        FROM bronze.erp_LOC_A101;

        SET @end_time = GETDATE();
        PRINT '>> Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' sec';


        -- ----------------------------------------------------
        -- Table : silver.erp_PX_CAT_G1V2
        -- Source: bronze.erp_PX_CAT_G1V2
        -- Desc  : Product category and subcategory reference
        --         data from ERP. No transformations required —
        --         data is clean at the source. Loaded as-is.
        -- ----------------------------------------------------
        SET @start_time = GETDATE();

        PRINT '>> Truncating: silver.erp_PX_CAT_G1V2';
        TRUNCATE TABLE silver.erp_PX_CAT_G1V2;

        PRINT '>> Inserting: silver.erp_PX_CAT_G1V2';
        INSERT INTO silver.erp_PX_CAT_G1V2 (
            id,
            cat,
            subcat,
            maintenance
        )
        SELECT
            id,           -- Product category identifier — no transformation needed
            cat,          -- Top-level category name — no transformation needed
            subcat,       -- Subcategory name — no transformation needed
            maintenance   -- Maintenance classification — no transformation needed
        FROM bronze.erp_PX_CAT_G1V2;

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
        PRINT 'ERROR: Silver Load Failed';
        PRINT 'Message: ' + ERROR_MESSAGE();                       -- Human-readable error description
        PRINT 'Number : ' + CAST(ERROR_NUMBER() AS NVARCHAR);     -- SQL Server error code
        PRINT 'State  : ' + CAST(ERROR_STATE()  AS NVARCHAR);     -- Error state for diagnostics
        PRINT '=====================================';
    END CATCH;

    -- --------------------------------------------------------
    -- Log the total elapsed time for the entire Silver batch.
    -- Useful for monitoring and comparing load performance
    -- across runs over time.
    -- --------------------------------------------------------
    SET @batch_end_time = GETDATE();

    PRINT '=====================================';
    PRINT 'Total Batch Duration: '
          + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR)
          + ' sec';
    PRINT '=====================================';

END;


-- ============================================================
-- Execute the Silver load procedure
-- ============================================================
-- Run this after bronze.load_bronze has completed successfully.
-- All six Silver tables will be truncated and reloaded in sequence.

EXEC silver.load_silver;

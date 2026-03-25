-- ============================================================
-- Script  : Bronze Layer — Table Definitions
-- Schema  : bronze (raw / landing layer)
-- Purpose : Creates all raw staging tables for the Bronze layer.
--           Data is ingested as-is from two source systems:
--             - CRM  : Customer, Product, and Sales data
--             - ERP  : Customer demographics, Location, and Category data
--           No transformations are applied at this layer.
--           Cleansing and type casting is handled in Silver.
-- Note    : Each table is dropped and recreated if it already
--           exists, ensuring a clean structure on every run.
-- ============================================================

USE DataWarehouse;
GO


-- ============================================================
-- CRM TABLES
-- Source : CRM System
-- ============================================================

-- ------------------------------------------------------------
-- Table : bronze.crm_cust_info
-- Source: CRM — Customer Information
-- Desc  : Raw customer master data from the CRM system.
--         Contains personal details such as name, gender,
--         marital status, and account creation date.
-- ------------------------------------------------------------

IF OBJECT_ID('bronze.crm_cust_info', 'U') IS NOT NULL
    DROP TABLE bronze.crm_cust_info;

CREATE TABLE bronze.crm_cust_info (

    cst_id              INT,            -- Unique numeric customer ID from the source CRM system
    cst_key             NVARCHAR(50),   -- Business/natural key used to identify the customer in CRM (e.g. 'CRM-00123')
    cst_firstname       NVARCHAR(50),   -- Customer first name — stored raw, trimmed/cased in Silver
    cst_lastname        NVARCHAR(50),   -- Customer last name — stored raw, trimmed/cased in Silver
    cst_marital_status  NVARCHAR(50),   -- Marital status (e.g. 'Single', 'Married') — normalised in Silver
    cst_gndr            NVARCHAR(50),   -- Gender (e.g. 'Male', 'Female', 'n/a') — normalised in Silver
    cst_create_date     DATE            -- Date the customer record was created in the source CRM system

);
GO


-- ------------------------------------------------------------
-- Table : bronze.crm_prd_info
-- Source: CRM — Product Information
-- Desc  : Raw product master data from the CRM system.
--         All columns stored as NVARCHAR to prevent BULK INSERT
--         failures caused by NULL, empty, or misformatted
--         date/numeric values in the source CSV file.
-- ------------------------------------------------------------

IF OBJECT_ID('bronze.crm_prd_info', 'U') IS NOT NULL
    DROP TABLE bronze.crm_prd_info;

CREATE TABLE bronze.crm_prd_info (

    prd_id          NVARCHAR(50),   -- Unique product identifier from the source system
    prd_key         NVARCHAR(50),   -- Business key used to join with other source systems
    prd_nm          NVARCHAR(50),   -- Product name as provided by the source
    prd_cost        NVARCHAR(50),   -- Raw product cost — cast to DECIMAL in Silver
    prd_line        NVARCHAR(50),   -- Product line or category (e.g. 'Road', 'Mountain')
    prd_start_dt    NVARCHAR(50),   -- Raw product availability start date — cast to DATE in Silver
    prd_end_dt      NVARCHAR(50)    -- Raw product availability end date — cast to DATE in Silver
                                    -- Stored as NVARCHAR because source CSV contains NULLs
                                    -- and non-standard date formats that would fail DATE casting

);
GO


-- ------------------------------------------------------------
-- Table : bronze.crm_sales_details
-- Source: CRM — Sales Transactions
-- Desc  : Raw sales order data from the CRM system.
--         Date and numeric columns stored as INT to match the
--         source format (dates stored as integers e.g. 20260325).
--         These will be validated and cast in Silver.
-- ------------------------------------------------------------

IF OBJECT_ID('bronze.crm_sales_details', 'U') IS NOT NULL
    DROP TABLE bronze.crm_sales_details;

CREATE TABLE bronze.crm_sales_details (

    sls_ord_num     NVARCHAR(50),   -- Sales order number (e.g. 'SO-00123')
    sls_prd_key     NVARCHAR(50),   -- Product key — foreign key linking to crm_prd_info
    sls_cust_id     INT,            -- Customer ID — foreign key linking to crm_cust_info
    sls_order_dt    INT,            -- Order date stored as integer in source (e.g. 20260325) — cast to DATE in Silver
    sls_ship_dt     INT,            -- Shipment date stored as integer in source — cast to DATE in Silver
    sls_due_dt      INT,            -- Payment due date stored as integer in source — cast to DATE in Silver
    sls_sales       INT,            -- Total sales amount for the order line — validated in Silver
    sls_quantity    INT,            -- Quantity of product ordered — validated in Silver
    sls_price       INT             -- Unit price of the product — validated in Silver

);
GO


-- ============================================================
-- ERP TABLES
-- Source : ERP System
-- Note   : ERP column names are kept as-is from the source
--          (short/uppercase). They are renamed to standard
--          naming conventions in the Silver layer.
-- ============================================================

-- ------------------------------------------------------------
-- Table : bronze.erp_CUST_AZ12
-- Source: ERP — Customer Demographics
-- Desc  : Raw customer demographic data from the ERP system.
--         Contains birth date and gender per customer.
--         Joined to CRM customer data in Silver using CID.
-- ------------------------------------------------------------

IF OBJECT_ID('bronze.erp_CUST_AZ12', 'U') IS NOT NULL
    DROP TABLE bronze.erp_CUST_AZ12;

CREATE TABLE bronze.erp_CUST_AZ12 (

    CID     NVARCHAR(50),   -- Customer identifier — used to join with CRM customer data in Silver
    BDATE   NVARCHAR(50),   -- Raw birth date — stored as text to handle format variations, cast to DATE in Silver
    GEN     NVARCHAR(50)    -- Gender code from ERP (e.g. 'M', 'F') — decoded and normalised in Silver

);
GO


-- ------------------------------------------------------------
-- Table : bronze.erp_LOC_A101
-- Source: ERP — Customer Location
-- Desc  : Raw customer country/location data from the ERP system.
--         Used to enrich customer records with geography in Silver.
-- ------------------------------------------------------------

IF OBJECT_ID('bronze.erp_LOC_A101', 'U') IS NOT NULL
    DROP TABLE bronze.erp_LOC_A101;

CREATE TABLE bronze.erp_LOC_A101 (

    CID     NVARCHAR(50),   -- Customer identifier — foreign key linking to ERP and CRM customer data
    CNTRY   NVARCHAR(50)    -- Raw country name or code (e.g. 'US', 'United States') — standardised in Silver

);
GO


-- ------------------------------------------------------------
-- Table : bronze.erp_PX_CAT_G1V2
-- Source: ERP — Product Category
-- Desc  : Raw product category and subcategory data from the ERP system.
--         Used to enrich product records with category hierarchy in Silver.
-- ------------------------------------------------------------

IF OBJECT_ID('bronze.erp_PX_CAT_G1V2', 'U') IS NOT NULL
    DROP TABLE bronze.erp_PX_CAT_G1V2;

CREATE TABLE bronze.erp_PX_CAT_G1V2 (

    ID          NVARCHAR(50),   -- Product category identifier — links to product data in Silver
    CAT         NVARCHAR(50),   -- Top-level product category (e.g. 'Bikes', 'Accessories')
    SUBCAT      NVARCHAR(50),   -- Product subcategory (e.g. 'Road Bikes', 'Helmets')
    MAINTENANCE NVARCHAR(50)    -- Maintenance flag or classification for the product category

);
GO

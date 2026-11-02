/* =====================================================================
   Lusitânia Stores — Project 1, Step 2
   Creates the data warehouse database (LusitaniaDW):

     stg.*   staging tables  (raw copies of the source, truncated each load)
     dim.*   dimension tables (surrogate keys, SCD2 columns, Unknown member)
     fact.*  fact table       (grain: one row per order line)
     etl.*   control tables   (watermarks for incremental loads, run log)

   Run in SSMS against localhost. Safe to rerun: drops and recreates the DW.
   ===================================================================== */

SET LANGUAGE us_english;   -- makes month/day names deterministic
SET DATEFIRST 1;           -- Monday = first day of the week
GO

USE master;
GO

IF DB_ID('LusitaniaDW') IS NOT NULL
BEGIN
    ALTER DATABASE LusitaniaDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE LusitaniaDW;
END
GO

CREATE DATABASE LusitaniaDW;
GO

-- Simple recovery: a DW is reloadable from source, so no need for full log backups
ALTER DATABASE LusitaniaDW SET RECOVERY SIMPLE;
GO

USE LusitaniaDW;
GO

CREATE SCHEMA stg;
GO
CREATE SCHEMA dim;
GO
CREATE SCHEMA fact;
GO
CREATE SCHEMA etl;
GO

/* =====================================================================
   1. STAGING  — same columns as the source, no constraints.
      Filled by SSIS (truncate + load). Never queried by reports.
   ===================================================================== */

CREATE TABLE stg.Customer (
    CustomerID      INT,
    CustomerCode    VARCHAR(10),
    FirstName       NVARCHAR(50),
    LastName        NVARCHAR(50),
    Email           NVARCHAR(120),
    Phone           VARCHAR(20),
    City            NVARCHAR(50),
    District        NVARCHAR(50),
    Segment         NVARCHAR(20),
    BirthDate       DATE,
    CreatedDate     DATE,
    ModifiedDate    DATETIME2(0),
    StagedAt        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

-- Product is flattened at extraction time (join Product + Category + Department)
CREATE TABLE stg.Product (
    ProductID       INT,
    SKU             VARCHAR(20),
    ProductName     NVARCHAR(100),
    Brand           NVARCHAR(50),
    CategoryName    NVARCHAR(50),
    DepartmentName  NVARCHAR(50),
    ListPrice       DECIMAL(10,2),
    IsActive        BIT,
    ModifiedDate    DATETIME2(0),
    StagedAt        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE stg.Store (
    StoreID         INT,
    StoreCode       VARCHAR(10),
    StoreName       NVARCHAR(100),
    StoreType       NVARCHAR(20),
    City            NVARCHAR(50),
    District        NVARCHAR(50),
    OpenDate        DATE,
    ModifiedDate    DATETIME2(0),
    StagedAt        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

-- Sales is flattened at extraction time (join SalesOrder + SalesOrderLine)
CREATE TABLE stg.Sales (
    OrderID         INT,
    OrderNumber     VARCHAR(20),
    OrderDate       DATETIME2(0),
    StoreCode       VARCHAR(10),
    CustomerCode    VARCHAR(10),       -- NULL for anonymous walk-ins
    Channel         VARCHAR(10),
    PaymentMethod   NVARCHAR(20),
    LineNumber      SMALLINT,
    SKU             VARCHAR(20),
    Quantity        INT,
    UnitPrice       DECIMAL(10,2),
    DiscountPct     DECIMAL(5,2),
    ModifiedDate    DATETIME2(0),
    StagedAt        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO

/* =====================================================================
   2. DIMENSIONS
   ===================================================================== */

/* ---------- dim.Date: generated, one row per day 2020-2030 ---------- */
CREATE TABLE dim.[Date] (
    DateKey         INT          NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY,  -- 20261029
    FullDate        DATE         NOT NULL,
    DayOfMonth      TINYINT      NOT NULL,
    DayName         VARCHAR(10)  NOT NULL,
    DayOfWeek       TINYINT      NOT NULL,   -- 1 = Monday ... 7 = Sunday
    IsWeekend       BIT          NOT NULL,
    ISOWeek         TINYINT      NOT NULL,
    MonthNumber     TINYINT      NOT NULL,
    MonthName       VARCHAR(10)  NOT NULL,
    MonthShort      CHAR(3)      NOT NULL,
    YearMonth       CHAR(7)      NOT NULL,   -- 2026-10
    Quarter         TINYINT      NOT NULL,
    QuarterName     CHAR(2)      NOT NULL,   -- Q4
    [Year]          SMALLINT     NOT NULL,
    IsHoliday       BIT          NOT NULL,
    HolidayName     NVARCHAR(50) NULL
);

;WITH d AS (
    SELECT TOP (DATEDIFF(DAY, '2020-01-01', '2030-12-31') + 1)
        FullDate = DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, CAST('2020-01-01' AS DATE))
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dim.[Date]
SELECT
    CONVERT(INT, CONVERT(CHAR(8), d.FullDate, 112)),
    d.FullDate,
    DAY(d.FullDate),
    DATENAME(WEEKDAY, d.FullDate),
    DATEPART(WEEKDAY, d.FullDate),
    CASE WHEN DATEPART(WEEKDAY, d.FullDate) IN (6, 7) THEN 1 ELSE 0 END,
    DATEPART(ISO_WEEK, d.FullDate),
    MONTH(d.FullDate),
    DATENAME(MONTH, d.FullDate),
    LEFT(DATENAME(MONTH, d.FullDate), 3),
    CONVERT(CHAR(7), d.FullDate, 120),
    DATEPART(QUARTER, d.FullDate),
    'Q' + CAST(DATEPART(QUARTER, d.FullDate) AS CHAR(1)),
    YEAR(d.FullDate),
    CASE WHEN h.HolidayName IS NULL THEN 0 ELSE 1 END,
    h.HolidayName
FROM d
LEFT JOIN (VALUES   -- Portuguese fixed-date public holidays (Easter-based ones left out for simplicity)
    (1, 1,  N'Ano Novo'),
    (4, 25, N'Dia da Liberdade'),
    (5, 1,  N'Dia do Trabalhador'),
    (6, 10, N'Dia de Portugal'),
    (8, 15, N'Assunção de Nossa Senhora'),
    (10, 5, N'Implantação da República'),
    (11, 1, N'Dia de Todos os Santos'),
    (12, 1, N'Restauração da Independência'),
    (12, 8, N'Imaculada Conceição'),
    (12, 25, N'Natal')
) h (M, D, HolidayName)
  ON h.M = MONTH(d.FullDate) AND h.D = DAY(d.FullDate);

-- Unknown date member (for facts with a missing/invalid date)
INSERT INTO dim.[Date]
VALUES (-1, '1900-01-01', 0, 'Unknown', 0, 0, 0, 0, 'Unknown', 'Unk', '1900-01', 0, 'Q0', 1900, 0, NULL);
GO

/* ---------- dim.Customer: SCD Type 2 (mixed) ----------
   Type 2 (new version on change): City, District, Segment
   Type 1 (overwrite in place):    FirstName, LastName, Email, Phone, BirthDate  */
CREATE TABLE dim.Customer (
    CustomerSK      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimCustomer PRIMARY KEY,  -- surrogate key
    CustomerCode    VARCHAR(10)   NOT NULL,                                            -- business key
    FirstName       NVARCHAR(50)  NOT NULL,
    LastName        NVARCHAR(50)  NOT NULL,
    FullName        AS (FirstName + N' ' + LastName),
    Email           NVARCHAR(120) NULL,
    Phone           VARCHAR(20)   NULL,
    BirthDate       DATE          NULL,
    City            NVARCHAR(50)  NOT NULL,   -- SCD2
    District        NVARCHAR(50)  NOT NULL,   -- SCD2
    Segment         NVARCHAR(20)  NOT NULL,   -- SCD2
    -- SCD2 housekeeping
    ValidFrom       DATE          NOT NULL,
    ValidTo         DATE          NOT NULL CONSTRAINT DF_DimCustomer_ValidTo DEFAULT '9999-12-31',
    IsCurrent       BIT           NOT NULL CONSTRAINT DF_DimCustomer_IsCurrent DEFAULT 1,
    -- change detection: one hash for Type 1 columns, one for Type 2 columns
    HashType1       VARBINARY(32) NULL,
    HashType2       VARBINARY(32) NULL,
    -- audit
    InsertedAt      DATETIME2(0)  NOT NULL CONSTRAINT DF_DimCustomer_Inserted DEFAULT SYSDATETIME(),
    UpdatedAt       DATETIME2(0)  NULL
);

-- Only ONE current row per customer is allowed
CREATE UNIQUE INDEX UX_DimCustomer_Current
    ON dim.Customer (CustomerCode) WHERE IsCurrent = 1;

SET IDENTITY_INSERT dim.Customer ON;
INSERT INTO dim.Customer (CustomerSK, CustomerCode, FirstName, LastName, City, District, Segment, ValidFrom)
VALUES (-1, 'UNKNOWN', N'Unknown', N'Customer', N'Unknown', N'Unknown', N'Unknown', '1900-01-01');
SET IDENTITY_INSERT dim.Customer OFF;
GO

/* ---------- dim.Product: SCD Type 2 (mixed), denormalized (star) ----------
   Type 2: CategoryName, DepartmentName, ListPrice
   Type 1: ProductName, Brand, IsActive  */
CREATE TABLE dim.Product (
    ProductSK       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimProduct PRIMARY KEY,
    SKU             VARCHAR(20)   NOT NULL,
    ProductName     NVARCHAR(100) NOT NULL,
    Brand           NVARCHAR(50)  NOT NULL,
    IsActive        BIT           NOT NULL,
    CategoryName    NVARCHAR(50)  NOT NULL,   -- SCD2
    DepartmentName  NVARCHAR(50)  NOT NULL,   -- SCD2
    ListPrice       DECIMAL(10,2) NOT NULL,   -- SCD2
    ValidFrom       DATE          NOT NULL,
    ValidTo         DATE          NOT NULL CONSTRAINT DF_DimProduct_ValidTo DEFAULT '9999-12-31',
    IsCurrent       BIT           NOT NULL CONSTRAINT DF_DimProduct_IsCurrent DEFAULT 1,
    HashType1       VARBINARY(32) NULL,
    HashType2       VARBINARY(32) NULL,
    InsertedAt      DATETIME2(0)  NOT NULL CONSTRAINT DF_DimProduct_Inserted DEFAULT SYSDATETIME(),
    UpdatedAt       DATETIME2(0)  NULL
);

CREATE UNIQUE INDEX UX_DimProduct_Current
    ON dim.Product (SKU) WHERE IsCurrent = 1;

SET IDENTITY_INSERT dim.Product ON;
INSERT INTO dim.Product (ProductSK, SKU, ProductName, Brand, IsActive, CategoryName, DepartmentName, ListPrice, ValidFrom)
VALUES (-1, 'UNKNOWN', N'Unknown Product', N'Unknown', 0, N'Unknown', N'Unknown', 0, '1900-01-01');
SET IDENTITY_INSERT dim.Product OFF;
GO

/* ---------- dim.Store: SCD Type 1 (overwrite, no history) ---------- */
CREATE TABLE dim.Store (
    StoreSK         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimStore PRIMARY KEY,
    StoreCode       VARCHAR(10)   NOT NULL CONSTRAINT UQ_DimStore_Code UNIQUE,
    StoreName       NVARCHAR(100) NOT NULL,
    StoreType       NVARCHAR(20)  NOT NULL,
    City            NVARCHAR(50)  NOT NULL,
    District        NVARCHAR(50)  NOT NULL,
    OpenDate        DATE          NULL,
    InsertedAt      DATETIME2(0)  NOT NULL CONSTRAINT DF_DimStore_Inserted DEFAULT SYSDATETIME(),
    UpdatedAt       DATETIME2(0)  NULL
);

SET IDENTITY_INSERT dim.Store ON;
INSERT INTO dim.Store (StoreSK, StoreCode, StoreName, StoreType, City, District)
VALUES (-1, 'UNKNOWN', N'Unknown Store', N'Unknown', N'Unknown', N'Unknown');
SET IDENTITY_INSERT dim.Store OFF;
GO

/* =====================================================================
   3. FACT  — grain: one row per order line
   ===================================================================== */
CREATE TABLE fact.Sales (
    SalesLineKey    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactSales PRIMARY KEY,
    -- dimension foreign keys (surrogate keys)
    DateKey         INT           NOT NULL CONSTRAINT FK_FactSales_Date     REFERENCES dim.[Date](DateKey),
    CustomerSK      INT           NOT NULL CONSTRAINT FK_FactSales_Customer REFERENCES dim.Customer(CustomerSK),
    ProductSK       INT           NOT NULL CONSTRAINT FK_FactSales_Product  REFERENCES dim.Product(ProductSK),
    StoreSK         INT           NOT NULL CONSTRAINT FK_FactSales_Store    REFERENCES dim.Store(StoreSK),
    -- degenerate dimensions (attributes with no dimension table of their own)
    OrderNumber     VARCHAR(20)   NOT NULL,
    OrderLineNumber SMALLINT      NOT NULL,
    Channel         VARCHAR(10)   NOT NULL,
    PaymentMethod   NVARCHAR(20)  NOT NULL,
    -- measures
    Quantity        INT           NOT NULL,   -- additive
    UnitPrice       DECIMAL(10,2) NOT NULL,   -- NON-additive (never SUM it)
    DiscountPct     DECIMAL(5,2)  NOT NULL,   -- NON-additive
    GrossAmount     DECIMAL(12,2) NOT NULL,   -- additive: Quantity * UnitPrice
    DiscountAmount  DECIMAL(12,2) NOT NULL,   -- additive
    NetAmount       DECIMAL(12,2) NOT NULL,   -- additive: Gross - Discount
    -- audit
    SourceModifiedDate DATETIME2(0) NULL,
    InsertedAt      DATETIME2(0)  NOT NULL CONSTRAINT DF_FactSales_Inserted DEFAULT SYSDATETIME(),
    UpdatedAt       DATETIME2(0)  NULL,
    -- the business key of the grain: guarantees idempotent loads (no duplicates)
    CONSTRAINT UQ_FactSales_OrderLine UNIQUE (OrderNumber, OrderLineNumber)
);

CREATE INDEX IX_FactSales_DateKey     ON fact.Sales (DateKey);
CREATE INDEX IX_FactSales_CustomerSK  ON fact.Sales (CustomerSK);
CREATE INDEX IX_FactSales_ProductSK   ON fact.Sales (ProductSK);
GO

/* =====================================================================
   4. ETL CONTROL
   ===================================================================== */

-- Last successfully loaded ModifiedDate per source entity (incremental loads)
CREATE TABLE etl.Watermark (
    EntityName       VARCHAR(50)  NOT NULL CONSTRAINT PK_Watermark PRIMARY KEY,
    LastModifiedDate DATETIME2(0) NOT NULL CONSTRAINT DF_Watermark_Last DEFAULT '1900-01-01',
    UpdatedAt        DATETIME2(0) NULL
);

INSERT INTO etl.Watermark (EntityName)
VALUES ('Customer'), ('Product'), ('Store'), ('Sales');

-- One row per package run
CREATE TABLE etl.LoadLog (
    LoadLogID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LoadLog PRIMARY KEY,
    PackageName     VARCHAR(100)  NOT NULL,
    StartTime       DATETIME2(0)  NOT NULL CONSTRAINT DF_LoadLog_Start DEFAULT SYSDATETIME(),
    EndTime         DATETIME2(0)  NULL,
    RowsInserted    INT           NULL,
    RowsUpdated     INT           NULL,
    Status          VARCHAR(20)   NOT NULL CONSTRAINT DF_LoadLog_Status DEFAULT 'Running',  -- Running / Succeeded / Failed
    ErrorMessage    NVARCHAR(4000) NULL
);
GO

/* =====================================================================
   5. CHECKS
   ===================================================================== */
SELECT s.name AS SchemaName, t.name AS TableName
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY s.name, t.name;

SELECT MIN(FullDate) AS FirstDate, MAX(FullDate) AS LastDate, COUNT(*) AS DaysIncludingUnknown
FROM dim.[Date];

SELECT 'dim.Customer' AS DimTable, CustomerSK AS SK, CustomerCode AS BusinessKey FROM dim.Customer
UNION ALL SELECT 'dim.Product', ProductSK, SKU FROM dim.Product
UNION ALL SELECT 'dim.Store',   StoreSK,   StoreCode FROM dim.Store;

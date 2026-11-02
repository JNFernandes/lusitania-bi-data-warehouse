/* =====================================================================
   Lusitânia Stores — Project 1, Step 7
   Creates the stored procedure that loads fact.Sales from stg.Sales.

   For every sales line it:
     1. swaps business keys for SURROGATE KEYS (lookups on the dimensions)
          OrderDate     → DateKey     (dim.Date)
          StoreCode     → StoreSK     (dim.Store)
          CustomerCode  → CustomerSK  (dim.Customer, version valid ON the sale date)
          SKU           → ProductSK   (dim.Product,  version valid ON the sale date)
        Anything not found → -1 (Unknown member)
     2. calculates the measures (Gross, Discount, Net)
     3. MERGEs into fact.Sales on the grain (OrderNumber + OrderLineNumber):
        new line → INSERT, changed line → UPDATE, same line → nothing

   Run this whole file in SSMS (F5). Requires steps 4, 5 and 6 to have
   loaded the dimensions first (dimensions BEFORE facts).
   ===================================================================== */

USE LusitaniaDW;
GO

CREATE OR ALTER PROCEDURE etl.usp_Load_FactSales
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* -----------------------------------------------------------------
       STEP 1 — Build the fact rows: lookups + measures
       ----------------------------------------------------------------- */
    DROP TABLE IF EXISTS #src;

    SELECT
        DateKey     = ISNULL(dd.DateKey, -1),
        CustomerSK  = ISNULL(dc.CustomerSK, -1),   -- NULL CustomerCode (walk-in) → -1
        ProductSK   = ISNULL(dp.ProductSK, -1),
        StoreSK     = ISNULL(ds.StoreSK, -1),
        s.OrderNumber,
        OrderLineNumber = s.LineNumber,
        s.Channel,
        s.PaymentMethod,
        s.Quantity,
        s.UnitPrice,
        s.DiscountPct,
        GrossAmount    = CAST(s.Quantity * s.UnitPrice AS DECIMAL(12,2)),
        DiscountAmount = CAST(ROUND(s.Quantity * s.UnitPrice * s.DiscountPct / 100, 2) AS DECIMAL(12,2)),
        SourceModifiedDate = s.ModifiedDate
    INTO #src
    FROM stg.Sales s

    -- Date: exact match on the calendar day
    LEFT JOIN dim.[Date] dd
           ON dd.FullDate = CAST(s.OrderDate AS DATE)

    -- Store: SCD1, only one row per store
    LEFT JOIN dim.Store ds
           ON ds.StoreCode = s.StoreCode

    -- Customer: SCD2 → pick the version whose validity period contains the sale date
    LEFT JOIN dim.Customer dc
           ON dc.CustomerCode = s.CustomerCode
          AND CAST(s.OrderDate AS DATE) BETWEEN dc.ValidFrom AND dc.ValidTo

    -- Product: SCD2 → same "point-in-time" lookup
    LEFT JOIN dim.Product dp
           ON dp.SKU = s.SKU
          AND CAST(s.OrderDate AS DATE) BETWEEN dp.ValidFrom AND dp.ValidTo;

    /* -----------------------------------------------------------------
       STEP 2 — MERGE into the fact on the grain
       ----------------------------------------------------------------- */
    DECLARE @Actions TABLE (Action NVARCHAR(10));

    BEGIN TRANSACTION;

    MERGE fact.Sales AS tgt
    USING #src AS src
       ON tgt.OrderNumber     = src.OrderNumber
      AND tgt.OrderLineNumber = src.OrderLineNumber

    WHEN MATCHED AND EXISTS (
            SELECT src.DateKey, src.CustomerSK, src.ProductSK, src.StoreSK, src.Channel,
                   src.PaymentMethod, src.Quantity, src.UnitPrice, src.DiscountPct,
                   src.GrossAmount, src.DiscountAmount
            EXCEPT
            SELECT tgt.DateKey, tgt.CustomerSK, tgt.ProductSK, tgt.StoreSK, tgt.Channel,
                   tgt.PaymentMethod, tgt.Quantity, tgt.UnitPrice, tgt.DiscountPct,
                   tgt.GrossAmount, tgt.DiscountAmount
         )
    THEN UPDATE SET
            tgt.DateKey        = src.DateKey,
            tgt.CustomerSK     = src.CustomerSK,
            tgt.ProductSK      = src.ProductSK,
            tgt.StoreSK        = src.StoreSK,
            tgt.Channel        = src.Channel,
            tgt.PaymentMethod  = src.PaymentMethod,
            tgt.Quantity       = src.Quantity,
            tgt.UnitPrice      = src.UnitPrice,
            tgt.DiscountPct    = src.DiscountPct,
            tgt.GrossAmount    = src.GrossAmount,
            tgt.DiscountAmount = src.DiscountAmount,
            tgt.NetAmount      = src.GrossAmount - src.DiscountAmount,
            tgt.SourceModifiedDate = src.SourceModifiedDate,
            tgt.UpdatedAt      = SYSDATETIME()

    WHEN NOT MATCHED BY TARGET
    THEN INSERT (DateKey, CustomerSK, ProductSK, StoreSK, OrderNumber, OrderLineNumber,
                 Channel, PaymentMethod, Quantity, UnitPrice, DiscountPct,
                 GrossAmount, DiscountAmount, NetAmount, SourceModifiedDate)
         VALUES (src.DateKey, src.CustomerSK, src.ProductSK, src.StoreSK, src.OrderNumber,
                 src.OrderLineNumber, src.Channel, src.PaymentMethod, src.Quantity,
                 src.UnitPrice, src.DiscountPct, src.GrossAmount, src.DiscountAmount,
                 src.GrossAmount - src.DiscountAmount, src.SourceModifiedDate)

    OUTPUT $action INTO @Actions;

    COMMIT TRANSACTION;

    SELECT
        RowsInserted = SUM(CASE WHEN Action = 'INSERT' THEN 1 ELSE 0 END),
        RowsUpdated  = SUM(CASE WHEN Action = 'UPDATE' THEN 1 ELSE 0 END)
    FROM @Actions;
END;
GO


/* =====================================================================
   FIRST LOAD — expect RowsInserted ≈ 99,875 (same as stg.Sales)
   ===================================================================== */
EXEC etl.usp_Load_FactSales;
GO

/* SECOND LOAD — expect 0 and 0 (idempotent: the UNIQUE grain + MERGE) */
EXEC etl.usp_Load_FactSales;
GO


/* =====================================================================
   CHECKS
   ===================================================================== */

-- 1) Reconciliation: does the warehouse total equal the source total?
--    This is the single most important check in any DW project.
SELECT
    SourceLines   = (SELECT COUNT(*) FROM LusitaniaOLTP.sales.SalesOrderLine),
    FactLines     = (SELECT COUNT(*) FROM fact.Sales),
    SourceNet     = (SELECT CAST(SUM(ROUND(Quantity * UnitPrice, 2)
                                   - ROUND(Quantity * UnitPrice * DiscountPct / 100, 2)) AS DECIMAL(14,2))
                     FROM LusitaniaOLTP.sales.SalesOrderLine),
    FactNet       = (SELECT SUM(NetAmount) FROM fact.Sales);

-- 2) How many lines went to each Unknown member?
--    Customer -1 should be the anonymous walk-ins (~22%); the others should be 0.
SELECT
    UnknownCustomer = SUM(CASE WHEN CustomerSK = -1 THEN 1 ELSE 0 END),
    UnknownProduct  = SUM(CASE WHEN ProductSK  = -1 THEN 1 ELSE 0 END),
    UnknownStore    = SUM(CASE WHEN StoreSK    = -1 THEN 1 ELSE 0 END),
    UnknownDate     = SUM(CASE WHEN DateKey    = -1 THEN 1 ELSE 0 END),
    TotalLines      = COUNT(*)
FROM fact.Sales;

-- 3) Your first STAR SCHEMA query: revenue by year, store district and department
SELECT
    d.[Year],
    s.District     AS StoreDistrict,
    p.DepartmentName,
    Orders     = COUNT(DISTINCT f.OrderNumber),
    Units      = SUM(f.Quantity),
    NetRevenue = SUM(f.NetAmount)
FROM fact.Sales   f
JOIN dim.[Date]   d ON d.DateKey   = f.DateKey
JOIN dim.Store    s ON s.StoreSK   = f.StoreSK
JOIN dim.Product  p ON p.ProductSK = f.ProductSK
GROUP BY d.[Year], s.District, p.DepartmentName
ORDER BY d.[Year], s.District, p.DepartmentName;

-- 4) Revenue by customer segment — anonymous sales appear as 'Unknown'
SELECT
    c.Segment,
    NetRevenue = SUM(f.NetAmount),
    ShareOfTotal = CAST(100.0 * SUM(f.NetAmount) / SUM(SUM(f.NetAmount)) OVER () AS DECIMAL(5,1))
FROM fact.Sales    f
JOIN dim.Customer  c ON c.CustomerSK = f.CustomerSK
GROUP BY c.Segment
ORDER BY NetRevenue DESC;
GO

/* =====================================================================
   Lusitânia Stores — Project 1, Step 6
   Creates the stored procedure that loads dim.Product from stg.Product.
   Same SCD pattern as dim.Customer (step 5):

     SCD Type 2 (keep history):   CategoryName, DepartmentName, ListPrice
     SCD Type 1 (overwrite):      ProductName, Brand, IsActive

   Why ListPrice is Type 2: reports like "average list price by month"
   must show the price that was valid at the time, not today's price.

   Run this whole file in SSMS (F5). Tests run inside a transaction
   that is rolled back, so they leave no trace.
   ===================================================================== */

USE LusitaniaDW;
GO

CREATE OR ALTER PROCEDURE etl.usp_Load_DimProduct
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Type1Updated INT = 0, @Expired INT = 0, @Inserted INT = 0;

    /* STEP 0 — staging rows + the two fingerprints */
    DROP TABLE IF EXISTS #src;

    SELECT
        s.SKU, s.ProductName, s.Brand, s.IsActive,
        s.CategoryName, s.DepartmentName, s.ListPrice,
        ChangeDate = CAST(ISNULL(s.ModifiedDate, SYSDATETIME()) AS DATE),
        HashType1  = HASHBYTES('SHA2_256', CONCAT_WS('|',
                        ISNULL(s.ProductName, N''), ISNULL(s.Brand, N''),
                        ISNULL(CAST(s.IsActive AS CHAR(1)), ''))),
        HashType2  = HASHBYTES('SHA2_256', CONCAT_WS('|',
                        ISNULL(s.CategoryName, N''), ISNULL(s.DepartmentName, N''),
                        ISNULL(CAST(s.ListPrice AS VARCHAR(20)), '')))
    INTO #src
    FROM stg.Product s;

    BEGIN TRANSACTION;

    /* STEP 1 — Type 1: overwrite on all versions */
    UPDATE d
    SET d.ProductName = s.ProductName,
        d.Brand       = s.Brand,
        d.IsActive    = s.IsActive,
        d.HashType1   = s.HashType1,
        d.UpdatedAt   = SYSDATETIME()
    FROM dim.Product d
    JOIN #src s ON s.SKU = d.SKU
    WHERE d.HashType1 <> s.HashType1 OR d.HashType1 IS NULL;

    SET @Type1Updated = @@ROWCOUNT;

    /* STEP 2 — Type 2: expire the current version */
    UPDATE d
    SET d.ValidTo   = DATEADD(DAY, -1, s.ChangeDate),
        d.IsCurrent = 0,
        d.UpdatedAt = SYSDATETIME()
    FROM dim.Product d
    JOIN #src s ON s.SKU = d.SKU
    WHERE d.IsCurrent = 1
      AND d.HashType2 <> s.HashType2;

    SET @Expired = @@ROWCOUNT;

    /* STEP 3 — insert a current row for every product that has none */
    INSERT INTO dim.Product
        (SKU, ProductName, Brand, IsActive, CategoryName, DepartmentName, ListPrice,
         ValidFrom, ValidTo, IsCurrent, HashType1, HashType2)
    SELECT
        s.SKU, s.ProductName, s.Brand, s.IsActive, s.CategoryName, s.DepartmentName, s.ListPrice,
        ValidFrom = CASE WHEN EXISTS (SELECT 1 FROM dim.Product x WHERE x.SKU = s.SKU)
                         THEN s.ChangeDate
                         ELSE '1900-01-01' END,
        '9999-12-31', 1, s.HashType1, s.HashType2
    FROM #src s
    WHERE NOT EXISTS (SELECT 1 FROM dim.Product d
                      WHERE d.SKU = s.SKU AND d.IsCurrent = 1);

    SET @Inserted = @@ROWCOUNT;

    COMMIT TRANSACTION;

    SELECT
        NewProducts      = @Inserted - @Expired,
        NewVersions      = @Expired,
        ExpiredVersions  = @Expired,
        Type1RowsUpdated = @Type1Updated;
END;
GO


/* =====================================================================
   FIRST LOAD — expect NewProducts = 240, everything else 0
   ===================================================================== */
EXEC etl.usp_Load_DimProduct;
GO

/* SECOND LOAD — expect all zeros (idempotent) */
EXEC etl.usp_Load_DimProduct;
GO

/* =====================================================================
   TESTS (rolled back at the end)
     SKU-00001 gets a 10% price increase → Type 2: new version
     SKU-00002 is renamed                → Type 1: overwrite
   ===================================================================== */
BEGIN TRANSACTION;

    SELECT 'BEFORE' AS Moment, ProductSK, SKU, ProductName, CategoryName, ListPrice,
           ValidFrom, ValidTo, IsCurrent
    FROM dim.Product
    WHERE SKU IN ('SKU-00001', 'SKU-00002')
    ORDER BY SKU, ValidFrom;

    UPDATE stg.Product
    SET ListPrice = CAST(ListPrice * 1.10 AS DECIMAL(10,2)),
        ModifiedDate = '2026-06-01'
    WHERE SKU = 'SKU-00001';

    UPDATE stg.Product
    SET ProductName = ProductName + N' (2026 edition)',
        ModifiedDate = '2026-06-01'
    WHERE SKU = 'SKU-00002';

    -- Expect: NewProducts 0, NewVersions 1, Expired 1, Type1RowsUpdated 1
    EXEC etl.usp_Load_DimProduct;

    SELECT 'AFTER' AS Moment, ProductSK, SKU, ProductName, CategoryName, ListPrice,
           ValidFrom, ValidTo, IsCurrent
    FROM dim.Product
    WHERE SKU IN ('SKU-00001', 'SKU-00002')
    ORDER BY SKU, ValidFrom;

ROLLBACK TRANSACTION;
GO

-- Confirm the rollback: 240 rows, all current
SELECT COUNT(*) AS TotalRows, SUM(CAST(IsCurrent AS INT)) AS CurrentRows
FROM dim.Product
WHERE ProductSK <> -1;
GO

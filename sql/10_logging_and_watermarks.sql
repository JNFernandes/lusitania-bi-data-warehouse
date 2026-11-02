/* =====================================================================
   Lusitânia Stores — Project 1, Step 10
   Logging + incremental loading (database side).

   PART A (LusitaniaOLTP)
     Two "extract views" with a single ModifiedDate column each, so SSIS
     can filter them with a simple  WHERE ModifiedDate > ?

   PART B (LusitaniaDW)
     1. The four load procedures again, now with LOGGING:
        each run writes one row to etl.LoadLog (start, end, rows, status,
        and the error message if it fails). The load logic is unchanged.
     2. etl.usp_Get_Watermarks    → returns the 4 bookmarks to SSIS
     3. etl.usp_Update_Watermarks → moves the bookmarks forward after a
                                    SUCCESSFUL load
     4. Initializes the watermarks from the current (full) staging.

   Run the whole file in SSMS (F5). Safe to rerun.
   ===================================================================== */


/* =====================================================================
   PART A — extract views in the SOURCE
   ===================================================================== */
USE LusitaniaOLTP;
GO

CREATE OR ALTER VIEW product.vw_ProductExtract
AS
SELECT
    p.ProductID,
    p.SKU,
    p.ProductName,
    p.Brand,
    c.CategoryName,
    d.DepartmentName,
    p.ListPrice,
    p.IsActive,
    -- most recent change across the 3 tables (a category rename counts too)
    ModifiedDate = (SELECT MAX(v) FROM (VALUES (p.ModifiedDate), (c.ModifiedDate), (d.ModifiedDate)) x (v))
FROM product.Product     p
JOIN product.Category    c ON c.CategoryID   = p.CategoryID
JOIN product.Department  d ON d.DepartmentID = c.DepartmentID;
GO

CREATE OR ALTER VIEW sales.vw_SalesExtract
AS
SELECT
    o.OrderID,
    o.OrderNumber,
    o.OrderDate,
    s.StoreCode,
    cu.CustomerCode,
    o.Channel,
    o.PaymentMethod,
    l.LineNumber,
    p.SKU,
    l.Quantity,
    l.UnitPrice,
    l.DiscountPct,
    -- a line counts as changed if the line OR its order header changed
    ModifiedDate = CASE WHEN l.ModifiedDate > o.ModifiedDate THEN l.ModifiedDate ELSE o.ModifiedDate END
FROM sales.SalesOrder          o
JOIN sales.SalesOrderLine      l  ON l.OrderID     = o.OrderID
JOIN sales.Store               s  ON s.StoreID     = o.StoreID
JOIN product.Product           p  ON p.ProductID   = l.ProductID
LEFT JOIN sales.Customer       cu ON cu.CustomerID = o.CustomerID;
GO


/* =====================================================================
   PART B — warehouse procedures with logging
   Pattern used in every procedure:

     1. insert a 'Running' row in etl.LoadLog
     2. BEGIN TRY  → do the load in a transaction → mark 'Succeeded' + counts
     3. BEGIN CATCH → roll back, mark 'Failed' + error message, re-raise
        (re-raising with THROW makes the SSIS task turn red as well)
   ===================================================================== */
USE LusitaniaDW;
GO

/* ---------------------------------------------------------------------
   dim.Store — SCD1
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimStore
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LogID INT;
    INSERT INTO etl.LoadLog (PackageName) VALUES (OBJECT_NAME(@@PROCID));
    SET @LogID = SCOPE_IDENTITY();

    BEGIN TRY
        DECLARE @Actions TABLE (Action NVARCHAR(10));

        BEGIN TRANSACTION;

        MERGE dim.Store AS tgt
        USING (SELECT StoreCode, StoreName, StoreType, City, District, OpenDate FROM stg.Store) AS src
           ON tgt.StoreCode = src.StoreCode
        WHEN MATCHED AND EXISTS (
                SELECT src.StoreName, src.StoreType, src.City, src.District, src.OpenDate
                EXCEPT
                SELECT tgt.StoreName, tgt.StoreType, tgt.City, tgt.District, tgt.OpenDate)
        THEN UPDATE SET
                tgt.StoreName = src.StoreName, tgt.StoreType = src.StoreType,
                tgt.City = src.City, tgt.District = src.District,
                tgt.OpenDate = src.OpenDate, tgt.UpdatedAt = SYSDATETIME()
        WHEN NOT MATCHED BY TARGET
        THEN INSERT (StoreCode, StoreName, StoreType, City, District, OpenDate)
             VALUES (src.StoreCode, src.StoreName, src.StoreType, src.City, src.District, src.OpenDate)
        OUTPUT $action INTO @Actions;

        COMMIT TRANSACTION;

        DECLARE @Ins INT = (SELECT COUNT(*) FROM @Actions WHERE Action = 'INSERT');
        DECLARE @Upd INT = (SELECT COUNT(*) FROM @Actions WHERE Action = 'UPDATE');

        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), RowsInserted = @Ins, RowsUpdated = @Upd, Status = 'Succeeded'
        WHERE LoadLogID = @LogID;

        SELECT RowsInserted = @Ins, RowsUpdated = @Upd;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), Status = 'Failed', ErrorMessage = ERROR_MESSAGE()
        WHERE LoadLogID = @LogID;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   dim.Customer — SCD2 (mixed)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimCustomer
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LogID INT;
    INSERT INTO etl.LoadLog (PackageName) VALUES (OBJECT_NAME(@@PROCID));
    SET @LogID = SCOPE_IDENTITY();

    BEGIN TRY
        DECLARE @Type1Updated INT = 0, @Expired INT = 0, @Inserted INT = 0;

        DROP TABLE IF EXISTS #src;
        SELECT
            s.CustomerCode, s.FirstName, s.LastName, s.Email, s.Phone, s.BirthDate,
            s.City, s.District, s.Segment,
            ChangeDate = CAST(ISNULL(s.ModifiedDate, SYSDATETIME()) AS DATE),
            HashType1  = HASHBYTES('SHA2_256', CONCAT_WS('|',
                            ISNULL(s.FirstName, N''), ISNULL(s.LastName, N''),
                            ISNULL(s.Email, N''), ISNULL(s.Phone, ''),
                            ISNULL(CONVERT(CHAR(10), s.BirthDate, 120), ''))),
            HashType2  = HASHBYTES('SHA2_256', CONCAT_WS('|',
                            ISNULL(s.City, N''), ISNULL(s.District, N''), ISNULL(s.Segment, N'')))
        INTO #src
        FROM stg.Customer s;

        BEGIN TRANSACTION;

        -- Type 1: overwrite on all versions
        UPDATE d
        SET d.FirstName = s.FirstName, d.LastName = s.LastName, d.Email = s.Email,
            d.Phone = s.Phone, d.BirthDate = s.BirthDate,
            d.HashType1 = s.HashType1, d.UpdatedAt = SYSDATETIME()
        FROM dim.Customer d
        JOIN #src s ON s.CustomerCode = d.CustomerCode
        WHERE d.HashType1 <> s.HashType1 OR d.HashType1 IS NULL;
        SET @Type1Updated = @@ROWCOUNT;

        -- Type 2: expire the current version
        UPDATE d
        SET d.ValidTo = DATEADD(DAY, -1, s.ChangeDate), d.IsCurrent = 0, d.UpdatedAt = SYSDATETIME()
        FROM dim.Customer d
        JOIN #src s ON s.CustomerCode = d.CustomerCode
        WHERE d.IsCurrent = 1 AND d.HashType2 <> s.HashType2;
        SET @Expired = @@ROWCOUNT;

        -- Insert a current row for every customer that has none
        INSERT INTO dim.Customer
            (CustomerCode, FirstName, LastName, Email, Phone, BirthDate,
             City, District, Segment, ValidFrom, ValidTo, IsCurrent, HashType1, HashType2)
        SELECT
            s.CustomerCode, s.FirstName, s.LastName, s.Email, s.Phone, s.BirthDate,
            s.City, s.District, s.Segment,
            CASE WHEN EXISTS (SELECT 1 FROM dim.Customer x WHERE x.CustomerCode = s.CustomerCode)
                 THEN s.ChangeDate ELSE '1900-01-01' END,
            '9999-12-31', 1, s.HashType1, s.HashType2
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dim.Customer d
                          WHERE d.CustomerCode = s.CustomerCode AND d.IsCurrent = 1);
        SET @Inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), RowsInserted = @Inserted,
            RowsUpdated = @Type1Updated + @Expired, Status = 'Succeeded'
        WHERE LoadLogID = @LogID;

        SELECT NewCustomers = @Inserted - @Expired, NewVersions = @Expired,
               ExpiredVersions = @Expired, Type1RowsUpdated = @Type1Updated;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), Status = 'Failed', ErrorMessage = ERROR_MESSAGE()
        WHERE LoadLogID = @LogID;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   dim.Product — SCD2 (mixed)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimProduct
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LogID INT;
    INSERT INTO etl.LoadLog (PackageName) VALUES (OBJECT_NAME(@@PROCID));
    SET @LogID = SCOPE_IDENTITY();

    BEGIN TRY
        DECLARE @Type1Updated INT = 0, @Expired INT = 0, @Inserted INT = 0;

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

        UPDATE d
        SET d.ProductName = s.ProductName, d.Brand = s.Brand, d.IsActive = s.IsActive,
            d.HashType1 = s.HashType1, d.UpdatedAt = SYSDATETIME()
        FROM dim.Product d
        JOIN #src s ON s.SKU = d.SKU
        WHERE d.HashType1 <> s.HashType1 OR d.HashType1 IS NULL;
        SET @Type1Updated = @@ROWCOUNT;

        UPDATE d
        SET d.ValidTo = DATEADD(DAY, -1, s.ChangeDate), d.IsCurrent = 0, d.UpdatedAt = SYSDATETIME()
        FROM dim.Product d
        JOIN #src s ON s.SKU = d.SKU
        WHERE d.IsCurrent = 1 AND d.HashType2 <> s.HashType2;
        SET @Expired = @@ROWCOUNT;

        INSERT INTO dim.Product
            (SKU, ProductName, Brand, IsActive, CategoryName, DepartmentName, ListPrice,
             ValidFrom, ValidTo, IsCurrent, HashType1, HashType2)
        SELECT
            s.SKU, s.ProductName, s.Brand, s.IsActive, s.CategoryName, s.DepartmentName, s.ListPrice,
            CASE WHEN EXISTS (SELECT 1 FROM dim.Product x WHERE x.SKU = s.SKU)
                 THEN s.ChangeDate ELSE '1900-01-01' END,
            '9999-12-31', 1, s.HashType1, s.HashType2
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM dim.Product d WHERE d.SKU = s.SKU AND d.IsCurrent = 1);
        SET @Inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), RowsInserted = @Inserted,
            RowsUpdated = @Type1Updated + @Expired, Status = 'Succeeded'
        WHERE LoadLogID = @LogID;

        SELECT NewProducts = @Inserted - @Expired, NewVersions = @Expired,
               ExpiredVersions = @Expired, Type1RowsUpdated = @Type1Updated;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), Status = 'Failed', ErrorMessage = ERROR_MESSAGE()
        WHERE LoadLogID = @LogID;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   fact.Sales
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_FactSales
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LogID INT;
    INSERT INTO etl.LoadLog (PackageName) VALUES (OBJECT_NAME(@@PROCID));
    SET @LogID = SCOPE_IDENTITY();

    BEGIN TRY
        DROP TABLE IF EXISTS #src;
        SELECT
            DateKey     = ISNULL(dd.DateKey, -1),
            CustomerSK  = ISNULL(dc.CustomerSK, -1),
            ProductSK   = ISNULL(dp.ProductSK, -1),
            StoreSK     = ISNULL(ds.StoreSK, -1),
            s.OrderNumber,
            OrderLineNumber = s.LineNumber,
            s.Channel, s.PaymentMethod, s.Quantity, s.UnitPrice, s.DiscountPct,
            GrossAmount    = CAST(s.Quantity * s.UnitPrice AS DECIMAL(12,2)),
            DiscountAmount = CAST(ROUND(s.Quantity * s.UnitPrice * s.DiscountPct / 100, 2) AS DECIMAL(12,2)),
            SourceModifiedDate = s.ModifiedDate
        INTO #src
        FROM stg.Sales s
        LEFT JOIN dim.[Date]   dd ON dd.FullDate = CAST(s.OrderDate AS DATE)
        LEFT JOIN dim.Store    ds ON ds.StoreCode = s.StoreCode
        LEFT JOIN dim.Customer dc ON dc.CustomerCode = s.CustomerCode
                                 AND CAST(s.OrderDate AS DATE) BETWEEN dc.ValidFrom AND dc.ValidTo
        LEFT JOIN dim.Product  dp ON dp.SKU = s.SKU
                                 AND CAST(s.OrderDate AS DATE) BETWEEN dp.ValidFrom AND dp.ValidTo;

        DECLARE @Actions TABLE (Action NVARCHAR(10));

        BEGIN TRANSACTION;

        MERGE fact.Sales AS tgt
        USING #src AS src
           ON tgt.OrderNumber = src.OrderNumber AND tgt.OrderLineNumber = src.OrderLineNumber
        WHEN MATCHED AND EXISTS (
                SELECT src.DateKey, src.CustomerSK, src.ProductSK, src.StoreSK, src.Channel,
                       src.PaymentMethod, src.Quantity, src.UnitPrice, src.DiscountPct,
                       src.GrossAmount, src.DiscountAmount
                EXCEPT
                SELECT tgt.DateKey, tgt.CustomerSK, tgt.ProductSK, tgt.StoreSK, tgt.Channel,
                       tgt.PaymentMethod, tgt.Quantity, tgt.UnitPrice, tgt.DiscountPct,
                       tgt.GrossAmount, tgt.DiscountAmount)
        THEN UPDATE SET
                tgt.DateKey = src.DateKey, tgt.CustomerSK = src.CustomerSK,
                tgt.ProductSK = src.ProductSK, tgt.StoreSK = src.StoreSK,
                tgt.Channel = src.Channel, tgt.PaymentMethod = src.PaymentMethod,
                tgt.Quantity = src.Quantity, tgt.UnitPrice = src.UnitPrice,
                tgt.DiscountPct = src.DiscountPct, tgt.GrossAmount = src.GrossAmount,
                tgt.DiscountAmount = src.DiscountAmount,
                tgt.NetAmount = src.GrossAmount - src.DiscountAmount,
                tgt.SourceModifiedDate = src.SourceModifiedDate, tgt.UpdatedAt = SYSDATETIME()
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

        DECLARE @Ins INT = (SELECT COUNT(*) FROM @Actions WHERE Action = 'INSERT');
        DECLARE @Upd INT = (SELECT COUNT(*) FROM @Actions WHERE Action = 'UPDATE');

        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), RowsInserted = @Ins, RowsUpdated = @Upd, Status = 'Succeeded'
        WHERE LoadLogID = @LogID;

        SELECT RowsInserted = @Ins, RowsUpdated = @Upd;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE etl.LoadLog
        SET EndTime = SYSDATETIME(), Status = 'Failed', ErrorMessage = ERROR_MESSAGE()
        WHERE LoadLogID = @LogID;
        THROW;
    END CATCH
END;
GO


/* =====================================================================
   WATERMARKS
   ===================================================================== */

/* Returns the 4 bookmarks as ONE row with 4 columns, so SSIS can put
   each one into a variable. CAST to DATETIME because SSIS DateTime
   variables don't accept DATETIME2 from an OLE DB result set. */
CREATE OR ALTER PROCEDURE etl.usp_Get_Watermarks
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        CustomerWM = CAST(MAX(CASE WHEN EntityName = 'Customer' THEN LastModifiedDate END) AS DATETIME),
        StoreWM    = CAST(MAX(CASE WHEN EntityName = 'Store'    THEN LastModifiedDate END) AS DATETIME),
        ProductWM  = CAST(MAX(CASE WHEN EntityName = 'Product'  THEN LastModifiedDate END) AS DATETIME),
        SalesWM    = CAST(MAX(CASE WHEN EntityName = 'Sales'    THEN LastModifiedDate END) AS DATETIME)
    FROM etl.Watermark;
END;
GO

/* Moves each bookmark to the newest ModifiedDate that was just loaded.
   Runs at the END of the pipeline, only if everything succeeded:
   if the warehouse load fails, the bookmark stays where it was and the
   next run simply extracts the same rows again (safe, because every
   load is idempotent). An empty staging table leaves its bookmark alone. */
CREATE OR ALTER PROCEDURE etl.usp_Update_Watermarks
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LogID INT;
    INSERT INTO etl.LoadLog (PackageName) VALUES (OBJECT_NAME(@@PROCID));
    SET @LogID = SCOPE_IDENTITY();

    UPDATE w
    SET w.LastModifiedDate = x.MaxModified,
        w.UpdatedAt        = SYSDATETIME()
    FROM etl.Watermark w
    JOIN (
        SELECT 'Customer', MAX(ModifiedDate) FROM stg.Customer
        UNION ALL SELECT 'Store',   MAX(ModifiedDate) FROM stg.Store
        UNION ALL SELECT 'Product', MAX(ModifiedDate) FROM stg.Product
        UNION ALL SELECT 'Sales',   MAX(ModifiedDate) FROM stg.Sales
    ) x (EntityName, MaxModified)
      ON x.EntityName = w.EntityName
    WHERE x.MaxModified > w.LastModifiedDate;

    UPDATE etl.LoadLog
    SET EndTime = SYSDATETIME(), RowsUpdated = @@ROWCOUNT, Status = 'Succeeded'
    WHERE LoadLogID = @LogID;
END;
GO


/* =====================================================================
   INITIALIZE — staging currently holds the last FULL extract, so this
   sets every bookmark to "everything up to now has been loaded".
   ===================================================================== */
EXEC etl.usp_Update_Watermarks;

SELECT EntityName, LastModifiedDate, UpdatedAt
FROM etl.Watermark
ORDER BY EntityName;

-- What SSIS will receive
EXEC etl.usp_Get_Watermarks;

-- The log so far
SELECT LoadLogID, PackageName, StartTime, EndTime, RowsInserted, RowsUpdated, Status, ErrorMessage
FROM etl.LoadLog
ORDER BY LoadLogID DESC;
GO

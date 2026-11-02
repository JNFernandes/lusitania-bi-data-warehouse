/* =====================================================================
   Lusitânia Stores — Project 1, Step 5
   Creates the stored procedure that loads dim.Customer from stg.Customer.

   dim.Customer is a MIXED dimension:
     SCD Type 2 (keep history):   City, District, Segment
     SCD Type 1 (overwrite):      FirstName, LastName, Email, Phone, BirthDate

   Change detection uses two hashes (fingerprints):
     HashType1 = fingerprint of the Type 1 columns
     HashType2 = fingerprint of the Type 2 columns
   Comparing one hash is simpler than comparing every column, and it
   tells us WHICH kind of change happened.

   Run this whole file in SSMS (F5). It creates the procedure, loads
   the 3,000 customers, then runs tests inside a transaction that is
   rolled back, so the test changes leave no trace.
   ===================================================================== */

USE LusitaniaDW;
GO

CREATE OR ALTER PROCEDURE etl.usp_Load_DimCustomer
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- any error rolls back the whole load

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Type1Updated INT = 0, @Expired INT = 0, @NewCustomers INT = 0, @NewVersions INT = 0;

    /* -----------------------------------------------------------------
       STEP 0 — Prepare the source: staging rows + their two hashes.
       ISNULL(...,'') keeps NULLs from silently disappearing in the hash.
       ----------------------------------------------------------------- */
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

    /* -----------------------------------------------------------------
       STEP 1 — Type 1 changes: overwrite in place.
       Applied to ALL versions of the customer, so a corrected name or
       email shows the same everywhere in reports.
       ----------------------------------------------------------------- */
    UPDATE d
    SET d.FirstName = s.FirstName,
        d.LastName  = s.LastName,
        d.Email     = s.Email,
        d.Phone     = s.Phone,
        d.BirthDate = s.BirthDate,
        d.HashType1 = s.HashType1,
        d.UpdatedAt = SYSDATETIME()
    FROM dim.Customer d
    JOIN #src s ON s.CustomerCode = d.CustomerCode
    WHERE d.HashType1 <> s.HashType1 OR d.HashType1 IS NULL;

    SET @Type1Updated = @@ROWCOUNT;

    /* -----------------------------------------------------------------
       STEP 2 — Type 2 changes: EXPIRE the current version.
       The old row stays, but is closed: ValidTo = day before the change,
       IsCurrent = 0. Old sales keep pointing to it.
       ----------------------------------------------------------------- */
    UPDATE d
    SET d.ValidTo   = DATEADD(DAY, -1, s.ChangeDate),
        d.IsCurrent = 0,
        d.UpdatedAt = SYSDATETIME()
    FROM dim.Customer d
    JOIN #src s ON s.CustomerCode = d.CustomerCode
    WHERE d.IsCurrent = 1
      AND d.HashType2 <> s.HashType2;

    SET @Expired = @@ROWCOUNT;

    /* -----------------------------------------------------------------
       STEP 3 — INSERT a current row for every customer that has none:
         a) brand-new customers        → ValidFrom = 1900-01-01
            (the first version covers all history, so every past sale
             finds a matching version)
         b) customers expired in step 2 → ValidFrom = date of the change
       Each insert gets a NEW surrogate key from IDENTITY.
       ----------------------------------------------------------------- */
    INSERT INTO dim.Customer
        (CustomerCode, FirstName, LastName, Email, Phone, BirthDate,
         City, District, Segment, ValidFrom, ValidTo, IsCurrent, HashType1, HashType2)
    SELECT
        s.CustomerCode, s.FirstName, s.LastName, s.Email, s.Phone, s.BirthDate,
        s.City, s.District, s.Segment,
        ValidFrom = CASE WHEN EXISTS (SELECT 1 FROM dim.Customer x WHERE x.CustomerCode = s.CustomerCode)
                         THEN s.ChangeDate          -- b) new version
                         ELSE '1900-01-01' END,     -- a) first version
        '9999-12-31', 1, s.HashType1, s.HashType2
    FROM #src s
    WHERE NOT EXISTS (SELECT 1 FROM dim.Customer d
                      WHERE d.CustomerCode = s.CustomerCode AND d.IsCurrent = 1);

    DECLARE @Inserted INT = @@ROWCOUNT;
    SET @NewVersions  = @Expired;               -- every expired row got exactly one new version
    SET @NewCustomers = @Inserted - @Expired;   -- the remaining inserts are brand-new customers

    COMMIT TRANSACTION;

    SELECT
        NewCustomers     = @NewCustomers,
        NewVersions      = @NewVersions,
        ExpiredVersions  = @Expired,
        Type1RowsUpdated = @Type1Updated;   -- counts ROWS: a customer with 3 versions = 3
END;
GO


/* =====================================================================
   FIRST LOAD — all 3,000 customers are new
   Expect: NewCustomers = 3000, NewVersions = 0, Expired = 0.
   (Type1Updates is also 0: there were no existing rows to overwrite.)
   ===================================================================== */
EXEC etl.usp_Load_DimCustomer;

SELECT COUNT(*) AS CurrentCustomers
FROM dim.Customer
WHERE IsCurrent = 1 AND CustomerSK <> -1;
GO

/* =====================================================================
   SECOND LOAD — nothing changed → everything 0 (idempotent)
   ===================================================================== */
EXEC etl.usp_Load_DimCustomer;
GO

/* =====================================================================
   TESTS — inside a transaction that is ROLLED BACK at the end,
   so the warehouse returns exactly to how it was.
     C00001 moves city          → Type 2: new version
     C00002 changes email       → Type 1: overwrite, no new version
   ===================================================================== */
BEGIN TRANSACTION;

    -- Show both customers BEFORE
    SELECT 'BEFORE' AS Moment, CustomerSK, CustomerCode, FullName, Email, City, Segment,
           ValidFrom, ValidTo, IsCurrent
    FROM dim.Customer
    WHERE CustomerCode IN ('C00001', 'C00002')
    ORDER BY CustomerCode, ValidFrom;

    -- Simulate what the next staging extract would bring
    UPDATE stg.Customer
    SET City = CASE WHEN City = N'Lisboa' THEN N'Porto' ELSE N'Lisboa' END,
        District = CASE WHEN City = N'Lisboa' THEN N'Porto' ELSE N'Lisboa' END,
        ModifiedDate = '2026-03-15'
    WHERE CustomerCode = 'C00001';

    UPDATE stg.Customer
    SET Email = N'new.email@example.com',
        ModifiedDate = '2026-05-20'
    WHERE CustomerCode = 'C00002';

    -- Expect: NewCustomers 0, NewVersions 1, Expired 1, Type1Updates 1
    EXEC etl.usp_Load_DimCustomer;

    -- Show both customers AFTER
    SELECT 'AFTER' AS Moment, CustomerSK, CustomerCode, FullName, Email, City, Segment,
           ValidFrom, ValidTo, IsCurrent
    FROM dim.Customer
    WHERE CustomerCode IN ('C00001', 'C00002')
    ORDER BY CustomerCode, ValidFrom;

ROLLBACK TRANSACTION;   -- undo the test: staging and dim.Customer back to normal
GO

-- Confirm the rollback worked: still one row per customer
SELECT COUNT(*) AS TotalRows, SUM(CAST(IsCurrent AS INT)) AS CurrentRows
FROM dim.Customer
WHERE CustomerSK <> -1;
GO

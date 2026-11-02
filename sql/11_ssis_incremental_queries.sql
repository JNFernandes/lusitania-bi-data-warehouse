/* =====================================================================
   Lusitânia Stores — Project 1, Step 11
   Incremental extract queries to paste into the SSIS extract package,
   plus a small test to run in SSMS afterwards.

   Each query ends with  WHERE ModifiedDate > ?
   The ? is a PARAMETER: SSIS replaces it with the watermark variable
   before sending the query to SQL Server. In the OLE DB Source editor,
   click "Parameters..." and map Parameter0 to the variable shown.
   ===================================================================== */


/* ---------------------------------------------------------------------
   Execute SQL Task "Get watermarks"   (Connection: DW)
   ResultSet: Single row
   Result Set page:  CustomerWM → User::WM_Customer
                     StoreWM    → User::WM_Store
                     ProductWM  → User::WM_Product
                     SalesWM    → User::WM_Sales
   --------------------------------------------------------------------- */
EXEC etl.usp_Get_Watermarks;


/* ---------------------------------------------------------------------
   Load stg_Customer — OLE DB Source (OLTP)
   Parameters: Parameter0 → User::WM_Customer
   --------------------------------------------------------------------- */
SELECT CustomerID, CustomerCode, FirstName, LastName, Email, Phone,
       City, District, Segment, BirthDate, CreatedDate, ModifiedDate
FROM sales.Customer
WHERE ModifiedDate > ?;


/* ---------------------------------------------------------------------
   Load stg_Store — OLE DB Source (OLTP)
   Parameters: Parameter0 → User::WM_Store
   --------------------------------------------------------------------- */
SELECT StoreID, StoreCode, StoreName, StoreType, City, District, OpenDate, ModifiedDate
FROM sales.Store
WHERE ModifiedDate > ?;


/* ---------------------------------------------------------------------
   Load stg_Product — OLE DB Source (OLTP)
   Parameters: Parameter0 → User::WM_Product
   --------------------------------------------------------------------- */
SELECT ProductID, SKU, ProductName, Brand, CategoryName, DepartmentName,
       ListPrice, IsActive, ModifiedDate
FROM product.vw_ProductExtract
WHERE ModifiedDate > ?;


/* ---------------------------------------------------------------------
   Load stg_Sales — OLE DB Source (OLTP)
   Parameters: Parameter0 → User::WM_Sales
   --------------------------------------------------------------------- */
SELECT OrderID, OrderNumber, OrderDate, StoreCode, CustomerCode, Channel, PaymentMethod,
       LineNumber, SKU, Quantity, UnitPrice, DiscountPct, ModifiedDate
FROM sales.vw_SalesExtract
WHERE ModifiedDate > ?;


/* ---------------------------------------------------------------------
   Execute SQL Task "Update watermarks"  (in Master, LAST step; Connection: DW)
   --------------------------------------------------------------------- */
EXEC etl.usp_Update_Watermarks;



/* =====================================================================
   TEST — run these in SSMS (not in SSIS)
   ===================================================================== */

/* TEST 1: run Master.dtsx with NO changes in the source, then run this.
   Expect: all staging tables EMPTY (nothing new to extract),
           and new 'Succeeded' rows in the log with 0 rows inserted/updated. */
SELECT 'stg.Customer' AS T, COUNT(*) AS Rows FROM LusitaniaDW.stg.Customer
UNION ALL SELECT 'stg.Store',   COUNT(*) FROM LusitaniaDW.stg.Store
UNION ALL SELECT 'stg.Product', COUNT(*) FROM LusitaniaDW.stg.Product
UNION ALL SELECT 'stg.Sales',   COUNT(*) FROM LusitaniaDW.stg.Sales;

SELECT TOP (10) LoadLogID, PackageName, StartTime, EndTime, RowsInserted, RowsUpdated, Status
FROM LusitaniaDW.etl.LoadLog
ORDER BY LoadLogID DESC;


/* TEST 2: make ONE small change in the source, run Master.dtsx again,
   then rerun the two queries above.
   Expect: stg.Customer has 1 row, stg.Sales has 1 row, the rest 0;
           usp_Load_DimCustomer logs 1 inserted + 1 updated (new SCD2 version),
           usp_Load_FactSales logs 1 inserted. */
USE LusitaniaOLTP;

UPDATE sales.Customer
SET Segment = CASE WHEN Segment = N'Gold' THEN N'Silver' ELSE N'Gold' END,
    ModifiedDate = '2026-10-28 10:00'
WHERE CustomerCode = 'C00020';

IF NOT EXISTS (SELECT 1 FROM sales.SalesOrder WHERE OrderNumber = 'LS0040006')
BEGIN
    INSERT INTO sales.SalesOrder (OrderNumber, OrderDate, StoreID, CustomerID, Channel, PaymentMethod, ModifiedDate)
    SELECT 'LS0040006', '2026-10-29 17:45', s.StoreID, c.CustomerID, 'Store', N'Card', '2026-10-29 17:45'
    FROM sales.Store s, sales.Customer c
    WHERE s.StoreCode = 'LIS01' AND c.CustomerCode = 'C00020';

    INSERT INTO sales.SalesOrderLine (OrderID, LineNumber, ProductID, Quantity, UnitPrice, DiscountPct, ModifiedDate)
    SELECT o.OrderID, 1, p.ProductID, 1, p.ListPrice, 0, '2026-10-29 17:45'
    FROM sales.SalesOrder o, product.Product p
    WHERE o.OrderNumber = 'LS0040006' AND p.SKU = 'SKU-00030';
END

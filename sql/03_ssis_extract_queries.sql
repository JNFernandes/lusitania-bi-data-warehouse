/* =====================================================================
   Lusitânia Stores — Project 1, Step 3
   SQL to paste into the SSIS package "Extract_Staging.dtsx".
   This file is NOT meant to be run as a whole in SSMS — copy each block
   into the SSIS task indicated in its header.
   (You CAN run each SELECT in SSMS first to preview what it returns.)
   ===================================================================== */


/* ---------------------------------------------------------------------
   A) Execute SQL Task "Truncate staging"
      Connection: DW (LusitaniaDW)
      Empties staging so every run starts clean (makes the load idempotent).
   --------------------------------------------------------------------- */
TRUNCATE TABLE stg.Customer;
TRUNCATE TABLE stg.Store;
TRUNCATE TABLE stg.Product;
TRUNCATE TABLE stg.Sales;


/* ---------------------------------------------------------------------
   B) Data Flow "Load stg.Customer"
      OLE DB Source → Connection: OLTP → Data access mode: SQL command
      OLE DB Destination → Connection: DW → table: [stg].[Customer]
   --------------------------------------------------------------------- */
SELECT
    CustomerID,
    CustomerCode,
    FirstName,
    LastName,
    Email,
    Phone,
    City,
    District,
    Segment,
    BirthDate,
    CreatedDate,
    ModifiedDate
FROM sales.Customer;


/* ---------------------------------------------------------------------
   C) Data Flow "Load stg.Store"
      OLE DB Source → OLTP, SQL command
      OLE DB Destination → DW, table: [stg].[Store]
   --------------------------------------------------------------------- */
SELECT
    StoreID,
    StoreCode,
    StoreName,
    StoreType,
    City,
    District,
    OpenDate,
    ModifiedDate
FROM sales.Store;


/* ---------------------------------------------------------------------
   D) Data Flow "Load stg.Product"
      Flattens Product + Category + Department into one row per product.
      ModifiedDate = the most recent change across the three tables,
      so a category rename is also picked up by incremental loads later.
      OLE DB Source → OLTP, SQL command
      OLE DB Destination → DW, table: [stg].[Product]
   --------------------------------------------------------------------- */
SELECT
    p.ProductID,
    p.SKU,
    p.ProductName,
    p.Brand,
    c.CategoryName,
    d.DepartmentName,
    p.ListPrice,
    p.IsActive,
    ModifiedDate = (SELECT MAX(v) FROM (VALUES (p.ModifiedDate), (c.ModifiedDate), (d.ModifiedDate)) x (v))
FROM product.Product     p
JOIN product.Category    c ON c.CategoryID   = p.CategoryID
JOIN product.Department  d ON d.DepartmentID = c.DepartmentID;


/* ---------------------------------------------------------------------
   E) Data Flow "Load stg.Sales"
      Flattens SalesOrder + SalesOrderLine into one row per order line,
      and swaps internal IDs for business keys (StoreCode, CustomerCode, SKU),
      which is what the warehouse uses to look up surrogate keys.
      LEFT JOIN on Customer keeps anonymous walk-ins (CustomerCode = NULL).
      OLE DB Source → OLTP, SQL command
      OLE DB Destination → DW, table: [stg].[Sales]
   --------------------------------------------------------------------- */
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
    ModifiedDate = CASE WHEN l.ModifiedDate > o.ModifiedDate THEN l.ModifiedDate ELSE o.ModifiedDate END
FROM sales.SalesOrder          o
JOIN sales.SalesOrderLine      l  ON l.OrderID    = o.OrderID
JOIN sales.Store               s  ON s.StoreID    = o.StoreID
JOIN product.Product           p  ON p.ProductID  = l.ProductID
LEFT JOIN sales.Customer       cu ON cu.CustomerID = o.CustomerID;


/* ---------------------------------------------------------------------
   F) After running the package — verify in SSMS
      Staging row counts should match the source.
   --------------------------------------------------------------------- */
SELECT 'stg.Customer' AS TableName, COUNT(*) AS StagingRows,
       (SELECT COUNT(*) FROM LusitaniaOLTP.sales.Customer) AS SourceRows
FROM LusitaniaDW.stg.Customer
UNION ALL
SELECT 'stg.Store', COUNT(*), (SELECT COUNT(*) FROM LusitaniaOLTP.sales.Store)
FROM LusitaniaDW.stg.Store
UNION ALL
SELECT 'stg.Product', COUNT(*), (SELECT COUNT(*) FROM LusitaniaOLTP.product.Product)
FROM LusitaniaDW.stg.Product
UNION ALL
SELECT 'stg.Sales', COUNT(*), (SELECT COUNT(*) FROM LusitaniaOLTP.sales.SalesOrderLine)
FROM LusitaniaDW.stg.Sales;

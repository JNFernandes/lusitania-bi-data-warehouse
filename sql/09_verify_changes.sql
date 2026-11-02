/* =====================================================================
   Lusitânia Stores — Project 1, Step 9
   Verifies that the changes from step 8 flowed correctly through the
   whole pipeline (source → staging → dimensions → fact).

   Run in SSMS AFTER running Master.dtsx.
   ===================================================================== */

USE LusitaniaDW;
GO

/* ---------------------------------------------------------------------
   1) CUSTOMER VERSIONS
      C00010 and C00011: 2 rows each (old closed, new current)  → SCD2
      C00012: 1 row with the new email                          → SCD1
      C03001: 1 row, ValidFrom 1900-01-01                        → new
   --------------------------------------------------------------------- */
SELECT CustomerSK, CustomerCode, FullName, Email, City, Segment,
       ValidFrom, ValidTo, IsCurrent
FROM dim.Customer
WHERE CustomerCode IN ('C00010', 'C00011', 'C00012', 'C03001')
ORDER BY CustomerCode, ValidFrom;

/* ---------------------------------------------------------------------
   2) PRODUCT VERSIONS
      SKU-00010: 2 rows (old price / new price)
      SKU-00011: 2 rows (old category / new category)
      SKU-00241: 1 row (new product)
   --------------------------------------------------------------------- */
SELECT ProductSK, SKU, ProductName, CategoryName, DepartmentName, ListPrice,
       ValidFrom, ValidTo, IsCurrent
FROM dim.Product
WHERE SKU IN ('SKU-00010', 'SKU-00011', 'SKU-00241')
ORDER BY SKU, ValidFrom;

/* ---------------------------------------------------------------------
   3) STORE — renamed in place, same StoreSK (SCD1)
   --------------------------------------------------------------------- */
SELECT StoreSK, StoreCode, StoreName, UpdatedAt
FROM dim.Store
WHERE StoreCode = 'AVR01';

/* ---------------------------------------------------------------------
   4) THE KEY PROOF — C00010's sales split across their two versions.
      Old sales stay with the OLD city, the October sale goes to the NEW one.
   --------------------------------------------------------------------- */
SELECT
    c.CustomerSK,
    c.City            AS CityOnThatVersion,
    c.ValidFrom,
    c.ValidTo,
    SalesLines        = COUNT(*),
    FirstSale         = MIN(d.FullDate),
    LastSale          = MAX(d.FullDate),
    NetRevenue        = SUM(f.NetAmount)
FROM fact.Sales   f
JOIN dim.Customer c ON c.CustomerSK = f.CustomerSK
JOIN dim.[Date]   d ON d.DateKey    = f.DateKey
WHERE c.CustomerCode = 'C00010'
GROUP BY c.CustomerSK, c.City, c.ValidFrom, c.ValidTo
ORDER BY c.ValidFrom;

/* ---------------------------------------------------------------------
   5) THE NEW ORDERS in the fact, with the keys they were given
   --------------------------------------------------------------------- */
SELECT
    f.OrderNumber, f.OrderLineNumber, d.FullDate,
    f.CustomerSK, c.CustomerCode, c.City AS CustomerCity, c.Segment,
    f.ProductSK,  p.SKU, p.CategoryName, p.ListPrice,
    s.StoreName,
    f.Quantity, f.NetAmount
FROM fact.Sales   f
JOIN dim.[Date]   d ON d.DateKey    = f.DateKey
JOIN dim.Customer c ON c.CustomerSK = f.CustomerSK
JOIN dim.Product  p ON p.ProductSK  = f.ProductSK
JOIN dim.Store    s ON s.StoreSK    = f.StoreSK
WHERE f.OrderNumber >= 'LS0040001'
ORDER BY f.OrderNumber, f.OrderLineNumber;

/* ---------------------------------------------------------------------
   6) RECONCILIATION — source and warehouse must still match exactly
   --------------------------------------------------------------------- */
SELECT
    SourceLines = (SELECT COUNT(*) FROM LusitaniaOLTP.sales.SalesOrderLine),
    FactLines   = (SELECT COUNT(*) FROM fact.Sales),
    SourceNet   = (SELECT CAST(SUM(ROUND(Quantity * UnitPrice, 2)
                                 - ROUND(Quantity * UnitPrice * DiscountPct / 100, 2)) AS DECIMAL(14,2))
                   FROM LusitaniaOLTP.sales.SalesOrderLine),
    FactNet     = (SELECT SUM(NetAmount) FROM fact.Sales);
GO

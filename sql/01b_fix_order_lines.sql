/* =====================================================================
   Lusitânia Stores — Project 1, fix for Step 1
   Rebuilds sales.SalesOrderLine (1 to 4 lines per existing order).
   Use when sales.SalesOrder has rows but sales.SalesOrderLine is empty.
   Safe to rerun: deletes existing lines first.
   ===================================================================== */

USE LusitaniaOLTP;
GO
SET NOCOUNT ON;

DECLARE @ProductCount INT = (SELECT COUNT(*) FROM product.Product);
DECLARE @OrderCount   INT = (SELECT COUNT(*) FROM sales.SalesOrder);

IF @ProductCount = 0 OR @OrderCount = 0
BEGIN
    RAISERROR('Products or orders are missing. Rerun 01_create_lusitania_oltp.sql instead.', 16, 1);
    RETURN;
END

DELETE FROM sales.SalesOrderLine;

-- Numbers 1..4 (max lines per order)
DROP TABLE IF EXISTS #N;
SELECT n INTO #N FROM (VALUES (1), (2), (3), (4)) v (n);

-- Products numbered 1..N so a random number can pick one
DROP TABLE IF EXISTS #Prod;
SELECT rn = ROW_NUMBER() OVER (ORDER BY ProductID), ProductID, ListPrice
INTO #Prod
FROM product.Product;

-- How many lines each order gets.
-- Note: modulo is applied BEFORE ABS, which avoids the rare overflow
-- ABS(-2147483648) can cause with CHECKSUM(NEWID()).
DROP TABLE IF EXISTS #OC;
SELECT OrderID, OrderDate,
       LineCount = 1 + ABS(CHECKSUM(NEWID()) % 4)
INTO #OC
FROM sales.SalesOrder;

-- One row per line with its random choices materialized
DROP TABLE IF EXISTS #L;
SELECT
    oc.OrderID,
    oc.OrderDate,
    LineNumber = CAST(n.n AS SMALLINT),
    rProd = ABS(CHECKSUM(NEWID()) % @ProductCount),
    rQty  = ABS(CHECKSUM(NEWID()) % 100),
    rDisc = ABS(CHECKSUM(NEWID()) % 100)
INTO #L
FROM #OC oc
JOIN #N n ON n.n <= oc.LineCount;

INSERT INTO sales.SalesOrderLine (OrderID, LineNumber, ProductID, Quantity, UnitPrice, DiscountPct, ModifiedDate)
SELECT
    l.OrderID,
    l.LineNumber,
    p.ProductID,
    CASE WHEN l.rQty < 70 THEN 1 WHEN l.rQty < 92 THEN 2 ELSE 3 END,
    p.ListPrice,
    CASE WHEN l.rDisc < 80 THEN 0
         WHEN l.rDisc < 90 THEN 5
         WHEN l.rDisc < 97 THEN 10
         ELSE 20 END,
    l.OrderDate
FROM #L l
JOIN #Prod p ON p.rn = l.rProd + 1
ORDER BY l.OrderID, l.LineNumber;

-- Checks
SELECT 'SalesOrder' AS TableName, COUNT(*) AS Rows FROM sales.SalesOrder
UNION ALL
SELECT 'SalesOrderLine', COUNT(*) FROM sales.SalesOrderLine;

SELECT
    YEAR(o.OrderDate) AS SalesYear,
    o.Channel,
    COUNT(DISTINCT o.OrderID) AS Orders,
    CAST(SUM(l.Quantity * l.UnitPrice * (1 - l.DiscountPct / 100)) AS DECIMAL(14,2)) AS NetRevenue
FROM sales.SalesOrder o
JOIN sales.SalesOrderLine l ON l.OrderID = o.OrderID
GROUP BY YEAR(o.OrderDate), o.Channel
ORDER BY SalesYear, o.Channel;

/* =====================================================================
   Lusitânia Stores — Project 1, Step 8
   Simulates one month of real business activity in the SOURCE system
   (LusitaniaOLTP), so you can watch it flow through the pipeline.

   What changes (all effective October 2026):
     CUSTOMERS
       C00010  moves to another city         → SCD2: new version
       C00011  is upgraded to Gold segment   → SCD2: new version
       C00012  changes email                 → SCD1: overwrite
       C03001  new customer signs up         → new row
     PRODUCTS
       SKU-00010  price +15%                 → SCD2: new version
       SKU-00011  moves to another category  → SCD2: new version
       SKU-00241  new product launched       → new row
     STORES
       AVR01   renamed                       → SCD1: overwrite
     ORDERS
       5 new orders (10-25 Oct), including the customers and
       products above and one anonymous walk-in

   Run ONCE in SSMS (F5). Then run Master.dtsx in Visual Studio,
   then 09_verify_changes.sql in SSMS.
   ===================================================================== */

USE LusitaniaOLTP;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS (SELECT 1 FROM sales.SalesOrder WHERE OrderNumber = 'LS0040001')
BEGIN
    RAISERROR('The changes were already applied. Nothing to do — run Master.dtsx and then 09_verify_changes.sql.', 16, 1);
    RETURN;
END

BEGIN TRANSACTION;

/* ---------------------------------------------------------------------
   CUSTOMERS
   --------------------------------------------------------------------- */

-- C00010 moves (to Faro, or to Braga if already in Faro) — Type 2
UPDATE sales.Customer
SET City         = CASE WHEN City = N'Faro' THEN N'Braga' ELSE N'Faro' END,
    District     = CASE WHEN City = N'Faro' THEN N'Braga' ELSE N'Faro' END,
    ModifiedDate = '2026-10-01 10:00'
WHERE CustomerCode = 'C00010';

-- C00011 upgraded to Gold (to Silver if already Gold) — Type 2
UPDATE sales.Customer
SET Segment      = CASE WHEN Segment = N'Gold' THEN N'Silver' ELSE N'Gold' END,
    ModifiedDate = '2026-10-01 11:00'
WHERE CustomerCode = 'C00011';

-- C00012 changes email — Type 1
UPDATE sales.Customer
SET Email        = N'c00012.new@example.com',
    ModifiedDate = '2026-10-02 09:30'
WHERE CustomerCode = 'C00012';

-- New customer
INSERT INTO sales.Customer
    (CustomerCode, FirstName, LastName, Email, Phone, City, District, Segment, BirthDate, CreatedDate, ModifiedDate)
VALUES
    ('C03001', N'Leonor', N'Teixeira', N'leonor.teixeira@example.com', '912345678',
     N'Aveiro', N'Aveiro', N'Standard', '1995-07-14', '2026-10-03', '2026-10-03 15:00');

/* ---------------------------------------------------------------------
   PRODUCTS
   --------------------------------------------------------------------- */

-- SKU-00010 price increase of 15% — Type 2
UPDATE product.Product
SET ListPrice    = CAST(ListPrice * 1.15 AS DECIMAL(10,2)),
    ModifiedDate = '2026-10-01 08:00'
WHERE SKU = 'SKU-00010';

-- SKU-00011 moves to another category (Audio, or Laptops if already Audio) — Type 2
UPDATE p
SET CategoryID   = c.CategoryID,
    ModifiedDate = '2026-10-01 08:00'
FROM product.Product p
JOIN product.Category cur ON cur.CategoryID = p.CategoryID
JOIN product.Category c   ON c.CategoryName = CASE WHEN cur.CategoryName = N'Audio'
                                                   THEN N'Laptops' ELSE N'Audio' END
WHERE p.SKU = 'SKU-00011';

-- New product
INSERT INTO product.Product (SKU, ProductName, CategoryID, Brand, ListPrice, ModifiedDate)
SELECT 'SKU-00241', N'Audio Atlantica Wireless Earbuds Pro', CategoryID, N'Atlantica', 149.90, '2026-10-04 12:00'
FROM product.Category
WHERE CategoryName = N'Audio';

/* ---------------------------------------------------------------------
   STORES
   --------------------------------------------------------------------- */

-- Aveiro store renamed — Type 1
UPDATE sales.Store
SET StoreName    = N'Lusitânia Aveiro Fórum',
    ModifiedDate = '2026-10-05 09:00'
WHERE StoreCode = 'AVR01';

/* ---------------------------------------------------------------------
   NEW ORDERS (after the changes, so they must link to the NEW versions)
   --------------------------------------------------------------------- */
DECLARE @Orders TABLE (OrderNumber VARCHAR(20), OrderDate DATETIME2(0), StoreCode VARCHAR(10),
                       CustomerCode VARCHAR(10), Channel VARCHAR(10), PaymentMethod NVARCHAR(20));

INSERT INTO @Orders VALUES
    ('LS0040001', '2026-10-10 12:15', 'FAR01', 'C00010', 'Store',  N'Card'),
    ('LS0040002', '2026-10-12 18:40', 'ONL01', 'C00011', 'Online', N'MB Way'),
    ('LS0040003', '2026-10-15 11:05', 'AVR01', 'C03001', 'Store',  N'Card'),
    ('LS0040004', '2026-10-20 16:30', 'AVR01', NULL,     'Store',  N'Cash'),     -- anonymous walk-in
    ('LS0040005', '2026-10-25 10:20', 'ONL01', 'C00012', 'Online', N'Card');

INSERT INTO sales.SalesOrder (OrderNumber, OrderDate, StoreID, CustomerID, Channel, PaymentMethod, ModifiedDate)
SELECT o.OrderNumber, o.OrderDate, s.StoreID, c.CustomerID, o.Channel, o.PaymentMethod, o.OrderDate
FROM @Orders o
JOIN sales.Store s         ON s.StoreCode = o.StoreCode
LEFT JOIN sales.Customer c ON c.CustomerCode = o.CustomerCode;

DECLARE @Lines TABLE (OrderNumber VARCHAR(20), LineNumber SMALLINT, SKU VARCHAR(20), Quantity INT, DiscountPct DECIMAL(5,2));

INSERT INTO @Lines VALUES
    ('LS0040001', 1, 'SKU-00010', 1, 0),     -- product with the NEW price
    ('LS0040001', 2, 'SKU-00241', 2, 0),     -- the NEW product
    ('LS0040002', 1, 'SKU-00011', 1, 5),     -- product in its NEW category
    ('LS0040003', 1, 'SKU-00241', 1, 10),    -- new customer buys new product
    ('LS0040003', 2, 'SKU-00005', 2, 0),
    ('LS0040004', 1, 'SKU-00010', 1, 0),     -- walk-in → Unknown customer
    ('LS0040005', 1, 'SKU-00020', 3, 0);

INSERT INTO sales.SalesOrderLine (OrderID, LineNumber, ProductID, Quantity, UnitPrice, DiscountPct, ModifiedDate)
SELECT so.OrderID, l.LineNumber, p.ProductID, l.Quantity, p.ListPrice, l.DiscountPct, so.OrderDate
FROM @Lines l
JOIN sales.SalesOrder so ON so.OrderNumber = l.OrderNumber
JOIN product.Product  p  ON p.SKU = l.SKU;

COMMIT TRANSACTION;

/* ---------------------------------------------------------------------
   What changed in the source
   --------------------------------------------------------------------- */
SELECT CustomerCode, FirstName, LastName, Email, City, Segment, ModifiedDate
FROM sales.Customer
WHERE CustomerCode IN ('C00010', 'C00011', 'C00012', 'C03001');

SELECT p.SKU, p.ProductName, c.CategoryName, p.ListPrice, p.ModifiedDate
FROM product.Product p
JOIN product.Category c ON c.CategoryID = p.CategoryID
WHERE p.SKU IN ('SKU-00010', 'SKU-00011', 'SKU-00241');

SELECT o.OrderNumber, o.OrderDate, l.LineNumber, l.Quantity, l.UnitPrice
FROM sales.SalesOrder o
JOIN sales.SalesOrderLine l ON l.OrderID = o.OrderID
WHERE o.OrderNumber >= 'LS0040001'
ORDER BY o.OrderNumber, l.LineNumber;
GO

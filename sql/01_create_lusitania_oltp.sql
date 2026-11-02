/* =====================================================================
   Lusitânia Stores — Project 1, Step 1
   Creates the OLTP source database (the shop's operational system)
   and fills it with ~2.75 years of realistic sales data.

   Run in SSMS against your local SQL Server (Developer Edition).
   Safe to rerun: it drops and recreates the database.
   Runtime: a few seconds.
   ===================================================================== */

USE master;
GO

IF DB_ID('LusitaniaOLTP') IS NOT NULL
BEGIN
    ALTER DATABASE LusitaniaOLTP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE LusitaniaOLTP;
END
GO

CREATE DATABASE LusitaniaOLTP;
GO

USE LusitaniaOLTP;
GO

CREATE SCHEMA product;
GO
CREATE SCHEMA sales;
GO

/* ---------------------------------------------------------------------
   1. TABLES (normalized OLTP design)
   --------------------------------------------------------------------- */

CREATE TABLE product.Department (
    DepartmentID    INT IDENTITY(1,1) CONSTRAINT PK_Department PRIMARY KEY,
    DepartmentName  NVARCHAR(50)  NOT NULL CONSTRAINT UQ_Department_Name UNIQUE,
    ModifiedDate    DATETIME2(0)  NOT NULL CONSTRAINT DF_Department_Modified DEFAULT SYSDATETIME()
);

CREATE TABLE product.Category (
    CategoryID      INT IDENTITY(1,1) CONSTRAINT PK_Category PRIMARY KEY,
    CategoryName    NVARCHAR(50)  NOT NULL CONSTRAINT UQ_Category_Name UNIQUE,
    DepartmentID    INT           NOT NULL CONSTRAINT FK_Category_Department REFERENCES product.Department(DepartmentID),
    ModifiedDate    DATETIME2(0)  NOT NULL CONSTRAINT DF_Category_Modified DEFAULT SYSDATETIME()
);

CREATE TABLE product.Product (
    ProductID       INT IDENTITY(1,1) CONSTRAINT PK_Product PRIMARY KEY,
    SKU             VARCHAR(20)   NOT NULL CONSTRAINT UQ_Product_SKU UNIQUE,   -- natural/business key
    ProductName     NVARCHAR(100) NOT NULL,
    CategoryID      INT           NOT NULL CONSTRAINT FK_Product_Category REFERENCES product.Category(CategoryID),
    Brand           NVARCHAR(50)  NOT NULL,
    ListPrice       DECIMAL(10,2) NOT NULL,
    IsActive        BIT           NOT NULL CONSTRAINT DF_Product_IsActive DEFAULT 1,
    ModifiedDate    DATETIME2(0)  NOT NULL CONSTRAINT DF_Product_Modified DEFAULT SYSDATETIME()
);

CREATE TABLE sales.Store (
    StoreID         INT IDENTITY(1,1) CONSTRAINT PK_Store PRIMARY KEY,
    StoreCode       VARCHAR(10)   NOT NULL CONSTRAINT UQ_Store_Code UNIQUE,     -- natural/business key
    StoreName       NVARCHAR(100) NOT NULL,
    StoreType       NVARCHAR(20)  NOT NULL,   -- Street / Mall / Online
    City            NVARCHAR(50)  NOT NULL,
    District        NVARCHAR(50)  NOT NULL,
    OpenDate        DATE          NOT NULL,
    ModifiedDate    DATETIME2(0)  NOT NULL CONSTRAINT DF_Store_Modified DEFAULT SYSDATETIME()
);

CREATE TABLE sales.Customer (
    CustomerID      INT IDENTITY(1,1) CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerCode    VARCHAR(10)   NOT NULL CONSTRAINT UQ_Customer_Code UNIQUE,  -- natural/business key
    FirstName       NVARCHAR(50)  NOT NULL,
    LastName        NVARCHAR(50)  NOT NULL,
    Email           NVARCHAR(120) NOT NULL,
    Phone           VARCHAR(20)   NULL,
    City            NVARCHAR(50)  NOT NULL,
    District        NVARCHAR(50)  NOT NULL,
    Segment         NVARCHAR(20)  NOT NULL,   -- Standard / Silver / Gold (loyalty)
    BirthDate       DATE          NULL,
    CreatedDate     DATE          NOT NULL,
    ModifiedDate    DATETIME2(0)  NOT NULL CONSTRAINT DF_Customer_Modified DEFAULT SYSDATETIME()
);

CREATE TABLE sales.SalesOrder (
    OrderID         INT IDENTITY(1,1) CONSTRAINT PK_SalesOrder PRIMARY KEY,
    OrderNumber     VARCHAR(20)   NOT NULL CONSTRAINT UQ_SalesOrder_Number UNIQUE,
    OrderDate       DATETIME2(0)  NOT NULL,
    StoreID         INT           NOT NULL CONSTRAINT FK_SalesOrder_Store REFERENCES sales.Store(StoreID),
    CustomerID      INT           NULL     CONSTRAINT FK_SalesOrder_Customer REFERENCES sales.Customer(CustomerID), -- NULL = anonymous walk-in
    Channel         VARCHAR(10)   NOT NULL,   -- Store / Online
    PaymentMethod   NVARCHAR(20)  NOT NULL,
    ModifiedDate    DATETIME2(0)  NOT NULL CONSTRAINT DF_SalesOrder_Modified DEFAULT SYSDATETIME()
);

CREATE TABLE sales.SalesOrderLine (
    OrderLineID     INT IDENTITY(1,1) CONSTRAINT PK_SalesOrderLine PRIMARY KEY,
    OrderID         INT           NOT NULL CONSTRAINT FK_SalesOrderLine_Order REFERENCES sales.SalesOrder(OrderID),
    LineNumber      SMALLINT      NOT NULL,
    ProductID       INT           NOT NULL CONSTRAINT FK_SalesOrderLine_Product REFERENCES product.Product(ProductID),
    Quantity        INT           NOT NULL CONSTRAINT CK_SalesOrderLine_Qty CHECK (Quantity > 0),
    UnitPrice       DECIMAL(10,2) NOT NULL,   -- price actually charged at the time of sale
    DiscountPct     DECIMAL(5,2)  NOT NULL CONSTRAINT DF_SalesOrderLine_Disc DEFAULT 0,
    ModifiedDate    DATETIME2(0)  NOT NULL CONSTRAINT DF_SalesOrderLine_Modified DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_SalesOrderLine UNIQUE (OrderID, LineNumber)
);

-- Indexes that support incremental (watermark) extraction later on
CREATE INDEX IX_SalesOrder_ModifiedDate     ON sales.SalesOrder (ModifiedDate);
CREATE INDEX IX_SalesOrderLine_ModifiedDate ON sales.SalesOrderLine (ModifiedDate);
CREATE INDEX IX_Customer_ModifiedDate       ON sales.Customer (ModifiedDate);
CREATE INDEX IX_Product_ModifiedDate        ON product.Product (ModifiedDate);
GO

/* ---------------------------------------------------------------------
   2. HELPER: numbers table (temp tables survive GO in the same session)
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #N;
SELECT TOP (100000) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
INTO #N
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

/* ---------------------------------------------------------------------
   3. REFERENCE DATA: departments, categories, products, stores
   --------------------------------------------------------------------- */
INSERT INTO product.Department (DepartmentName)
VALUES (N'Electronics'), (N'Home & Kitchen'), (N'Fashion'), (N'Sports & Outdoors');

INSERT INTO product.Category (CategoryName, DepartmentID)
SELECT c.CategoryName, d.DepartmentID
FROM (VALUES
        (N'Smartphones',      N'Electronics'),
        (N'Laptops',          N'Electronics'),
        (N'Audio',            N'Electronics'),
        (N'Cookware',         N'Home & Kitchen'),
        (N'Bedding',          N'Home & Kitchen'),
        (N'Small Appliances', N'Home & Kitchen'),
        (N'Menswear',         N'Fashion'),
        (N'Womenswear',       N'Fashion'),
        (N'Footwear',         N'Fashion'),
        (N'Fitness',          N'Sports & Outdoors'),
        (N'Cycling',          N'Sports & Outdoors'),
        (N'Camping',          N'Sports & Outdoors')
     ) c (CategoryName, DepartmentName)
JOIN product.Department d ON d.DepartmentName = c.DepartmentName
ORDER BY d.DepartmentID, c.CategoryName;

-- 240 products: 20 per category, 6 brands, price varies around a category base price
DROP TABLE IF EXISTS #ProdRand;
SELECT n.n, rPrice = ABS(CHECKSUM(NEWID()) % 150)
INTO #ProdRand
FROM #N n
WHERE n.n <= 240;

INSERT INTO product.Product (SKU, ProductName, CategoryID, Brand, ListPrice)
SELECT
    'SKU-' + RIGHT('00000' + CAST(r.n AS VARCHAR(5)), 5),
    c.CategoryName + N' ' + b.Brand + N' Model ' + CAST(r.n AS NVARCHAR(5)),
    c.CategoryID,
    b.Brand,
    CAST(bp.BasePrice * (0.5 + r.rPrice / 100.0) AS DECIMAL(10,2))
FROM #ProdRand r
JOIN (SELECT CategoryID, CategoryName,
             rn = ROW_NUMBER() OVER (ORDER BY CategoryID)
      FROM product.Category) c
  ON c.rn = ((r.n - 1) % 12) + 1
JOIN (VALUES (N'Smartphones', 450), (N'Laptops', 900), (N'Audio', 120),
             (N'Cookware', 60), (N'Bedding', 50), (N'Small Appliances', 80),
             (N'Menswear', 40), (N'Womenswear', 45), (N'Footwear', 70),
             (N'Fitness', 55), (N'Cycling', 300), (N'Camping', 90)
     ) bp (CategoryName, BasePrice)
  ON bp.CategoryName = c.CategoryName
JOIN (VALUES (0, N'Atlantica'), (1, N'Douro'), (2, N'Minho & Co'),
             (3, N'Tejo'), (4, N'Aveiro Labs'), (5, N'Serra')
     ) b (k, Brand)
  ON b.k = r.n % 6
ORDER BY r.n;

INSERT INTO sales.Store (StoreCode, StoreName, StoreType, City, District, OpenDate)
VALUES
    ('LIS01', N'Lusitânia Lisboa Centro',      N'Mall',   N'Lisboa',     N'Lisboa',  '2015-03-01'),
    ('LIS02', N'Lusitânia Lisboa Baixa',       N'Street', N'Lisboa',     N'Lisboa',  '2018-06-15'),
    ('POR01', N'Lusitânia Porto Baixa',        N'Street', N'Porto',      N'Porto',   '2016-09-10'),
    ('POR02', N'Lusitânia Matosinhos',         N'Mall',   N'Matosinhos', N'Porto',   '2019-04-01'),
    ('BRG01', N'Lusitânia Braga',              N'Mall',   N'Braga',      N'Braga',   '2020-02-20'),
    ('COI01', N'Lusitânia Coimbra',            N'Street', N'Coimbra',    N'Coimbra', '2017-11-05'),
    ('FAR01', N'Lusitânia Faro',               N'Mall',   N'Faro',       N'Faro',    '2021-05-12'),
    ('AVR01', N'Lusitânia Aveiro',             N'Street', N'Aveiro',     N'Aveiro',  '2022-03-08'),
    ('ONL01', N'Lusitânia Online',             N'Online', N'Lisboa',     N'Lisboa',  '2019-01-01');

/* ---------------------------------------------------------------------
   4. CUSTOMERS (3,000)
   Random values are materialized first, so NEWID() is evaluated
   exactly once per row (avoids optimizer re-evaluation surprises).
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #FirstNames;
DROP TABLE IF EXISTS #LastNames;
DROP TABLE IF EXISTS #Cities;

SELECT k, Name INTO #FirstNames FROM (VALUES
    (0, N'Ana'), (1, N'João'), (2, N'Maria'), (3, N'Pedro'), (4, N'Inês'),
    (5, N'Tiago'), (6, N'Beatriz'), (7, N'Rui'), (8, N'Sofia'), (9, N'Miguel'),
    (10, N'Catarina'), (11, N'Diogo'), (12, N'Mariana'), (13, N'Nuno'), (14, N'Rita'),
    (15, N'André'), (16, N'Joana'), (17, N'Bruno'), (18, N'Carolina'), (19, N'Ricardo')
) v (k, Name);

SELECT k, Name INTO #LastNames FROM (VALUES
    (0, N'Silva'), (1, N'Santos'), (2, N'Ferreira'), (3, N'Pereira'), (4, N'Oliveira'),
    (5, N'Costa'), (6, N'Rodrigues'), (7, N'Martins'), (8, N'Jesus'), (9, N'Sousa'),
    (10, N'Fernandes'), (11, N'Gonçalves'), (12, N'Gomes'), (13, N'Lopes'), (14, N'Marques'),
    (15, N'Alves'), (16, N'Almeida'), (17, N'Ribeiro'), (18, N'Pinto'), (19, N'Carvalho')
) v (k, Name);

SELECT k, City, District INTO #Cities FROM (VALUES
    (0, N'Lisboa', N'Lisboa'), (1, N'Porto', N'Porto'), (2, N'Braga', N'Braga'),
    (3, N'Coimbra', N'Coimbra'), (4, N'Faro', N'Faro'), (5, N'Aveiro', N'Aveiro'),
    (6, N'Setúbal', N'Setúbal'), (7, N'Viseu', N'Viseu'), (8, N'Leiria', N'Leiria'),
    (9, N'Évora', N'Évora')
) v (k, City, District);

DROP TABLE IF EXISTS #C;
SELECT TOP (3000)
    n.n,
    rFirst   = ABS(CHECKSUM(NEWID()) % 20),
    rLast    = ABS(CHECKSUM(NEWID()) % 20),
    rCity    = ABS(CHECKSUM(NEWID()) % 10),
    rSeg     = ABS(CHECKSUM(NEWID()) % 100),
    rAge     = ABS(CHECKSUM(NEWID()) % (55 * 365)),
    rCreated = ABS(CHECKSUM(NEWID()) % 730),
    rPhone   = ABS(CHECKSUM(NEWID()) % 100000000)
INTO #C
FROM #N n
ORDER BY n.n;

INSERT INTO sales.Customer
    (CustomerCode, FirstName, LastName, Email, Phone, City, District, Segment, BirthDate, CreatedDate, ModifiedDate)
SELECT
    'C' + RIGHT('00000' + CAST(c.n AS VARCHAR(5)), 5),
    f.Name,
    l.Name,
    TRANSLATE(LOWER(f.Name + N'.' + l.Name), N'ãçéêíóõúâ', N'aceeiooua')
        + CAST(c.n AS NVARCHAR(5)) + N'@example.com',
    '9' + RIGHT('00000000' + CAST(c.rPhone AS VARCHAR(8)), 8),
    ci.City,
    ci.District,
    CASE WHEN c.rSeg < 60 THEN N'Standard'
         WHEN c.rSeg < 90 THEN N'Silver'
         ELSE N'Gold' END,
    DATEADD(DAY, -(18 * 365 + c.rAge), CAST('2026-01-01' AS DATE)),
    DATEADD(DAY, c.rCreated, CAST('2022-01-01' AS DATE)),
    DATEADD(DAY, c.rCreated, CAST('2022-01-01' AS DATETIME2(0)))
FROM #C c
JOIN #FirstNames f ON f.k  = c.rFirst
JOIN #LastNames  l ON l.k  = c.rLast
JOIN #Cities     ci ON ci.k = c.rCity
ORDER BY c.n;

/* ---------------------------------------------------------------------
   5. ORDERS (40,000) between 2024-01-01 and 2026-09-30
   - 25% online (always with a known customer)
   - 75% in physical stores; 30% of those are anonymous walk-ins (NULL customer)
   --------------------------------------------------------------------- */
DECLARE @StartDate     DATE = '2024-01-01';
DECLARE @Days          INT  = DATEDIFF(DAY, '2024-01-01', '2026-09-30') + 1;
DECLARE @OnlineStoreID INT  = (SELECT StoreID FROM sales.Store WHERE StoreCode = 'ONL01');
DECLARE @CustomerCount INT  = (SELECT COUNT(*) FROM sales.Customer);

DROP TABLE IF EXISTS #PS;
SELECT rn = ROW_NUMBER() OVER (ORDER BY StoreID), StoreID
INTO #PS
FROM sales.Store
WHERE StoreType <> N'Online';

DECLARE @PhysicalStores INT = (SELECT COUNT(*) FROM #PS);

DROP TABLE IF EXISTS #O;
SELECT TOP (40000)
    rDay    = ABS(CHECKSUM(NEWID()) % @Days),
    rMin    = ABS(CHECKSUM(NEWID()) % 720),          -- 09:00 to 21:00
    rChan   = ABS(CHECKSUM(NEWID()) % 100),
    rStore  = ABS(CHECKSUM(NEWID()) % @PhysicalStores),
    rAnon   = ABS(CHECKSUM(NEWID()) % 100),
    rCustId = ABS(CHECKSUM(NEWID()) % @CustomerCount),
    rPay    = ABS(CHECKSUM(NEWID()) % 4)
INTO #O
FROM #N;

DROP TABLE IF EXISTS #Cust;
SELECT rn = ROW_NUMBER() OVER (ORDER BY CustomerID), CustomerID
INTO #Cust
FROM sales.Customer;

INSERT INTO sales.SalesOrder (OrderNumber, OrderDate, StoreID, CustomerID, Channel, PaymentMethod, ModifiedDate)
SELECT
    'LS' + RIGHT('0000000' + CAST(ROW_NUMBER() OVER (ORDER BY x.OrderDate) AS VARCHAR(7)), 7),
    x.OrderDate, x.StoreID, x.CustomerID, x.Channel, x.PaymentMethod, x.OrderDate
FROM (
    SELECT
        OrderDate     = DATEADD(MINUTE, 540 + o.rMin,
                                CAST(DATEADD(DAY, o.rDay, @StartDate) AS DATETIME2(0))),
        StoreID       = CASE WHEN o.rChan < 25 THEN @OnlineStoreID ELSE ps.StoreID END,
        CustomerID    = CASE WHEN o.rChan >= 25 AND o.rAnon < 30 THEN NULL ELSE cu.CustomerID END,
        Channel       = CASE WHEN o.rChan < 25 THEN 'Online' ELSE 'Store' END,
        PaymentMethod = CASE WHEN o.rChan < 25 AND pm.PaymentMethod = N'Cash' THEN N'Card'
                             ELSE pm.PaymentMethod END
    FROM #O o
    JOIN #PS   ps ON ps.rn = o.rStore + 1
    JOIN #Cust cu ON cu.rn = o.rCustId + 1
    JOIN (VALUES (0, N'Card'), (1, N'Cash'), (2, N'MB Way'), (3, N'Multibanco')) pm (k, PaymentMethod)
      ON pm.k = o.rPay
) x
ORDER BY x.OrderDate;

/* ---------------------------------------------------------------------
   6. ORDER LINES (1 to 4 per order)
   --------------------------------------------------------------------- */
DECLARE @ProductCount INT = (SELECT COUNT(*) FROM product.Product);

DROP TABLE IF EXISTS #OC;
SELECT OrderID, OrderDate, LineCount = 1 + ABS(CHECKSUM(NEWID()) % 4)
INTO #OC
FROM sales.SalesOrder;

DROP TABLE IF EXISTS #Prod;
SELECT rn = ROW_NUMBER() OVER (ORDER BY ProductID), ProductID, ListPrice
INTO #Prod
FROM product.Product;

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
GO

/* ---------------------------------------------------------------------
   7. QUICK CHECKS
   --------------------------------------------------------------------- */
SELECT 'Departments' AS TableName, COUNT(*) AS Rows FROM product.Department
UNION ALL SELECT 'Categories',  COUNT(*) FROM product.Category
UNION ALL SELECT 'Products',    COUNT(*) FROM product.Product
UNION ALL SELECT 'Stores',      COUNT(*) FROM sales.Store
UNION ALL SELECT 'Customers',   COUNT(*) FROM sales.Customer
UNION ALL SELECT 'Orders',      COUNT(*) FROM sales.SalesOrder
UNION ALL SELECT 'Order lines', COUNT(*) FROM sales.SalesOrderLine;

-- Net revenue per year and channel (sanity check of the generated data)
SELECT
    YEAR(o.OrderDate) AS SalesYear,
    o.Channel,
    COUNT(DISTINCT o.OrderID) AS Orders,
    CAST(SUM(l.Quantity * l.UnitPrice * (1 - l.DiscountPct / 100)) AS DECIMAL(14,2)) AS NetRevenue
FROM sales.SalesOrder o
JOIN sales.SalesOrderLine l ON l.OrderID = o.OrderID
GROUP BY YEAR(o.OrderDate), o.Channel
ORDER BY SalesYear, o.Channel;

-- Share of anonymous (NULL customer) orders — these will map to the "Unknown" member later
SELECT
    SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS AnonymousOrders,
    COUNT(*) AS TotalOrders
FROM sales.SalesOrder;

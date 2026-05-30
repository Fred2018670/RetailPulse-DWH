-- 1. Create the Analytics Warehouse Database
CREATE DATABASE RetailPulse_DWH;
GO

USE RetailPulse_DWH;
GO

-- 2. Create DimDate (Time-Based Reporting)
CREATE TABLE DimDate (
    DateKey INT PRIMARY KEY, -- Format: YYYYMMDD
    FullDate DATE NOT NULL,
    DayNumber INT NOT NULL,
    DayName VARCHAR(10) NOT NULL,
    WeekNumber INT NOT NULL,
    MonthNumber INT NOT NULL,
    MonthName VARCHAR(10) NOT NULL,
    Quarter INT NOT NULL,
    Year INT NOT NULL,
    FiscalMonth INT NOT NULL,
    FiscalQuarter INT NOT NULL,
    FiscalYear INT NOT NULL,
    IsWeekend BIT NOT NULL
);

-- 3. Create DimLocation (Geography Master)
CREATE TABLE DimLocation (
    LocationKey INT IDENTITY(1,1) PRIMARY KEY,
    City VARCHAR(100) NOT NULL,
    Region VARCHAR(100) NOT NULL,
    Country VARCHAR(100) NOT NULL
);

-- 4. Create DimCustomer (With SCD Type 2 tracking for Freelance Tier Analytics)
CREATE TABLE DimCustomer (
    CustomerKey INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL, -- Operational ERP ID
    CustomerName VARCHAR(150) NOT NULL,
    Gender VARCHAR(20) NOT NULL,
    AgeGroup VARCHAR(20) NOT NULL,
    LocationKey INT FOREIGN KEY REFERENCES DimLocation(LocationKey),
    SignupDate DATE NOT NULL,
    CustomerSegment VARCHAR(20) NOT NULL, -- Bronze, Silver, Gold, Platinum
    -- SCD Type 2 Fields
    ValidFrom DATE NOT NULL,
    ValidTo DATE NULL,
    IsCurrent BIT NOT NULL DEFAULT 1
);

-- 5. Create DimProduct (Product Master)
CREATE TABLE DimProduct (
    ProductKey INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    ProductName VARCHAR(150) NOT NULL,
    Brand VARCHAR(100) NOT NULL,
    Category VARCHAR(100) NOT NULL,
    SubCategory VARCHAR(100) NOT NULL,
    StandardCost DECIMAL(18,2) NOT NULL,
    SellingPrice DECIMAL(18,2) NOT NULL
);

-- 6. Create DimCampaign (Marketing Attribution)
CREATE TABLE DimCampaign (
    CampaignKey INT IDENTITY(1,1) PRIMARY KEY,
    CampaignName VARCHAR(150) NOT NULL,
    Channel VARCHAR(50) NOT NULL, -- Google Ads, Facebook Ads, Organic, etc.
    CampaignCost DECIMAL(18,2) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL
);

-- 7. Create DimStatus (Transactional Status)
CREATE TABLE DimStatus (
    StatusKey INT IDENTITY(1,1) PRIMARY KEY,
    StatusName VARCHAR(50) NOT NULL -- Completed, Returned, Cancelled, Pending
);

-- 8. Create FactSales (Core Transactional Analytics Grain: 1 Row Per Order Line Item)
CREATE TABLE FactSales (
    SalesFactKey BIGINT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    OrderLineNumber INT NOT NULL,
    DateKey INT FOREIGN KEY REFERENCES DimDate(DateKey),
    CustomerKey INT FOREIGN KEY REFERENCES DimCustomer(CustomerKey),
    ProductKey INT FOREIGN KEY REFERENCES DimProduct(ProductKey),
    LocationKey INT FOREIGN KEY REFERENCES DimLocation(LocationKey),
    CampaignKey INT FOREIGN KEY REFERENCES DimCampaign(CampaignKey),
    StatusKey INT FOREIGN KEY REFERENCES DimStatus(StatusKey),
    OrderSource VARCHAR(50) NOT NULL, -- Website, Mobile App, Marketplace
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL,
    DiscountAmount DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    TaxAmount DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    ShippingCost DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    ProductCost DECIMAL(18,2) NOT NULL, -- Snapshot of cost at time of sale
    GrossRevenue AS (Quantity * UnitPrice),
    NetRevenue AS ((Quantity * UnitPrice) - DiscountAmount),
    Profit AS (((Quantity * UnitPrice) - DiscountAmount) - (Quantity * ProductCost))
);

-- 9. Create FactInventory (Daily Snapshot Analytics)
CREATE TABLE FactInventory (
    InventoryFactKey BIGINT IDENTITY(1,1) PRIMARY KEY,
    DateKey INT FOREIGN KEY REFERENCES DimDate(DateKey),
    ProductKey INT FOREIGN KEY REFERENCES DimProduct(ProductKey),
    OpeningStock INT NOT NULL,
    StockReceived INT NOT NULL DEFAULT 0,
    StockSold INT NOT NULL DEFAULT 0,
    StockReturned INT NOT NULL DEFAULT 0,
    ClosingStock INT NOT NULL,
    InventoryValue AS (ClosingStock * 1.0) -- Calculated later relative to DimProduct cost in views
);

-- 10. Create FactMarketing (Performance & Cost Analysis)
CREATE TABLE FactMarketing (
    MarketingFactKey INT IDENTITY(1,1) PRIMARY KEY,
    DateKey INT FOREIGN KEY REFERENCES DimDate(DateKey),
    CampaignKey INT FOREIGN KEY REFERENCES DimCampaign(CampaignKey),
    Impressions INT NOT NULL DEFAULT 0,
    Clicks INT NOT NULL DEFAULT 0,
    Conversions INT NOT NULL DEFAULT 0,
    RevenueGenerated DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    Cost DECIMAL(18,2) NOT NULL DEFAULT 0.00
);

USE RetailPulse_DWH;
GO

-- 1. SEED DIMDATE (Looping mechanism for 5 years: 2022 to 2026)
SET NOCOUNT ON;
DECLARE @StartDate DATE = '2022-01-01';
DECLARE @EndDate DATE = '2026-12-31';
DECLARE @CurrentDate DATE = @StartDate;

WHILE @CurrentDate <= @EndDate
BEGIN
    INSERT INTO DimDate (
        DateKey, FullDate, DayNumber, DayName, WeekNumber, 
        MonthNumber, MonthName, Quarter, Year, 
        FiscalMonth, FiscalQuarter, FiscalYear, IsWeekend
    )
    VALUES (
        CAST(FORMAT(@CurrentDate, 'yyyyMMdd') AS INT),
        @CurrentDate,
        DATEPART(DAY, @CurrentDate),
        DATENAME(WEEKDAY, @CurrentDate),
        DATEPART(WEEK, @CurrentDate),
        DATEPART(MONTH, @CurrentDate),
        DATENAME(MONTH, @CurrentDate),
        DATEPART(QUARTER, @CurrentDate),
        DATEPART(YEAR, @CurrentDate),
        -- Assuming a standard standard fiscal year starting in July (Common E-Commerce setup)
        CASE WHEN DATEPART(MONTH, @CurrentDate) >= 7 THEN DATEPART(MONTH, @CurrentDate) - 6 ELSE DATEPART(MONTH, @CurrentDate) + 6 END,
        CASE WHEN DATEPART(MONTH, @CurrentDate) BETWEEN 7 AND 9 THEN 1
             WHEN DATEPART(MONTH, @CurrentDate) BETWEEN 10 AND 12 THEN 2
             WHEN DATEPART(MONTH, @CurrentDate) BETWEEN 1 AND 3 THEN 3
             ELSE 4 END,
        CASE WHEN DATEPART(MONTH, @CurrentDate) >= 7 THEN DATEPART(YEAR, @CurrentDate) ELSE DATEPART(YEAR, @CurrentDate) - 1 END,
        CASE WHEN DATEPART(WEEKDAY, @CurrentDate) IN (1, 7) THEN 1 ELSE 0 END
    );
    SET @CurrentDate = DATEADD(DAY, 1, @CurrentDate);
END;
GO

-- 2. SEED DIMLOCATION (Multi-country e-commerce footprint)
INSERT INTO DimLocation (City, Region, Country) VALUES
('Nairobi', 'Nairobi County', 'Kenya'),
('Mombasa', 'Coast Region', 'Kenya'),
('Kisumu', 'Nyanza Region', 'Kenya'),
('Kampala', 'Central Region', 'Uganda'),
('Entebbe', 'Wakiso', 'Uganda'),
('Dar es Salaam', 'Kinondoni', 'Tanzania'),
('Arusha', 'Northern Highlands', 'Tanzania'),
('Kigali', 'Nyabugogo', 'Rwanda');
GO

-- 3. SEED DIMSTATUS
INSERT INTO DimStatus (StatusName) VALUES 
('Completed'), 
('Returned'), 
('Cancelled'), 
('Pending'), 
('Refunded');
GO

-- 4. SEED DIMPRODUCT (Sample Catalog with competitive pricing structures)
INSERT INTO DimProduct (ProductID, ProductName, Brand, Category, SubCategory, StandardCost, SellingPrice) VALUES
(101, 'Pulse Pro Wireless Headphones', 'SonicWave', 'Electronics', 'Audio', 45.00, 89.99),
(102, 'Apex Smartwatch v4', 'KronoTech', 'Electronics', 'Wearables', 120.00, 249.99),
(103, 'UltraFit Running Shoes', 'AeroPace', 'Sports', 'Footwear', 35.00, 79.99),
(104, 'HydraFlask 1L', 'EcoVessel', 'Sports', 'Accessories', 8.00, 24.99),
(105, 'Revitalize Facial Serum', 'GlowSkin', 'Beauty', 'Skincare', 12.00, 39.99),
(106, 'ErgoComfort Office Chair', 'ModLiving', 'Home', 'Furniture', 85.00, 189.99),
(107, 'Classic Cotton Hoodie', 'ThreadCo', 'Fashion', 'Apparel', 14.00, 34.99),
(108, 'Pro-Blend Blender 900W', 'NutriMax', 'Home', 'Appliances', 30.00, 69.99);
GO

-- 5. SEED DIMCAMPAIGN
INSERT INTO DimCampaign (CampaignName, Channel, CampaignCost, StartDate, EndDate) VALUES
('Black Friday Mega Sale', 'Google Ads', 5000.00, '2025-11-20', '2025-11-30'),
('New Year New You', 'Facebook Ads', 3500.00, '2026-01-01', '2026-01-15'),
('Summer Fashion Launch', 'Instagram', 2800.00, '2025-06-01', '2025-06-15'),
('Tech Upgrade Campaign', 'Email', 450.00, '2025-09-10', '2025-09-17'),
('Organic Tech Reviews', 'Organic Search', 0.00, '2024-01-01', '2026-12-31'),
('Lifestyle Influencer Push', 'Affiliate', 1200.00, '2025-03-01', '2025-03-31');
GO

-- 6. SEED DIMCUSTOMER (Generating base customer records with SCD Type 2 Active dates)
DECLARE @Counter INT = 1;
DECLARE @RandomLocation INT;
DECLARE @RandomSegment VARCHAR(20);
DECLARE @SignupDate DATE;

WHILE @Counter <= 1000 -- Generating initial batch of 1000 customers
BEGIN
    SET @RandomLocation = (SELECT TOP 1 LocationKey FROM DimLocation ORDER BY NEWID());
    SET @RandomSegment = CASE WHEN @Counter % 10 = 0 THEN 'Platinum'
                              WHEN @Counter % 5 = 0 THEN 'Gold'
                              WHEN @Counter % 3 = 0 THEN 'Silver'
                              ELSE 'Bronze' END;
    SET @SignupDate = DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 1000, '2026-05-01');

    INSERT INTO DimCustomer (CustomerID, CustomerName, Gender, AgeGroup, LocationKey, SignupDate, CustomerSegment, ValidFrom, ValidTo, IsCurrent)
    VALUES (
        2000 + @Counter,
        'Customer_Name_' + CAST(@Counter AS VARCHAR(10)),
        CASE WHEN @Counter % 2 = 0 THEN 'Female' ELSE 'Male' END,
        CASE WHEN @Counter % 4 = 0 THEN '18-24' WHEN @Counter % 4 = 1 THEN '25-34' WHEN @Counter % 4 = 2 THEN '35-54' ELSE '55+' END,
        @RandomLocation,
        @SignupDate,
        @RandomSegment,
        @SignupDate,
        NULL,
        1
    );
    SET @Counter = @Counter + 1;
END;
GO

-- 7. SEED FACTSALES 
-- Using a multi-row generation technique to simulate deep transaction histories efficiently
INSERT INTO FactSales (OrderID, OrderLineNumber, DateKey, CustomerKey, ProductKey, LocationKey, CampaignKey, StatusKey, OrderSource, Quantity, UnitPrice, DiscountAmount, TaxAmount, ShippingCost, ProductCost)
SELECT TOP 55000
    ABS(CHECKSUM(NEWID())) % 15000 + 100000 AS OrderID,
    (ROW_NUMBER() OVER(PARTITION BY ABS(CHECKSUM(NEWID())) % 15000 + 100000 ORDER BY (SELECT NULL))) AS OrderLineNumber,
    d.DateKey,
    c.CustomerKey,
    p.ProductKey,
    c.LocationKey,
    (SELECT TOP 1 CampaignKey FROM DimCampaign ORDER BY NEWID()) AS CampaignKey,
    CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 25 = 0 THEN 2 -- Returned
         WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 40 = 0 THEN 3 -- Cancelled
         ELSE 1 END AS StatusKey, -- Completed
    CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 3 = 0 THEN 'Website'
         WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 3 = 1 THEN 'Mobile App'
         ELSE 'Marketplace' END AS OrderSource,
    (ABS(CHECKSUM(NEWID())) % 3) + 1 AS Quantity,
    p.SellingPrice,
    CASE WHEN ABS(CHECKSUM(NEWID())) % 5 = 0 THEN ROUND((p.SellingPrice * 0.1), 2) ELSE 0.00 END AS DiscountAmount,
    ROUND((p.SellingPrice * 0.16), 2) AS TaxAmount, -- 16% standard VAT projection
    CASE WHEN p.SellingPrice > 100 THEN 0.00 ELSE 4.99 END AS ShippingCost,
    p.StandardCost
FROM DimDate d
CROSS JOIN DimProduct p
CROSS JOIN DimCustomer c
WHERE d.Year BETWEEN 2024 AND 2026 
  AND d.DayNumber % 4 = 0 -- Filtered to distribute across density metrics organically
ORDER BY NEWID();
GO

-- we drop fact sales to include different tax rate and currency

USE RetailPulse_DWH;
GO

-- Drop the existing FactSales table to update columns cleanly
DROP TABLE IF EXISTS FactSales;
GO

CREATE TABLE FactSales (
    SalesFactKey BIGINT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    OrderLineNumber INT NOT NULL,
    DateKey INT FOREIGN KEY REFERENCES DimDate(DateKey),
    CustomerKey INT FOREIGN KEY REFERENCES DimCustomer(CustomerKey),
    ProductKey INT FOREIGN KEY REFERENCES DimProduct(ProductKey),
    LocationKey INT FOREIGN KEY REFERENCES DimLocation(LocationKey),
    CampaignKey INT FOREIGN KEY REFERENCES DimCampaign(CampaignKey),
    StatusKey INT FOREIGN KEY REFERENCES DimStatus(StatusKey),
    OrderSource VARCHAR(50) NOT NULL, -- Website, Mobile App, Marketplace
    Quantity INT NOT NULL,
    
    -- Multi-Currency Infrastructure
    LocalCurrency VARCHAR(3) NOT NULL,    -- KES, TZS, UGX, RWF
    ExchangeRateToUSD DECIMAL(18,4) NOT NULL, -- Conversion factor to a unified group currency
    
    -- Financial fields (Stored in Local Currency)
    UnitPriceLocal DECIMAL(18,2) NOT NULL,
    DiscountAmountLocal DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    TaxAmountLocal DECIMAL(18,2) NOT NULL,
    ProductCostLocal DECIMAL(18,2) NOT NULL,
    
    -- Unified Reporting Columns (Calculated automatically via computed columns for the Warehouse)
    GrossRevenueUSD AS ROUND(((Quantity * UnitPriceLocal) * ExchangeRateToUSD), 2),
    NetRevenueUSD AS ROUND((((Quantity * UnitPriceLocal) - DiscountAmountLocal) * ExchangeRateToUSD), 2),
    TaxUSD AS ROUND((TaxAmountLocal * ExchangeRateToUSD), 2),
    ProfitUSD AS ROUND(((((Quantity * UnitPriceLocal) - DiscountAmountLocal) - (Quantity * ProductCostLocal)) * ExchangeRateToUSD), 2)
);
GO

-- then reseed

USE RetailPulse_DWH;
GO

-- Clear out any existing data to ensure consistency
TRUNCATE TABLE FactSales;
GO

INSERT INTO FactSales (OrderID, OrderLineNumber, DateKey, CustomerKey, ProductKey, LocationKey, CampaignKey, StatusKey, OrderSource, Quantity, UnitPriceLocal, DiscountAmountLocal, TaxAmountLocal, ProductCostLocal, LocalCurrency, ExchangeRateToUSD)
SELECT TOP 55000
    ABS(CHECKSUM(NEWID())) % 15000 + 100000 AS OrderID,
    (ROW_NUMBER() OVER(PARTITION BY ABS(CHECKSUM(NEWID())) % 15000 + 100000 ORDER BY (SELECT NULL))) AS OrderLineNumber,
    d.DateKey,
    c.CustomerKey,
    p.ProductKey,
    loc.LocationKey,
    (SELECT TOP 1 CampaignKey FROM DimCampaign ORDER BY NEWID()) AS CampaignKey,
    CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 25 = 0 THEN 2 -- Returned
         WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 40 = 0 THEN 3 -- Cancelled
         ELSE 1 END AS StatusKey,
    CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 3 = 0 THEN 'Website'
         WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 3 = 1 THEN 'Mobile App'
         ELSE 'Marketplace' END AS OrderSource,
    (ABS(CHECKSUM(NEWID())) % 3) + 1 AS Quantity,
    
    -- Scale base selling price to simulate local currency values realistic to East Africa
    CASE WHEN loc.Country = 'Kenya' THEN p.SellingPrice * 130.00
         WHEN loc.Country = 'Tanzania' THEN p.SellingPrice * 2600.00
         WHEN loc.Country = 'Uganda' THEN p.SellingPrice * 3700.00
         WHEN loc.Country = 'Rwanda' THEN p.SellingPrice * 1200.00 END AS UnitPriceLocal,
         
    -- Disocunt applied in local currency
    CASE WHEN ABS(CHECKSUM(NEWID())) % 5 = 0 THEN ROUND(((p.SellingPrice * 0.1) * 130.00), 2) ELSE 0.00 END AS DiscountAmountLocal,
    
    -- Dynamic VAT Rate calculation based on country location
    CASE WHEN loc.Country = 'Kenya' THEN ROUND((p.SellingPrice * 130.00 * 0.16), 2)       -- Kenya 16%
         WHEN loc.Country = 'Tanzania' THEN ROUND((p.SellingPrice * 2600.00 * 0.15), 2)   -- Zanzibar/TZ mainland blend 15%
         WHEN loc.Country = 'Uganda' THEN ROUND((p.SellingPrice * 3700.00 * 0.18), 2)     -- Uganda 18%
         WHEN loc.Country = 'Rwanda' THEN ROUND((p.SellingPrice * 1200.00 * 0.18), 2)     -- Rwanda 18%
         ELSE ROUND((p.SellingPrice * 0.16), 2) END AS TaxAmountLocal,
         
    -- Localized standard cost representation
    CASE WHEN loc.Country = 'Kenya' THEN p.StandardCost * 130.00
         WHEN loc.Country = 'Tanzania' THEN p.StandardCost * 2600.00
         WHEN loc.Country = 'Uganda' THEN p.StandardCost * 3700.00
         WHEN loc.Country = 'Rwanda' THEN p.StandardCost * 1200.00 END AS ProductCostLocal,
         
    -- Local Currency Key strings
    CASE WHEN loc.Country = 'Kenya' THEN 'KES'
         WHEN loc.Country = 'Tanzania' THEN 'TZS'
         WHEN loc.Country = 'Uganda' THEN 'UGX'
         WHEN loc.Country = 'Rwanda' THEN 'RWF' END AS LocalCurrency,
         
    -- Real-world approximate conversion rates back to a standard unified group reporting layer (USD)
    CASE WHEN loc.Country = 'Kenya' THEN 0.0077
         WHEN loc.Country = 'Tanzania' THEN 0.00038
         WHEN loc.Country = 'Uganda' THEN 0.00027
         WHEN loc.Country = 'Rwanda' THEN 0.00078 END AS ExchangeRateToUSD

FROM DimDate d
CROSS JOIN DimProduct p
JOIN DimCustomer c ON c.IsCurrent = 1
JOIN DimLocation loc ON c.LocationKey = loc.LocationKey
WHERE d.Year BETWEEN 2024 AND 2026 
  AND d.DayNumber % 4 = 0 
ORDER BY NEWID();
GO

-- 8. SEED FACTINVENTORY (Simulating Daily Historical Positions)
INSERT INTO FactInventory (DateKey, ProductKey, OpeningStock, StockReceived, StockSold, StockReturned, ClosingStock)
SELECT TOP 25000
    d.DateKey,
    p.ProductKey,
    150 AS OpeningStock,
    CASE WHEN d.DayNumber = 1 THEN 100 ELSE 0 END AS StockReceived,
    ISNULL(SUM(fs.Quantity), 0) AS StockSold,
    CASE WHEN d.DayNumber % 15 = 0 THEN 2 ELSE 0 END AS StockReturned,
    150 + (CASE WHEN d.DayNumber = 1 THEN 100 ELSE 0 END) - ISNULL(SUM(fs.Quantity), 0) AS ClosingStock
FROM DimDate d
CROSS JOIN DimProduct p
LEFT JOIN FactSales fs ON fs.DateKey = d.DateKey AND fs.ProductKey = p.ProductKey
WHERE d.Year = 2025 OR d.Year = 2026
GROUP BY d.DateKey, p.ProductKey, d.DayNumber;
GO

-- 9. SEED FACTMARKETING (Attribution Costs and Conversions)
INSERT INTO FactMarketing (DateKey, CampaignKey, Impressions, Clicks, Conversions, RevenueGenerated, Cost)
SELECT 
    d.DateKey,
    c.CampaignKey,
    ABS(CHECKSUM(NEWID())) % 10000 + 5000 AS Impressions,
    ABS(CHECKSUM(NEWID())) % 800 + 200 AS Clicks,
    ABS(CHECKSUM(NEWID())) % 50 + 5 AS Conversions,
    0.00 AS RevenueGenerated, -- Will pull aggregate value dynamically through reporting layers
    ROUND((c.CampaignCost / DATEDIFF(DAY, c.StartDate, c.EndDate)), 2) AS Cost
FROM DimDate d
CROSS JOIN DimCampaign c
WHERE d.FullDate BETWEEN c.StartDate AND c.EndDate;
GO

-- then we load the views

USE RetailPulse_DWH;
GO

-- 1. vw_RevenueKPIs (High-Level Corporate Unified Performance)
CREATE OR ALTER VIEW vw_RevenueKPIs AS
SELECT 
    d.[Year],
    d.MonthName,
    COUNT(DISTINCT fs.OrderID) AS TotalOrders,
    SUM(fs.GrossRevenueUSD) AS GrossRevenue_USD,
    SUM(fs.NetRevenueUSD) AS NetRevenue_USD,
    SUM(fs.ProfitUSD) AS TotalProfit_USD,
    ROUND((SUM(fs.ProfitUSD) / NULLIF(SUM(fs.NetRevenueUSD), 0)) * 100, 2) AS ProfitMarginPercentage,
    ROUND(SUM(fs.NetRevenueUSD) / NULLIF(COUNT(DISTINCT fs.OrderID), 0), 2) AS AOV_USD
FROM FactSales fs
JOIN DimDate d ON fs.DateKey = d.DateKey
JOIN DimStatus s ON fs.StatusKey = s.StatusKey
WHERE s.StatusName NOT IN ('Cancelled', 'Refunded')
GROUP BY d.[Year], d.MonthNumber, d.MonthName;
GO

-- 2. vw_CustomerMetrics (Cross-Border Segment Enterprise Value)
CREATE OR ALTER VIEW vw_CustomerMetrics AS
SELECT 
    c.CustomerSegment,
    COUNT(DISTINCT fs.CustomerKey) AS ActiveCustomers,
    SUM(fs.Quantity) AS TotalItemsPurchased,
    SUM(fs.NetRevenueUSD) AS TotalRevenue_USD,
    ROUND(SUM(fs.NetRevenueUSD) / NULLIF(COUNT(DISTINCT fs.CustomerKey), 0), 2) AS CLV_USD
FROM FactSales fs
JOIN DimCustomer c ON fs.CustomerKey = c.CustomerKey
JOIN DimStatus s ON fs.StatusKey = s.StatusKey
WHERE s.StatusName = 'Completed'
GROUP BY c.CustomerSegment;
GO

-- 3. vw_ProductPerformance (Regional Catalog Diagnostics)
CREATE OR ALTER VIEW vw_ProductPerformance AS
SELECT 
    p.Category,
    p.SubCategory,
    p.ProductName,
    p.Brand,
    SUM(fs.Quantity) AS UnitsSold,
    SUM(fs.NetRevenueUSD) AS NetRevenue_USD,
    SUM(fs.ProfitUSD) AS TotalProfit_USD,
    ROUND((CAST(SUM(CASE WHEN s.StatusName = 'Returned' THEN fs.Quantity ELSE 0 END) AS DECIMAL(18,2)) / 
           NULLIF(SUM(fs.Quantity), 0)) * 100, 2) AS ReturnRatePercentage
FROM FactSales fs
JOIN DimProduct p ON fs.ProductKey = p.ProductKey
JOIN DimStatus s ON fs.StatusKey = s.StatusKey
GROUP BY p.Category, p.SubCategory, p.ProductName, p.Brand;
GO

-- 4. vw_InventoryAnalytics (Asset Valuation linked to Standard Base Costs)
CREATE OR ALTER VIEW vw_InventoryAnalytics AS
SELECT 
    p.Category,
    p.ProductName,
    SUM(fi.OpeningStock) AS TotalOpeningStock,
    SUM(fi.StockSold) AS TotalUnitsSold,
    SUM(fi.ClosingStock) AS CurrentStockOnHand,
    ROUND(SUM(fi.ClosingStock * p.StandardCost), 2) AS InventoryValue_USD,
    CASE WHEN SUM(fi.StockSold) = 0 THEN 'Dead Stock (No Sales)'
         WHEN SUM(fi.ClosingStock) > (SUM(fi.StockSold) * 3) THEN 'Overstocked'
         ELSE 'Healthy Turnover' END AS StockHealthStatus
FROM FactInventory fi
JOIN DimProduct p ON fi.ProductKey = p.ProductKey
GROUP BY p.Category, p.ProductName;
GO

-- 5. vw_MarketingROI (Multi-Channel Campaign Acquisition Spends)
CREATE OR ALTER VIEW vw_MarketingROI AS
SELECT 
    c.CampaignName,
    c.Channel,
    SUM(fm.Impressions) AS TotalImpressions,
    SUM(fm.Clicks) AS TotalClicks,
    SUM(fm.Conversions) AS TotalConversions,
    SUM(fm.Cost) AS TotalCampaignCost_USD,
    ROUND(SUM(fm.Cost) / NULLIF(SUM(fm.Conversions), 0), 2) AS CAC_USD
FROM FactMarketing fm
JOIN DimCampaign c ON fm.CampaignKey = c.CampaignKey
GROUP BY c.CampaignName, c.Channel;
GO


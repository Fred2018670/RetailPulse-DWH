
USE RetailPulse_DWH;
GO

-- ==============================================================================
-- QUERY 1: Month-over-Month (MoM) Revenue Growth Velocity
-- Business Value: Shows executives whether revenue acceleration is increasing or decaying.
-- ==============================================================================
WITH MonthlyRevenue AS (
    SELECT 
        d.[Year],
        d.MonthNumber,
        d.MonthName,
        SUM(fs.NetRevenueUSD) AS CurrentMonthRevenue_USD
    FROM FactSales fs
    JOIN DimDate d ON fs.DateKey = d.DateKey
    JOIN DimStatus s ON fs.StatusKey = s.StatusKey
    WHERE s.StatusName = 'Completed'
    GROUP BY d.[Year], d.MonthNumber, d.MonthName
)
SELECT 
    [Year],
    MonthName,
    CurrentMonthRevenue_USD,
    ISNULL(LAG(CurrentMonthRevenue_USD, 1) OVER (ORDER BY [Year], MonthNumber), 0) AS PreviousMonthRevenue_USD,
    ROUND(CurrentMonthRevenue_USD - LAG(CurrentMonthRevenue_USD, 1) OVER (ORDER BY [Year], MonthNumber), 2) AS RevenueVariance_USD,
    ROUND(((CurrentMonthRevenue_USD - LAG(CurrentMonthRevenue_USD, 1) OVER (ORDER BY [Year], MonthNumber)) / 
           NULLIF(LAG(CurrentMonthRevenue_USD, 1) OVER (ORDER BY [Year], MonthNumber), 0)) * 100, 2) AS MoMGrowthRatePercentage
FROM MonthlyRevenue
ORDER BY [Year], MonthNumber;



-- ==============================================================================
-- QUERY 2: Quarter-over-Quarter (QoQ) Growth Metrics
-- Business Value: Smooths out monthly anomalies to showcase macro financial health.
-- ==============================================================================
WITH QuarterlyRevenue AS (
    SELECT 
        d.[Year],
        d.Quarter,
        SUM(fs.NetRevenueUSD) AS CurrentQuarterRevenue_USD
    FROM FactSales fs
    JOIN DimDate d ON fs.DateKey = d.DateKey
    JOIN DimStatus s ON fs.StatusKey = s.StatusKey
    WHERE s.StatusName = 'Completed'
    GROUP BY d.[Year], d.Quarter
)
SELECT 
    [Year],
    'Q' + CAST(Quarter AS VARCHAR(2)) AS FinancialQuarter,
    CurrentQuarterRevenue_USD,
    ISNULL(LAG(CurrentQuarterRevenue_USD, 1) OVER (ORDER BY [Year], Quarter), 0) AS PreviousQuarterRevenue_USD,
    ROUND(((CurrentQuarterRevenue_USD - LAG(CurrentQuarterRevenue_USD, 1) OVER (ORDER BY [Year], Quarter)) / 
           NULLIF(LAG(CurrentQuarterRevenue_USD, 1) OVER (ORDER BY [Year], Quarter), 0)) * 100, 2) AS QoQGrowthRatePercentage
FROM QuarterlyRevenue
ORDER BY [Year], Quarter;

-- ==============================================================================
-- QUERY 3: Customer Cohort Retention Analysis (Time-Based Behavior)
-- Business Value: Measures customer loyalty and product-market fit.
-- T-SQL Techniques: First Value Windowing, Date Diffing, and Dynamic Matrix Aggregations
-- ==============================================================================
WITH CustomerFirstPurchase AS (
    -- Establish the birth month (Cohort) for every unique buyer
    SELECT 
        CustomerKey,
        MIN(d.FullDate) AS FirstPurchaseDate,
        DATEFRAMEWORK = DATEADD(MONTH, DATEDIFF(MONTH, 0, MIN(d.FullDate)), 0) -- Truncate to 1st of month
    FROM FactSales fs
    JOIN DimDate d ON fs.DateKey = d.DateKey
    GROUP BY CustomerKey
),
ActivityActivity AS (
    -- Calculate how many months after the cohort birth date the subsequent transactions happened
    SELECT 
        fs.CustomerKey,
        cfp.DATEFRAMEWORK AS CohortMonth,
        DATEDIFF(MONTH, cfp.DATEFRAMEWORK, d.FullDate) AS MonthsElapsed
    FROM FactSales fs
    JOIN DimDate d ON fs.DateKey = d.DateKey
    JOIN CustomerFirstPurchase cfp ON fs.CustomerKey = cfp.CustomerKey
    WHERE fs.StatusKey = 1 -- Completed sales only
)
SELECT 
    FORMAT(CohortMonth, 'yyyy-MM') AS Cohort,
    COUNT(DISTINCT CustomerKey) AS CohortSize,
    -- Build out retention performance buckets across timelines using standard pivots
    COUNT(DISTINCT CASE WHEN MonthsElapsed = 0 THEN CustomerKey END) AS Month_0_Active,
    COUNT(DISTINCT CASE WHEN MonthsElapsed = 1 THEN CustomerKey END) AS Month_1_Retained,
    COUNT(DISTINCT CASE WHEN MonthsElapsed = 2 THEN CustomerKey END) AS Month_2_Retained,
    COUNT(DISTINCT CASE WHEN MonthsElapsed = 3 THEN CustomerKey END) AS Month_3_Retained,
    ROUND((CAST(COUNT(DISTINCT CASE WHEN MonthsElapsed = 1 THEN CustomerKey END) AS DECIMAL(18,2)) / 
           NULLIF(COUNT(DISTINCT CustomerKey), 0)) * 100, 2) AS Month_1_RetentionRate_Pct
FROM ActivityActivity
GROUP BY CohortMonth
ORDER BY CohortMonth;

-- ==============================================================================
-- QUERY 4: Enterprise RFM (Recency, Frequency, Monetary) Customer Segmentation
-- Business Value: Drives automated targeted email marketing paths.
-- ==============================================================================
WITH CustomerRawRFM AS (
    SELECT 
        fs.CustomerKey,
        -- Recency: Days elapsed since their absolute last order date in the platform
        DATEDIFF(DAY, MAX(d.FullDate), '2026-05-30') AS RecencyDays, -- Using current timeline marker
        -- Frequency: Count of distinct orders placed
        COUNT(DISTINCT fs.OrderID) AS OrderFrequency,
        -- Monetary: Aggregate historical net value generated
        SUM(fs.NetRevenueUSD) AS TotalMonetaryValue_USD
    FROM FactSales fs
    JOIN DimDate d ON fs.DateKey = d.DateKey
    WHERE fs.StatusKey = 1
    GROUP BY fs.CustomerKey
),
RFMTiers AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY RecencyDays DESC) AS R_Score, -- High days = Low score (1)
        NTILE(4) OVER (ORDER BY OrderFrequency ASC) AS F_Score, -- High frequency = High score (4)
        NTILE(4) OVER (ORDER BY TotalMonetaryValue_USD ASC) AS M_Score
    FROM CustomerRawRFM
)
SELECT 
    c.CustomerID,
    c.CustomerName,
    r.RecencyDays,
    r.OrderFrequency,
    r.TotalMonetaryValue_USD,
    -- Translate structural numbers into actionable consulting labels
    CASE 
        WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score >= 3 THEN 'Core Champions (VIP)'
        WHEN R_Score <= 2 AND F_Score >= 3 THEN 'At Churn Risk (High Value)'
        WHEN R_Score >= 3 AND F_Score = 1 THEN 'New Promising Leads'
        ELSE 'Hibernating / Price Sensitive' 
    END AS ActionableMarketingSegment
FROM RFMTiers r
JOIN DimCustomer c ON r.CustomerKey = c.CustomerKey
ORDER BY TotalMonetaryValue_USD DESC;

-- ==============================================================================
-- QUERY 5: Dead Stock Asset Valuation (No Sales in Past 90+ Days)
-- Business Value: Identifies frozen working capital sitting in the warehouse.
-- T-SQL Techniques: Subqueries, Exclusions, and Asset Valuation Formulas
-- ==============================================================================
SELECT 
    p.ProductID,
    p.ProductName,
    p.Category,
    p.Brand,
    SUM(fi.ClosingStock) AS UnsoldUnitsOnHand,
    ROUND(SUM(fi.ClosingStock * p.StandardCost), 2) AS TiedUpCapital_USD
FROM FactInventory fi
JOIN DimProduct p ON fi.ProductKey = p.ProductKey
WHERE p.ProductKey NOT IN (
    -- Subquery isolates any product that recorded a sale within our recent historical window
    SELECT DISTINCT ProductKey 
    FROM FactSales 
    WHERE DateKey >= 20260301 -- Looking back from our latest May 2026 data boundary
)
GROUP BY p.ProductID, p.ProductName, p.Category, p.Brand
HAVING SUM(fi.ClosingStock) > 0
ORDER BY TiedUpCapital_USD DESC;



-- ==============================================================================
-- QUERY 6: Most Returned Products & Revenue Liability Leakage
-- Business Value: Flags manufacturing defects, poor sizing, or misleading product pages.
-- ==============================================================================
SELECT 
    p.ProductName,
    p.Category,
    SUM(CASE WHEN s.StatusName = 'Completed' THEN fs.Quantity ELSE 0 END) AS TotalUnitsKept,
    SUM(CASE WHEN s.StatusName = 'Returned' THEN fs.Quantity ELSE 0 END) AS TotalUnitsReturned,
    -- Return Rate percentage calculation
    ROUND(
        (CAST(SUM(CASE WHEN s.StatusName = 'Returned' THEN fs.Quantity ELSE 0 END) AS DECIMAL(18,2)) / 
        NULLIF(SUM(fs.Quantity), 0)) * 100, 2
    ) AS ReturnRatePercentage,
    ROUND(SUM(CASE WHEN s.StatusName = 'Returned' THEN fs.NetRevenueUSD ELSE 0 END), 2) AS LostRevenue_USD
FROM FactSales fs
JOIN DimProduct p ON fs.ProductKey = p.ProductKey
JOIN DimStatus s ON fs.StatusKey = s.StatusKey
GROUP BY p.ProductName, p.Category
HAVING SUM(CASE WHEN s.StatusName = 'Returned' THEN fs.Quantity ELSE 0 END) > 0
ORDER BY ReturnRatePercentage DESC, LostRevenue_USD DESC;

-- ==============================================================================
-- QUERY 7: Market Basket Analysis (Product Affinities for Upselling)
-- Business Value: Powers "Frequently Bought Together" sections to increase cross-border AOV.
-- T-SQL Techniques: Self-Joins, Non-Equal Joins (`<`), Aggregations, and Counting
-- ==============================================================================
SELECT 
    p1.Category AS ProductA_Category,
    p1.ProductName AS ProductA_Name,
    p2.Category AS ProductB_Category,
    p2.ProductName AS ProductB_Name,
    COUNT(*) AS TimesPurchasedTogether
FROM FactSales fs1
-- Self-join on the transaction order ID to find items sharing the same shopping cart
JOIN FactSales fs2 ON fs1.OrderID = fs2.OrderID AND fs1.ProductKey < fs2.ProductKey
JOIN DimProduct p1 ON fs1.ProductKey = p1.ProductKey
JOIN DimProduct p2 ON fs2.ProductKey = p2.ProductKey
WHERE fs1.StatusKey = 1 AND fs2.StatusKey = 1 -- Only analyze completed orders
GROUP BY p1.Category, p1.ProductName, p2.Category, p2.ProductName
HAVING COUNT(*) > 5 -- Filters out isolated accidental matching pairs
ORDER BY TimesPurchasedTogether DESC;


# RetailPulse: Cross-Border E-Commerce & Inventory Analytics Warehouse

A turnkey, production-ready Star Schema Analytics Warehouse designed specifically for multi-channel, cross-border e-commerce operations. This project simulates an analytics infrastructure for a regional retailer operating across East Africa (Kenya, Tanzania, Uganda, and Rwanda), handling multi-tax jurisdictions and localized currency conversions back to a unified corporate reporting layer (USD).

---

## 🚀 Business Value & Freelance Capabilities
This repository acts as a portfolio piece demonstrating advanced T-SQL engineering, performance tuning, and direct solutions to common freelance analytics requests on platforms like Upwork:

*   **International Tax & Multi-Currency Engine:** Automated calculation of regional VAT fluctuations (Kenya 16%, Uganda/Rwanda 18%, Tanzania 15% for Zanzibar/Mainland blend) and currency stabilization logic built directly into the data tier.
*   **Customer Retention Analytics (Cohorts):** Deep-dive matrix tracking of real user retention trajectories over time to measure churn and lifetime loyalty.
*   **Capital Leakage Controls:** Algorithmic identification of "Dead Stock" holding up warehouse capital and liability tracking for high-return product lines.
*   **Market Basket Analysis:** A self-joining affinity algorithm designed to map frequently co-purchased items for product bundling and automated upsells.

---

## 📊 Data Warehouse Architecture (Star Schema)
The architecture is built from the ground up as a highly performant analytical warehouse rather than an operational transactional database.

### Fact Tables
*   **`FactSales`:** Grain at 1 row per order line item. Captures dynamic local pricing vectors (KES, TZS, UGX, RWF) and features auto-computing reporting columns for Unified Corporate Gross Revenue (USD), Net Revenue (USD), and Profit margins.
*   **`FactInventory`:** Daily periodic snapshot capturing warehouse flow data, structural opening/closing counts, and asset valuations linked to product standard costs.
*   **`FactMarketing`:** Tracks cost attribution data directly correlated with active sales pipelines to calculate campaign ROI.

### Dimension Tables
*   **`DimCustomer`:** Protected by Slowly Changing Dimensions (SCD Type 2) tracking systems to map historical tier movements (Bronze, Silver, Gold, Platinum).
*   **`DimProduct`:** Standard retail matrix containing categorization tiers and static base accounting costs.
*   **`DimLocation`, `DimDate`, `DimCampaign`, `DimStatus`:** Core business filters mapping territorial regions, fiscal calendars, and purchase pipelines.

---

## 🗂️ Project Structure & Installation
The warehouse is fully self-contained and ready to execute in Microsoft SQL Server without needing any external language runtimes or external dependencies.

```plaintext
├── 01_Database_Setup_And_Seeding.sql   # DDL Schema, SCD setups, and multi-country mock data (55k+ rows)
├── 02_Analytical_Stored_Procedures.sql  # Parameter-driven API procedures for reporting dashboards and CRMs
├── 03_Advanced_Analytics_Queries.sql    # Core analytical scripts (MoM Growth, Cohorts, RFM, Basket Affinity)
└── RetailPulse_Executive_Insights.pbix  # Connected Power BI Interactive Dashboard
Installation Steps
Open SQL Server Management Studio (SSMS).

Open and execute 01_Database_Setup_And_Seeding.sql. This will configure the database environment, build multi-currency schema parameters, and generate all sample histories across the 2024–2026 timeline.

Execute 02_Analytical_Stored_Procedures.sql to compile the analytical API layers.

Run scripts within 03_Advanced_Analytics_Queries.sql to review the advanced corporate data models.

Open RetailPulse_Executive_Insights.pbix in Power BI Desktop to explore the presentation layer.
```
---

## 📈 Key Metrics & Analytical Models Featured
Cross-Border Tax & Multi-Currency Engine
The database dynamically scales across multiple currencies (KES, TZS, UGX, RWF) by calculating transactional metrics in local currencies alongside their localized tax rates (Kenya 16%, Tanzania 15%, Uganda/Rwanda 18%). It utilizes computed columns to automatically convert and surface uniform USD values for group-wide executive dashboards.

MoM & QoQ Growth Velocity (Window Functions)
Utilizes LAG() over partitioned timelines to compute continuous net conversion variance figures and percentage growth directions without row loop blocks.

Time-Based Customer Cohort Analysis
Maps transactional data against a customer's initial acquisition baseline month to create a retention matrix, enabling businesses to measure exact month-over-month customer churn.

Advanced RFM Customer Segmentation Matrix
Applies an NTILE(4) calculation over historical data vectors (Recency, Frequency, and Monetary valuation) to group users into actionable cohorts like Core Champions (VIP), At Churn Risk (High Value), or Hibernating.

Dead Stock Asset Valuation & Return Analysis
Identifies frozen working capital sitting in the warehouse by isolating products that have generated zero sales over a rolling 90-day window, alongside dynamic return rate metrics tracking financial revenue liability leaks.

Market Basket Association Analysis
Employs an advanced self-join optimization query pattern to efficiently map co-purchase frequency totals across items sharing identical shopping carts to find direct product affinities:

```sql
SQL
SELECT 
    fs1.ProductKey AS ProductA, 
    fs2.ProductKey AS ProductB, 
    COUNT(*) AS TimesPurchasedTogether
FROM FactSales fs1
JOIN FactSales fs2 ON fs1.OrderID = fs2.OrderID AND fs1.ProductKey < fs2.ProductKey
GROUP BY fs1.ProductKey, fs2.ProductKey

```
---

## 🧱 Advanced Analytical DAX Measures (Presentation Layer)
To power the interactive .pbix dashboard, 6 custom DAX expressions were engineered to handle advanced cross-border retail analytics, multi-state daily inventory snapshots, and a non-standard retail fiscal calendar:

### **1. `Fiscal YTD Sales (Custom Calendar)`**
Calculates cumulative sales revenue from the start of the corporate non-standard fiscal calendar rather than the standard Western calendar.
```dax
Fiscal YTD Sales = 
TOTALYTD(
    SUM(FactSales[RevenueUSD]), 
    DimDate[FullDate], 
    "06-30"
)
```
### **2. `Ending Inventory (Periodic Snapshot)`**
Calculates warehouse asset volumes on the final day of any selected temporal slice, ensuring snapshot volumes do not erroneously aggregate additively across time dimensions.
```dax
Ending Inventory Snapshot = 
CALCULATE(
    SUM(FactInventory[ClosingCount]),
    LASTNONBLANK(
        DimDate[FullDate],
        CALCULATE(COUNTROWS(FactInventory))
    )
)

```
### **3. `Inventory Turnover Ratio (ITR)`**
Measures supply chain health by dividing Cost of Goods Sold (COGS) by Average Inventory value, pinpointing capital efficiency.
```dax
Inventory Turnover Ratio = 
VAR TotalCOGS = SUM(FactSales[TotalCostUSD])
VAR AvgInventoryValue = AVERAGE(FactInventory[AssetValuationUSD])
RETURN
DIVIDE(TotalCOGS, AvgInventoryValue, 0)

```

### **4. `Cross-Border Net Revenue (Ex-Tax)`**
Drives multi-country gross margins by dynamically evaluating country-specific tax rules on the fly, subtracting regional VAT streams from international localized transactions.
```dax

Cross-Border Net Revenue = 
SUMX(
    FactSales,
    FactSales[GrossAmountUSD] / (1 + RELATED(DimLocation[TaxRate]))
)

```
### **5. `Active Revenue Risk (Returns Liability)`**
Quantifies financial exposure by tracking rolling return patterns against newly settled sales pipelines within the 30-day fulfillment window.
```dax

Active Revenue Risk = 
VAR TotalReturns = CALCULATE(SUM(FactSales[RevenueUSD]), DimStatus[Status] = "Returned")
VAR TotalSettled = CALCULATE(SUM(FactSales[RevenueUSD]), DimStatus[Status] = "Completed")
RETURN
DIVIDE(TotalReturns, TotalSettled, 0)

```

### **6. `Rolling 12-Month Customer LTV Growth`**
A moving baseline measure analyzing rolling trailing 12-month cohorts to evaluate whether net spending per active customer profile is expanding or contracting over time.
```dax

Rolling 12M Customer LTV = 
CALCULATE(
    SUM(FactSales[RevenueUSD]),
    DATESINPERIOD(
        DimDate[FullDate],
        MAX(DimDate[FullDate]),
        -12,
        MONTH
    )
) / DISTINCTCOUNT(FactSales[CustomerKey])

```

Disclaimer: All transactional data, customer identities, and company names utilized within this pipeline are synthetically generated for analytical demonstration purposes.

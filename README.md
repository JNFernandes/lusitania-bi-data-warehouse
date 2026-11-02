# Lusitânia Stores — Microsoft BI Data Warehouse

An end-to-end on-premises business intelligence platform for a fictional Portuguese retail chain: from an operational database to a dimensional data warehouse, a semantic model and an interactive dashboard.

<p>
  <img src="https://img.shields.io/badge/SQL%20Server-2025-CC2927?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzcgMiA0IDMuNiA0IDUuNXYxM0M0IDIwLjQgNyAyMiAxMiAyMnM4LTEuNiA4LTMuNXYtMTNDMjAgMy42IDE3IDIgMTIgMnptMCAyYzMuOSAwIDYgMS4xIDYgMS41UzE1LjkgNyAxMiA3IDYgNS45IDYgNS41IDguMSA0IDEyIDR6TTYgOC4zQzcuNSA5IDkuNiA5LjMgMTIgOS4zczQuNS0uMyA2LTF2My4yYzAgLjQtMi4xIDEuNS02IDEuNXMtNi0xLjEtNi0xLjV6bTAgNkM3LjUgMTUgOS42IDE1LjMgMTIgMTUuM3M0LjUtLjMgNi0xdjQuMmMwIC40LTIuMSAxLjUtNiAxLjVzLTYtMS4xLTYtMS41eiIvPjwvc3ZnPg%3D%3D" alt="SQL Server"/>
  <img src="https://img.shields.io/badge/T--SQL-stored%20procedures-2B579A?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0id2hpdGUiIGQ9Ik04LjYgMTYuNiA0IDEybDQuNi00LjZMNy4yIDZsLTYgNiA2IDZ6bTYuOCAwTDIwIDEybC00LjYtNC42TDE2LjggNmw2IDYtNiA2eiIvPjwvc3ZnPg%3D%3D" alt="T-SQL"/>
  <img src="https://img.shields.io/badge/SSIS-ETL-0078D4?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0zIDRoNnY1SDN6bTEyIDBoNnY1aC02ek05IDZoNnYxLjVIOXptLTMgNGgxLjV2NEg2em0tMyA0aDZ2NUgzem02IDJoNnYxLjVIOXptNi0yaDZ2NWgtNnoiLz48L3N2Zz4%3D" alt="SSIS"/>
  <img src="https://img.shields.io/badge/SSAS-Tabular-5C2D91?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyIDMgN3YxMGw5IDUgOS01Vjd6bTAgMi4zTDE4LjcgOCAxMiAxMS43IDUuMyA4ek01IDkuN2w2IDMuNHY2LjZsLTYtMy4zem04IDEwVjEzLjFsNi0zLjR2Ni43eiIvPjwvc3ZnPg%3D%3D" alt="SSAS"/>
  <img src="https://img.shields.io/badge/DAX-measures-8661C5?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHRleHQgeD0iMSIgeT0iMTgiIGZvbnQtZmFtaWx5PSJHZW9yZ2lhLHNlcmlmIiBmb250LXN0eWxlPSJpdGFsaWMiIGZvbnQtc2l6ZT0iMTciIGZpbGw9IndoaXRlIj5meDwvdGV4dD48L3N2Zz4%3D" alt="DAX"/>
  <img src="https://img.shields.io/badge/Power%20BI-Desktop-F2C811?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI%2BPHBhdGggZmlsbD0id2hpdGUiIGQ9Ik00IDE0aDR2N0g0em02LTVoNHYxMmgtNHptNi02aDR2MThoLTR6Ii8%2BPC9zdmc%2B" alt="Power BI"/>
  <img src="https://img.shields.io/badge/Visual%20Studio-2026-68217A?style=flat&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMjggMTI4Ij48cGF0aCBmaWxsPSJ3aGl0ZSIgZD0iTTk0LjE0NS4zNDhhOCA4IDAgMCAwLS41NjMuMDcyIDggOCAwIDAgMC0uOTI4LjAyNyA4IDggMCAwIDAtLjk4Mi4yMTUgOCA4IDAgMCAwLS41NTMuMDcyIDggOCAwIDAgMC0uODIyLjM4NyA4IDggMCAwIDAtLjQ4Ni4yMjlBOCA4IDAgMCAwIDg4IDIuNjY4TDQ1LjQ4NiA0OS42NzRsLTI0LjgyLTIwLjM0LTIuMTcyLTEuODY1YTUuMzMzIDUuMzMzIDAgMCAwLS44MjYtLjQ2MyA1LjMzMyA1LjMzMyAwIDAgMC0uNTM1LS4zIDUuMzMzIDUuMzMzIDAgMCAwLS42MDQtLjIyNyA1LjMzMyA1LjMzMyAwIDAgMC0uNjQ0LS4xNSA1LjMzMyA1LjMzMyAwIDAgMC0uNTA0LS4wMTcgNS4zMzMgNS4zMzMgMCAwIDAtLjUxLS4wNzQgNS4zMzMgNS4zMzMgMCAwIDAtLjI2Ni4wNiA1LjMzMyA1LjMzMyAwIDAgMC0uMjE0LS4wMDMgNS4zMzMgNS4zMzMgMCAwIDAtLjIyNy4wNiA1LjMzMyA1LjMzMyAwIDAgMC0uNDg0LjAwNiAzLjQgMy40IDAgMCAwLS43MDcuMjRsLTkuNjk0IDQuMDY3YTUuMzMzIDUuMzMzIDAgMCAwLTEuNDY2Ljk1IDUuMzMzIDUuMzMzIDAgMCAwLS4yMTUuMTc3IDUuMzMzIDUuMzMzIDAgMCAwLS4yMy4zMTIgNS4zMzMgNS4zMzMgMCAwIDAtLjY0Ljg4IDUuMzMzIDUuMzMzIDAgMCAwLS4yNjcuNDc2IDUuMzMzIDUuMzMzIDAgMCAwLS4wOS4yNzUgNS4zMzMgNS4zMzMgMCAwIDAtLjIzMi45MDggNS4zMzMgNS4zMzMgMCAwIDAtLjEzOS41MTZ2NTcuNjhhNS4zMzMgNS4zMzMgMCAwIDAgLjEzOS41MTIgNS4zMzMgNS4zMzMgMCAwIDAgLjIzMi45MTQgNS4zMzMgNS4zMzMgMCAwIDAgLjA5LjI3MSA1LjMzMyA1LjMzMyAwIDAgMCAuMjY4LjQ3NyA1LjMzMyA1LjMzMyAwIDAgMCAuNjM4Ljg3OSA1LjMzMyA1LjMzMyAwIDAgMCAuMjMuMzEyIDUuMzMzIDUuMzMzIDAgMCAwIC4yMTYuMTc4IDUuMzMzIDUuMzMzIDAgMCAwIDEuNDY2Ljk0OWw5LjY5NCA0LjA2NmE1LjMzMyA1LjMzMyAwIDAgMCAxLjcxNi4zNyA1LjMzMyA1LjMzMyAwIDAgMCAuNTEtLjAxIDUuMzMzIDUuMzMzIDAgMCAwIDEuMjcyLS4xOTggNS4zMzMgNS4zMzMgMCAwIDAgLjUxLS4xNTQgNS4zMzMgNS4zMzMgMCAwIDAgMS41MTMtLjg3M2wyLjE3Mi0xLjg2NyAyNC44Mi0yMC4zNEw4OCAxMjUuMzM0YTggOCAwIDAgMCAxLjkwMiAxLjM4NyA4IDggMCAwIDAgLjYwNC4yMyA4IDggMCAwIDAgLjAwNi4wMDIgOCA4IDAgMCAwIDEuMzQyLjUxNiA4IDggMCAwIDAgLjI0Mi4wMTMgOCA4IDAgMCAwIDEuNTU4LjA4OCA4IDggMCAwIDAgLjk5LjAxNCA4IDggMCAwIDAgMi40NS0uNzAzbDI2LjM3My0xMi42OGE4IDggMCAwIDAgLjU3Mi0uMzA2IDggOCAwIDAgMCAuMTctLjEwNiA4IDggMCAwIDAgLjM4My0uMjUgOCA4IDAgMCAwIC4xODEtLjEzNSA4IDggMCAwIDAgLjMzLS4yNTggOCA4IDAgMCAwIC4yMDQtLjE3MyA4IDggMCAwIDAgLjI3Ny0uMjYgOCA4IDAgMCAwIC4xOS0uMTkgOCA4IDAgMCAwIC4yODMtLjMxNCA4IDggMCAwIDAgLjE0NC0uMTY2IDggOCAwIDAgMCAuMjY2LS4zNTIgOCA4IDAgMCAwIC4xNDItLjE5MyA4IDggMCAwIDAgLjMzLS41MyA4IDggMCAwIDAgLjA5LS4xNyA4IDggMCAwIDAgLjItLjM4NiA4IDggMCAwIDAgLjExMy0uMjU2IDggOCAwIDAgMCAuMTUyLS4zNzkgOCA4IDAgMCAwIC4wNzYtLjIxNSA4IDggMCAwIDAgLjExNi0uMzY3IDggOCAwIDAgMCAuMDgyLS4zMDQgOCA4IDAgMCAwIC4wNzItLjM0MiA4IDggMCAwIDAgLjA1My0uMjc0IDggOCAwIDAgMCAuMDU2LS40MzEgOCA4IDAgMCAwIC4wMjItLjE4IDggOCAwIDAgMCAuMDAyLS4wMjMgOCA4IDAgMCAwIC4wMjctLjY1M1YyMS4wMjdhOCA4IDAgMCAwIDAtLjAxMSA4IDggMCAwIDAtLjAyNy0uNjU1IDggOCAwIDAgMC0uMDE4LS4xNTggOCA4IDAgMCAwLS4wNjYtLjUwOCA4IDggMCAwIDAtLjAzNC0uMTcgOCA4IDAgMCAwLS4wOTUtLjQ0MyA4IDggMCAwIDAtLjA3My0uMjY4IDggOCAwIDAgMC0uMTAzLS4zMyA4IDggMCAwIDAtLjEwMi0uMjk1IDggOCAwIDAgMC0uMTQyLS4zNDUgOCA4IDAgMCAwLS4xLS4yMzMgOCA4IDAgMCAwLS4yMDktLjQwNCA4IDggMCAwIDAtLjEwMy0uMTk1IDggOCAwIDAgMC0uMzMyLS41MjggOCA4IDAgMCAwLS4xMDYtLjE0IDggOCAwIDAgMC0uMjc3LS4zNyA4IDggMCAwIDAtLjE4OC0uMjE2IDggOCAwIDAgMC0uMjQ2LS4yNzQgOCA4IDAgMCAwLS4xOTMtLjE5MyA4IDggMCAwIDAtLjI4LS4yNjIgOCA4IDAgMCAwLS4yMDItLjE3NCA4IDggMCAwIDAtLjMzLS4yNTcgOCA4IDAgMCAwLS4xODItLjEzNSA4IDggMCAwIDAtLjM4My0uMjUgOCA4IDAgMCAwLS4xNy0uMTA2IDggOCAwIDAgMC0uNTcyLS4zMDZMOTcuMDk0IDEuMTJBOCA4IDAgMCAwIDk0Ljc1LjQxNmE4IDggMCAwIDAtLjM0Mi4wMDIgOCA4IDAgMCAwLS4yNjMtLjA3ek05NiAzNi45MDh2NTQuMTg2TDYyLjk0NyA2NC4wMDIgOTYgMzYuOTA4em0tODAgOC44MiAxNi41MjcgMTguMjc0TDE2IDgyLjI3NVY0NS43M3oiLz48L3N2Zz4K" alt="Visual Studio"/>
</p>

![Power BI dashboard](PowerBI_Total_Sales.png)

---

## Architecture

```mermaid
flowchart LR
    A[(LusitaniaOLTP<br/>source system)] -->|SSIS<br/>incremental extract| B[stg<br/>staging]
    subgraph DW [LusitaniaDW]
        B -->|T-SQL stored procedures| C[dim + fact<br/>star schema]
        E[etl<br/>watermarks + load log]
    end
    C --> D[SSAS Tabular<br/>semantic model]
    D -->|Live connection| F[Power BI<br/>dashboard]
```

| Layer | What it does |
|---|---|
| **Source (OLTP)** | Normalized retail database: 9 stores, 240 products, 3,000 customers, ~100,000 order lines (2024–2026) |
| **Staging (`stg`)** | Raw copy of new/changed source rows, truncated and reloaded each run |
| **Warehouse (`dim`, `fact`)** | Kimball star schema, SCD Type 1 and Type 2 dimensions, fact table at order-line grain |
| **Control (`etl`)** | Watermark per source table for incremental loads, and a log row for every load step |
| **Semantic model (SSAS)** | Relationships, DAX measures, time intelligence, date hierarchy |
| **Dashboard (Power BI)** | Live connection to the model: KPIs, trends, year-over-year, breakdowns, store map |

---

## Data model

![Star schema](star_schema.png)

- **fact.Sales** — grain: one row per order line. Measures: Quantity, Gross, Discount, Net amount. Degenerate dimensions: OrderNumber, Channel, PaymentMethod.
- **dim.Customer** — mixed SCD: Type 2 on City, District, Segment; Type 1 on name, email, phone.
- **dim.Product** — mixed SCD: Type 2 on Category, Department, ListPrice; Type 1 on name, brand, active flag.
- **dim.Store** — SCD Type 1.
- **dim.Date** — generated calendar 2020–2030 with ISO week, quarters and Portuguese public holidays.

Every dimension has an **Unknown member (key -1)**, so no fact row is ever lost (e.g. anonymous walk-in sales, ~22% of lines).

---

## Semantic model (SSAS Tabular)

![SSAS model diagram](SSAS%20diagram.png)

The model hides all technical columns (surrogate keys, hashes, audit columns), marks `Date` as the date table, sorts month and day names by number, and adds a `Calendar` hierarchy (Year → Quarter → Month → Date).

| Measure | DAX idea |
|---|---|
| Total Sales, Gross Sales, Total Discount, Units Sold | `SUM` of the fact columns |
| Orders | `DISTINCTCOUNT` of OrderNumber |
| Avg Order Value, Discount % | `DIVIDE` of other measures |
| Sales LY | `SAMEPERIODLASTYEAR`, limited to dates that have data (see design decisions) |
| Sales YoY % | Change vs last year, blank when there is no comparison |
| Sales YTD | `TOTALYTD` |

---

## ETL pipeline (SSIS)

`master.dtsx` runs the whole pipeline with one click:

1. **Extract_Package.dtsx** — reads the watermarks, truncates staging, extracts only rows with `ModifiedDate > watermark` from the source.
2. **Load_warehouse.dtsx** — loads the three dimensions **in parallel**, then the fact table only after all three succeed.
3. **Update watermarks** — moves each bookmark forward, only after a successful load.

All transformation logic lives in T-SQL stored procedures; SSIS orchestrates.

---

## Design decisions

**SCD Type 2 vs Type 1, decided per column.**
History is kept only where reports need it. A customer moving city must not move their past sales to the new city, so City is Type 2. Nobody reports "sales by old email address", so Email is Type 1, which also avoids keeping personal data that has no analytical use.

**Change detection with two hashes.**
Each SCD dimension stores a SHA-256 hash of its Type 1 columns and another of its Type 2 columns. Comparing hashes tells the load *what kind* of change happened without comparing every column.

**Point-in-time lookup for the fact.**
Fact rows are matched to the dimension version valid on the sale date (`OrderDate BETWEEN ValidFrom AND ValidTo`). The first version of each member starts at 1900-01-01, so every historical sale finds a match.

**Idempotent loads.**
Every step can be rerun safely: staging is truncated, dimensions are loaded with MERGE on the business key, and the fact with MERGE on its grain (OrderNumber + OrderLineNumber), backed by a unique constraint.

**Incremental extraction with safe failure recovery.**
Watermarks are advanced only after the warehouse load succeeds. If a run fails, the next run re-extracts the same rows, which is harmless because the loads are idempotent.
*Known limitation:* watermark loads do not detect hard deletes in the source. Options would be soft-delete flags, SQL Server CDC, or a periodic business-key comparison.

**Logging.**
Every load procedure writes start time, end time, rows inserted/updated and status to `etl.LoadLog`, and records the error message on failure (TRY/CATCH, transaction rollback, re-throw so SSIS also fails).

**Fair year-over-year comparison.**
The current year is incomplete, so a naive `SAMEPERIODLASTYEAR` compares ten months against twelve. The `Sales LY` measure limits last year to the same date range as the data available this year, and returns blank for periods with no sales.

**Reconciliation.**
After each load, the warehouse is checked against the source: row count and net revenue must match exactly.

---

## Testing

| Test | Expected | Result |
|---|---|---|
| Source vs warehouse reconciliation | Same line count and net revenue | ✅ 99,875 lines · €31,326,152.90 |
| Rerun pipeline with no changes | No rows inserted or updated | ✅ |
| Customer moves city | New SCD2 version; old sales keep old city | ✅ |
| Customer changes email | Overwritten, no new version | ✅ |
| Product price change | New SCD2 version | ✅ |
| Incremental run after 1 change | Only the changed rows extracted | ✅ 1 customer, 1 sales line |

---

## Repository structure

```
sql/                       T-SQL scripts, run in order (01 → 11)
LusitaniaETL/              SSIS project (Extract_Package, Load_warehouse, master)
LusitaniaModel/            SSAS Tabular project (Model.bim)
LusitaniaPBI_report.pbix   Power BI report (live connection to SSAS)
LusitaniaBI.slnx           Visual Studio solution
*.png                      Screenshots and diagrams
```

## How to run

**Requirements:** SQL Server 2025 Developer Edition (Database Engine, Integration Services, Analysis Services in Tabular mode), SSMS, Visual Studio with the SSIS and Analysis Services extensions, Power BI Desktop.

1. Run `sql/01_create_lusitania_oltp.sql` and `sql/02_create_lusitania_dw.sql` in SSMS.
2. Run scripts `04` to `07` and `10` to create the load procedures.
3. Grant the SSAS service account read access to the warehouse:
   ```sql
   CREATE LOGIN [NT Service\MSSQLServerOLAPService] FROM WINDOWS;
   USE LusitaniaDW;
   CREATE USER [NT Service\MSSQLServerOLAPService] FOR LOGIN [NT Service\MSSQLServerOLAPService];
   ALTER ROLE db_datareader ADD MEMBER [NT Service\MSSQLServerOLAPService];
   ```
4. Open `LusitaniaBI.slnx` in Visual Studio and run `master.dtsx`.
5. Deploy `LusitaniaModel` to `localhost`.
6. Open `LusitaniaPBI_report.pbix` in Power BI Desktop.

To simulate business changes and watch them flow through the pipeline, run `sql/08_simulate_changes.sql`, run `master.dtsx` again, then `sql/09_verify_changes.sql`.

---

*All data is synthetic, generated by the scripts in this repository.*

# PulseIQ Analytics — Task 2: Reporting Data Warehouse

A containerised PostgreSQL reporting data warehouse designed with a **Star Schema** architecture, **Slowly Changing Dimensions (SCD Type 2)**, **idempotent ETL upserts**, and **performance indexing**.

---

## 🚀 Quick Start (One Command)

From this project directory:

```bash
docker compose up --build
```

This single command will:
1. Spin up a **PostgreSQL 16** warehouse container (`pulseiq_postgres`) with health checks.
2. Automatically run the DDL schema script (`sql/init_schema.sql`) to create all tables and indexes.
3. Build and launch the ETL loader container (`pulseiq_warehouse_loader`).
4. Load dimensions and facts using **idempotent bulk UPSERTs** (`INSERT ... ON CONFLICT DO UPDATE`).
5. Execute the **three executive SQL queries + SCD2 history check** and display formatted results in the console.

To stop the services:
```bash
docker compose down
```

---

## 🏛️ Star Schema Architecture

Facts live in the center; Dimensions surround them to provide rich filtering, grouping, and drill-down context:

```
                      ┌───────────────────┐
                      │     dim_date      │
                      └─────────┬─────────┘
                                │
    ┌──────────────────┐        │        ┌──────────────────┐
    │  dim_department  ├────────┼───────►│   fact_payroll   │
    └────────┬─────────┘        │        └────────┬─────────┘
             │                  │                 │
             │                  ▼                 │
             │         ┌─────────────────┐        │
             ├────────►│ fact_attendance │        │
             │         └─────────────────┘        │
             │                                    │
             ▼                                    ▼
    ┌──────────────────┐                 ┌──────────────────┐
    │   dim_employee   │◄────────────────┤    fact_leave    │
    │  (SCD Type 2)    │                 └──────────────────┘
    └──────────────────┘
```

See the full Mermaid diagram in [`docs/schema_diagram.md`](docs/schema_diagram.md).

---

## 🎯 Fact Table Grains (One Sentence Each)

Choosing the grain defines the exact unit of measurement for each fact table:

1. **`fact_payroll`**:  
   *Grain: One row per employee per payroll processing month.*  
   Captures fixed pay, variable incentives, deductions, taxes, and total employer cost incurred.

2. **`fact_attendance_monthly`**:  
   *Grain: One row per employee per calendar month.*  
   Aggregates scheduled days, days present, WFH days, and computed monthly attendance rate.

3. **`fact_attendance_daily`**:  
   *Grain: One row per employee per scheduled calendar day.*  
   Tracks daily check-in status (Present, Absent, Half Day).

4. **`fact_leave`**:  
   *Grain: One row per discrete leave request submitted by an employee.*  
   Records leave type, approval status, and duration in days.

5. **`fact_headcount_monthly`**:  
   *Grain: One row per department per calendar month.*  
   Periodic snapshot recording starting headcount, hires, exits, transfers in/out, ending headcount, and monthly attrition rate.

---

## 💡 The "Think For Yourself" Design: Employee Department Transfer

> **Question**: *An employee moves from Sales to Support in June. How should May's cost and July's cost be reported, and how does your design make that work? Write your rule and why.*

### The Rule:
> **"Fact tables MUST join to dimensional history tables on the Surrogate Key (`employee_key`), NEVER the Natural Key (`employee_id`)."**

### How It Works:
- In `dim_employee`, the employee has two rows:
  - `employee_key = 100010`: Sales (`D04`), `valid_from = 2024-01-01`, `valid_to = 2025-05-31`, `is_current = 'N'`
  - `employee_key = 100011`: Support (`D07`), `valid_from = 2025-06-01`, `valid_to = 9999-12-31`, `is_current = 'Y'`
- **May's payroll fact row** stores `employee_key = 100010` $\rightarrow$ Reports under **Sales**.
- **July's payroll fact row** stores `employee_key = 100011` $\rightarrow$ Reports under **Support**.
- **Why**: Sales actually consumed the employee's labor in May and bore the cost. Retroactively reclassifying May to Support violates accounting matching principles and corrupts budget variance analysis.

Read the detailed architecture in [`docs/scd_type2_design.md`](docs/scd_type2_design.md).

---

## 📊 Three Sample SQL Verification Queries

Run manually via `psql` or automatically via `python src/verify_warehouse.py`:

1. **Cost by Department (2025-04)**:  
   Groups by department name to report employees paid, total gross, net, and employer cost.
2. **Headcount Trend (2025-04)**:  
   Tracks starting headcount, hires, exits, net transfers, ending headcount, and monthly attrition rate.
3. **Attendance & Overtime (2025-04)**:  
   Computes department attendance rate %, WFH share %, and overtime hours.
4. **SCD2 Point-in-Time History (EMP-0002)**:  
   Demonstrates Jatin Jayaraman's transition from Engineering (`D01`) to Finance (`D08`).

Full SQL script available in [`sql/test_queries.sql`](sql/test_queries.sql).

---

## 📈 Apache Superset Dashboard (Task 3)

The warehouse now includes a fully configured **Apache Superset** service connected to `pulseiq_postgres`.

### Accessing Superset:
- **URL**: `http://localhost:8088`
- **Username**: `admin`
- **Password**: `admin`
- **Dashboard**: `Headcount & Departments` (`/superset/dashboard/headcount-and-departments/`)

### Dashboard Features:
- **KPI Row**: `headcount` (441), `hires` (17), `exits` (3), `net_headcount_change` (+14).
- **Core Charts**:
  - `headcount_trend`: 21-month trajectory from 394 to 441 (+11.9% growth).
  - `department_split`: Ranked horizontal bar chart across 11 departments.
  - `tenure_bands`: Distribution across 5 tenure cohorts (50.6% have 3+ years).
  - `role_mix`: Seniority pyramid across job levels L1–L7 (59.4% in L2–L3).
  - `joiners_vs_leavers`: Grouped monthly inflow vs outflow with net line.
- **Filters**: Multi-select Department filter and Date Range filter.
- **Rule Adherence**: Metric dictionary titles + executive one-line takeaway on every chart.

---

## 📁 Repository Structure

```
Project 2 - PulseIQ Warehouse/
├── docker-compose.yml       ← PostgreSQL 16 + Loader + Apache Superset services
├── Dockerfile               ← Python container for loader
├── requirements.txt         ← psycopg2-binary, sqlalchemy, pandas, openpyxl, tabulate
├── .env / .env.example      ← Database connection credentials
├── dashboards/
│   ├── headcount_department_dashboard.json ← Exported Superset dashboard JSON
│   ├── headcount_department_export.zip     ← Native Superset dashboard bundle
│   └── export/              ← Modular YAML export (databases, datasets, charts, dashboards)
├── sql/
│   ├── init_schema.sql      ← DDL for 5 dimensions, 5 facts, and performance indexes
│   └── test_queries.sql     ← 3 executive queries + SCD2 audit query
├── src/
│   ├── load_warehouse.py    ← Idempotent bulk UPSERT loader
│   └── verify_warehouse.py  ← Automated query tester and output validator
├── scripts/
│   └── setup_superset.py    ← Automated Superset asset importer
├── docs/
│   ├── style_guide.md       ← Color-blind safe palette, fonts, number formats, & takeaways
│   ├── dashboard_design_review.md ← AI layout review, responsiveness, and design critique
│   ├── schema_diagram.md    ← Mermaid star schema diagram & grain definitions
│   ├── business_questions.md← Key questions leaders ask and required metrics
│   └── scd_type2_design.md  ← Department transfer design decision and rule
└── data/
    ├── clean/               ← Clean exports from Task 1
    └── star_schema_dataset.xlsx ← Complete PulseIQ analytics star schema workbook
```

---

## ✅ Completion Criteria Met

- [x] Style guide written with color-blind safe palette and the "Title + Takeaway" rule ([`docs/style_guide.md`](docs/style_guide.md))
- [x] AI design reviewed, critiqued, and improved for hierarchy and mobile responsiveness ([`docs/dashboard_design_review.md`](docs/dashboard_design_review.md))
- [x] Superset added to Docker Compose (`pulseiq_superset` on port 8088) and connected to the reporting warehouse
- [x] Headcount & Departments dashboard built with 4 KPI cards, 5 charts, and native filters (department, date range)
- [x] Numbers match warehouse data (441 active headcount, 17 hires, 3 exits, 50.6% 3+ yr tenure, 59.4% mid-senior specialists)
- [x] Dashboard export saved in repository ([`dashboards/`](dashboards/))


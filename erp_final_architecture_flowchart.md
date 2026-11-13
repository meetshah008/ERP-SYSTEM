# Enterprise Manufacturing ERP: System Architecture & Dual-Platform Flowchart

---

## 1. Executive Technical Overview

This architecture document formally outlines the multi-tier system topology and unified workflow for the **Enterprise Manufacturing ERP System**. 

The solution is architected as a **Dual-Platform Ecosystem** powered by a single cross-platform codebase (Flutter) connecting to a modular RESTful backend (Node.js/Express) and relational persistence layer (MySQL).

### Dual-Platform Client Strategy:
1. **Web & Desktop Application**:
   - **Target:** Manufacturing Companies & Enterprise Businesses.
   - **Focus:** Complete operational management, production planning (BOM), inventory control, 3-way accounts matching, bulk biometric attendance processing, and executive reporting on a desktop-optimized dashboard.

2. **Mobile Application**:
   - **Target:** Factory Floor, On-Site & Field Workforce Operations.
   - **Focus:** Real-time shop-floor execution, machine operation logs, quick raw material requests, task updates, and employee self-service (attendance & leaves) on a mobile-first interface.

---

## 2. Multi-Tier System Topology Diagram

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 PRESENTATION LAYER (UI)                                │
│                                                                                        │
│   ┌──────────────────────────────────────────┐  ┌────────────────────────────────────┐ │
│   │        WEB APP (Management Portal)       │  │    MOBILE APP (Worker / Staff)     │ │
│   │  - Super Admin Corporate Control         │  │  - Self-Service Punch & Leaves     │ │
│   │  - Production Routing & BOM Designer     │  │  - Machine Downtime & Scrap Log    │ │
│   │  - 3-Way Matching & Financial Audits     │  │  - On-site Task Checklist          │ │
│   │  - Bulk Face-Scanner Sheet Uploads       │  │  - Instant Material Issue Request  │ │
│   └────────────────────┬─────────────────────┘  └─────────────────┬──────────────────┘ │
└────────────────────────┼──────────────────────────────────────────┼────────────────────┘
                         │                                          │
                         │          HTTPS / REST API / JWT          │
                         ▼                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              APPLICATION SERVER (NODE.JS)                              │
│                                                                                        │
│  ┌───────────────────────┐  ┌────────────────────────┐  ┌───────────────────────────┐  │
│  │   Auth & RBAC Module  │  │   HR & Attendance Hub  │  │   Inventory & Stock Sync  │  │
│  └───────────────────────┘  └────────────────────────┘  └───────────────────────────┘  │
│  ┌───────────────────────┐  ┌────────────────────────┐  ┌───────────────────────────┐  │
│  │   Manufacturing Core  │  │  Projects & Timesheets │  │  Accounts & 3-Way Match   │  │
│  └───────────────────────┘  └────────────────────────┘  └───────────────────────────┘  │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │
                                            │  Connection Pooling (mysql2)
                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              DATABASE LAYER (MYSQL ENGINE)                             │
│                                                                                        │
│  - 51 Normalized Relational Entities (COMPANY, USER, EMPLOYEE, WORK_ORDER, BOM, etc.)  │
│  - ACID-Compliant Financial and Production Transactions                                │
│  - Immutable Calculation Snapshots & Multi-Tenant Isolation by company_id              │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Final Master Flowchart (Web vs. Mobile Workflows)

```mermaid
flowchart TB

    %% ================= 1. CLIENT ENTRY & DUAL-PLATFORM DETECTION =================
    subgraph CLIENT_ENTRY["1. CLIENT ACCESS & DEVICE ROUTING"]
        direction TB
        START([User Launches ERP Application]) --> DETECT_DEVICE{Detect Client Device}
        DETECT_DEVICE -- Desktop / Web Browser --> WEB_CLIENT[Launch Web Portal Viewport]
        DETECT_DEVICE -- Mobile / Tablet Device --> MOB_CLIENT[Launch Mobile App Viewport]
        
        WEB_CLIENT --> CHECK_CO{Company Configured?}
        MOB_CLIENT --> CHECK_CO
        
        CHECK_CO -- No: First Time Setup --> WIZARD[Web Company Setup Wizard: Legal Name, GST, FY, Super Admin]
        WIZARD --> LOGIN_SCREEN
        CHECK_CO -- Yes --> LOGIN_SCREEN[Display Login Screen]
    end

    %% ================= 2. AUTHENTICATION & ACCESS ENGINE =================
    subgraph AUTH_ENGINE["2. AUTHENTICATION & ROLE GOVERNANCE"]
        direction TB
        LOGIN_SCREEN --> INPUT_AUTH[Enter Email & Master Password]
        INPUT_AUTH --> VERIFY_CREDS{Validate Credentials}
        VERIFY_CREDS -- Invalid --> SHOW_ERROR[Show Error Alert & Lock Attempts]
        SHOW_ERROR --> LOGIN_SCREEN
        VERIFY_CREDS -- Valid --> MFA_CHECK{2FA Enabled?}
        MFA_CHECK -- Yes --> ENTER_OTP[Enter Verification OTP]
        ENTER_OTP --> ISSUE_TOKEN[Issue Secure JWT Token & Role Claims]
        MFA_CHECK -- No --> ISSUE_TOKEN
        
        ISSUE_TOKEN --> ROLE_BRANCH{Evaluate Role & Device Type}
    end

    %% ================= 3. WEB PORTAL WORKFLOW (MANAGEMENT TIER) =================
    subgraph WEB_PORTAL["3. WEB MANAGEMENT PORTAL (Super Admin & Module Managers)"]
        direction TB
        ROLE_BRANCH -- Web: Super Admin --> WEB_ADMIN_DASH[Super Admin Global Command Center]
        ROLE_BRANCH -- Web: Module Manager --> WEB_MGR_DASH[Department Operations Console]
        
        WEB_ADMIN_DASH --> SYS_CONFIG[Manage Branches, Multi-Warehouse & Role Permissions]
        WEB_ADMIN_DASH --> AUDIT_VIEW[Review Real-Time Audit Logs & P&L Statements]
        
        %% Web HR
        WEB_MGR_DASH -- HR Management --> WEB_HR[HR Management Console]
        WEB_HR --> UPLOAD_EXCEL[Upload Biometric Face Scanner Excel Sheet]
        UPLOAD_EXCEL --> PARSE_EXCEL[Background Parser: Calculate Late, Half-Day & Present]
        PARSE_EXCEL --> HR_DB_SAVE[(Update Attendance & Employee Records)]
        WEB_HR --> LEAVE_APPROVALS[Process Team Leave Approval Requests]
        
        %% Web Manufacturing
        WEB_MGR_DASH -- Production Management --> WEB_MFG[Manufacturing & Shop Floor Center]
        WEB_MFG --> DEFINE_BOM[Maintain Multi-Level BOM Recipes & Routings]
        DEFINE_BOM --> CREATE_WO[Schedule Production Work Orders]
        CREATE_WO --> PUSH_WO_FLOOR[Dispatch Operations to Work Centers]
        
        %% Web Inventory & Purchase
        WEB_MGR_DASH -- Supply Chain --> WEB_INV[Inventory & Procurement Hub]
        WEB_INV --> REORDER_CHECK{Stock < Reorder Level?}
        REORDER_CHECK -- Yes --> ISSUE_PO[Generate Purchase Order to Vendor]
        ISSUE_PO --> RECV_GRN[Inspect Delivery & Confirm GRN QC]
        
        %% Web Accounts
        WEB_MGR_DASH -- Accounts & Finance --> WEB_ACC[Finance & Commercial Ledger]
        RECV_GRN --> THREE_WAY_MATCH{3-Way Match: PO == GRN == Bill}
        THREE_WAY_MATCH -- Matched --> PAY_VENDOR[Disburse Vendor Payment via Bank]
        WEB_ACC --> GEN_INVOICE[Issue Customer Invoices & Ledger Entries]
    end

    %% ================= 4. MOBILE APP WORKFLOW (OPERATORS & STAFF) =================
    subgraph MOBILE_PORTAL["4. MOBILE APPLICATION (Floor Operators & Field Staff)"]
        direction TB
        ROLE_BRANCH -- Mobile: Operator / Staff --> MOB_DASH[Mobile Touch Home Dashboard]
        
        %% Mobile Features
        MOB_DASH --> MOB_ATTEND[Self-Service Attendance Punch]
        MOB_DASH --> MOB_LEAVES[Apply for Casual / Sick Leave]
        MOB_DASH --> MOB_PAYSLIP[Download Monthly PDF Payslips]
        
        %% Mobile Shop Floor Execution
        MOB_DASH --> MOB_WO_EXEC[My Machine Work Orders]
        PUSH_WO_FLOOR -. Sync to Operator App .-> MOB_WO_EXEC
        MOB_WO_EXEC --> LOG_PROD[Log Machine Hours, Output Quantity & Scrap]
        LOG_PROD --> PROD_LOG_DB[(Save Production Execution Log)]
        
        %% Mobile Project & Tasks
        MOB_DASH --> MOB_TASKS[My Assigned Project Tasks]
        MOB_TASKS --> UPDATE_TASK_STATUS[Move Kanban Status: In Progress / Done]
        UPDATE_TASK_STATUS --> LOG_TIMESHEET[Submit Daily Task Timesheet Hours]
        
        %% Mobile Stock Requisition
        MOB_TASKS --> NEED_MATERIAL{Need Raw Materials?}
        NEED_MATERIAL -- Yes --> MOB_REQ_STOCK[Submit Mobile Material Requisition]
        MOB_REQ_STOCK -. Trigger Approval Alert .-> WEB_INV
    end

    %% ================= 5. SHARED PERSISTENCE & SYNC =================
    HR_DB_SAVE --> CENTRAL_DB[(MySQL Relational Database: 51 Tables)]
    PROD_LOG_DB --> CENTRAL_DB
    PAY_VENDOR --> CENTRAL_DB
    GEN_INVOICE --> CENTRAL_DB
    LOG_TIMESHEET --> CENTRAL_DB
```

---

## 4. Key Architectural Highlights for Management

1. **True Cross-Platform Codebase**:
   - Both Web and Mobile are powered by a single Flutter repository, reducing development and maintenance overhead by over 50%.
2. **Adaptive Form Factor Rendering**:
   - The UI automatically renders dense, mouse-driven data grids for desktop users, and card-based, thumb-accessible touch interfaces for mobile users.
3. **Hardware-Agnostic Attendance Sync**:
   - Supports mobile self-service punches while simultaneously incorporating bulk offline Excel dumps from proprietary physical face-recognition scanners.
4. **End-to-End Traceability (Task to Machine to Ledger)**:
   - Every physical item requested on mobile flows directly from inventory balances, through manufacturing work orders, into project cost centers, and automatically reconciles in general ledger accounting.

# Beginner-Friendly Project Architecture Guide (Frontend & Backend)

Yeh guide isliye hai taaki tujhe code dhoondhne ya kisi chiz ko modify karne mein 1 second ka bhi confusion na ho. Sab kuch chhotte-chhotte, saaf-suthre folders mein bat gaya hai.

---

## 1. Project Root (Tere Main Folder Ka Look)

Tera main project folder do saaf hisso mein rahega:

```text
ERP_SYSTEM/
│
├── erp_backend/        <-- Server (Node.js + Express + MySQL)
│
└── erp_frontend/       <-- Screens & UI (Flutter Web + Mobile)
```

---

## 2. BACKEND ARCHITECTURE (`erp_backend/`)
*(Rule: Har module ka alag folder. Har kaam ka alag folder!)*

Jab bhi koi feature banta hai, uske sirf 3 steps hote hain:
1. **Route (URL / Path):** Jaise `/api/auth/login` ya `/api/hr/upload-attendance`.
2. **Controller (Manager):** Jo request check karta hai.
3. **Service (Worker):** Jo asal mein Excel padhta hai ya database mein save karta hai.

```text
erp_backend/
├── src/
│   ├── config/                     <-- Database Connection Settings
│   │   └── db.js                   <-- MySQL Workbench se connect karne wali 5 line
│   │
│   ├── modules/                    <-- SARE BUSINESS MODULES
│   │   │
│   │   ├── 01_auth/                <-- LOGIN & COMPANY REGISTRATION
│   │   │   ├── auth.routes.js      <-- URLs: /register-company, /login, /verify-otp
│   │   │   ├── auth.controller.js  <-- Input validation (email, password check)
│   │   │   └── auth.service.js     <-- Password hash & Database save
│   │   │
│   │   ├── 02_hr/                  <-- HR & BIOMETRIC ATTENDANCE
│   │   │   ├── hr.routes.js        <-- URLs: /employees, /upload-attendance, /leaves
│   │   │   ├── hr.controller.js    <-- File upload catch karna
│   │   │   ├── excel_parser.js     <-- ⭐ FACE SCANNER EXCEL READ KARNE KA CODE
│   │   │   └── hr.service.js       <-- Late/Half-Day status aur DB save
│   │   │
│   │   ├── 03_inventory/           <-- STOCK & WAREHOUSE
│   │   │   ├── inventory.routes.js
│   │   │   ├── inventory.controller.js
│   │   │   └── inventory.service.js
│   │   │
│   │   ├── 04_manufacturing/       <-- FACTORY, BOM & WORK ORDERS
│   │   │   ├── mfg.routes.js
│   │   │   ├── mfg.controller.js
│   │   │   └── mfg.service.js
│   │   │
│   │   ├── 05_projects/            <-- PROJECTS, TASKS & TIMESHEETS
│   │   │   ├── project.routes.js
│   │   │   ├── project.controller.js
│   │   │   └── project.service.js
│   │   │
│   │   └── 06_accounts/            <-- INVOICES, VENDOR BILLS & PAYROLL
│   │       ├── accounts.routes.js
│   │       ├── accounts.controller.js
│   │       └── accounts.service.js
│   │
│   └── server.js                   <-- Backend start karne ka main switch
│
└── package.json                    <-- Libraries list (express, mysql2, xlsx, etc.)
```

---

## 3. FRONTEND ARCHITECTURE (`erp_frontend/` - Flutter)
*(Rule: Koi bhi file 150 lines se badi nahi hogi. Sab components mein toota hoga!)*

```text
erp_frontend/lib/
│
├── core/                           <-- SAB JAGAH USE HONE WALA SAMAAN
│   ├── theme/
│   │   └── app_colors.dart         <-- Sirf colors: Primary Blue, Green, Red
│   │
│   ├── widgets/                    <-- REUSABLE LEGO BLOCKS
│   │   ├── custom_button.dart      <-- Standard Button (Har page pe use hoga)
│   │   ├── custom_text_field.dart  <-- Standard Input Box (Naam, Email daalne ke liye)
│   │   ├── responsive_builder.dart <-- Web vs Mobile screen pehchanne wala code
│   │   └── status_badge.dart       <-- 'Present', 'Late', 'In-Progress' wale badges
│   │
│   └── network/
│       └── api_client.dart         <-- Backend se baat karne wali ek file
│
├── features/                       <-- SCREEN BY SCREEN WORK
│   │
│   ├── 01_setup/                   <-- PEHLI BAAR COMPANY CREATE
│   │   ├── company_setup_screen.dart
│   │   └── components/
│   │       ├── company_details_step.dart  (Step 1: Name, GST)
│   │       ├── admin_account_step.dart    (Step 2: Admin Email/Pass)
│   │       └── branch_warehouse_step.dart (Step 3: First Branch)
│   │
│   ├── 02_auth/                    <-- ROZ KA LOGIN
│   │   ├── login_screen.dart
│   │   └── components/
│   │       ├── login_form.dart
│   │       └── otp_input_box.dart
│   │
│   ├── 03_dashboard_shell/         <-- APP KA FRAME (Sidebar + Header)
│   │   ├── web_shell.dart          (Desktop/Web View with full Sidebar)
│   │   ├── mobile_shell.dart       (Mobile View with Bottom Bar)
│   │   └── components/
│   │       ├── sidebar_item.dart
│   │       └── user_profile_header.dart
│   │
│   ├── 04_hr_module/               <-- HR SCREENS
│   │   ├── employee_list_screen.dart
│   │   ├── attendance_screen.dart  (Face scanner upload page)
│   │   └── components/
│   │       ├── employee_row_card.dart
│   │       ├── excel_upload_box.dart
│   │       └── leave_apply_modal.dart
│   │
│   ├── 05_inventory_module/        <-- INVENTORY SCREENS
│   │   ├── stock_list_screen.dart
│   │   └── components/
│   │       └── item_card.dart
│   │
│   ├── 06_manufacturing_module/    <-- FACTORY SCREENS
│   │   ├── work_orders_screen.dart
│   │   └── components/
│   │       └── bom_card.dart
│   │
│   └── 07_projects_module/         <-- PROJECTS SCREENS
│       ├── kanban_screen.dart
│       └── components/
│           ├── task_card.dart
│           └── timesheet_modal.dart
│
└── main.dart                       <-- Flutter start point
```

---

## 4. Yeh Architecture Tere Liye Itna Simple Kyun Banega?

### Real Life Scenario 1:
**"Bhai, mujhe Login screen ka background ya button ka text change karna hai!"**
- Tu kisi database ya backend ko nahi chhe dega.
- Seedha khol: `erp_frontend/lib/features/02_auth/components/login_form.dart`
- Bas 1 line change kar aur save kar!

### Real Life Scenario 2:
**"Bhai, Face Scanner Excel mein naya rule lagana hai ki 9:45 ke baad Late ho!"**
- Tu kisi frontend screen ko nahi chhe dega.
- Seedha khol: `erp_backend/src/modules/02_hr/excel_parser.js`
- Wahan clear likha hoga: `if (inTime > '09:45') status = 'Late';`
- Chhotisi line badal aur done!

---

Is tarike se har feature ek alag box (LEGO block) ki tarah rahega. Koi bhi file lambi ya complex nahi hogi!

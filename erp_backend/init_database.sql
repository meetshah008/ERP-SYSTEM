-- ============================================================================
-- MANUFACTURING ERP SYSTEM - MASTER DATABASE INITIALIZATION SCRIPT (MySQL)
-- Run this script directly in MySQL Workbench to create all foundation tables.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS `manufacturing_erp` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `manufacturing_erp`;

-- 1. COMPANY TABLE (Master Tenant)
CREATE TABLE IF NOT EXISTS `COMPANY` (
  `company_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_code` VARCHAR(50) NOT NULL UNIQUE,
  `name` VARCHAR(150) NOT NULL,
  `tax_id` VARCHAR(50),
  `address` TEXT,
  `currency` VARCHAR(10) NOT NULL DEFAULT 'INR',
  `financial_year_start` DATE NOT NULL,
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 2. BRANCH TABLE
CREATE TABLE IF NOT EXISTS `BRANCH` (
  `branch_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `address` TEXT,
  FOREIGN KEY (`company_id`) REFERENCES `COMPANY`(`company_id`) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 3. ROLE TABLE (3-Tier Hierarchy: Super Admin, Module Manager, Employee)
CREATE TABLE IF NOT EXISTS `ROLE` (
  `role_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `name` VARCHAR(50) NOT NULL,
  FOREIGN KEY (`company_id`) REFERENCES `COMPANY`(`company_id`) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 4. PERMISSION TABLE
CREATE TABLE IF NOT EXISTS `PERMISSION` (
  `permission_id` INT AUTO_INCREMENT PRIMARY KEY,
  `module` VARCHAR(50) NOT NULL,
  `action` VARCHAR(50) NOT NULL
) ENGINE=InnoDB;

-- 5. ROLE_PERMISSION MAPPING
CREATE TABLE IF NOT EXISTS `ROLE_PERMISSION` (
  `role_id` INT NOT NULL,
  `permission_id` INT NOT NULL,
  PRIMARY KEY (`role_id`, `permission_id`),
  FOREIGN KEY (`role_id`) REFERENCES `ROLE`(`role_id`) ON DELETE CASCADE,
  FOREIGN KEY (`permission_id`) REFERENCES `PERMISSION`(`permission_id`) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 6. USER TABLE (Login Accounts)
CREATE TABLE IF NOT EXISTS `USER` (
  `user_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `role_id` INT NOT NULL,
  `email` VARCHAR(120) NOT NULL UNIQUE,
  `password_hash` VARCHAR(255) NOT NULL,
  `two_factor_enabled` BOOLEAN DEFAULT FALSE,
  `is_active` BOOLEAN DEFAULT TRUE,
  `last_login` DATETIME NULL,
  FOREIGN KEY (`company_id`) REFERENCES `COMPANY`(`company_id`) ON DELETE CASCADE,
  FOREIGN KEY (`role_id`) REFERENCES `ROLE`(`role_id`)
) ENGINE=InnoDB;

-- 7. AUDIT_LOG TABLE
CREATE TABLE IF NOT EXISTS `AUDIT_LOG` (
  `log_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `user_id` INT NOT NULL,
  `module` VARCHAR(50) NOT NULL,
  `action` VARCHAR(50) NOT NULL,
  `record_ref` VARCHAR(100),
  `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`company_id`) REFERENCES `COMPANY`(`company_id`) ON DELETE CASCADE,
  FOREIGN KEY (`user_id`) REFERENCES `USER`(`user_id`)
) ENGINE=InnoDB;

-- 8. DEPARTMENT TABLE
CREATE TABLE IF NOT EXISTS `DEPARTMENT` (
  `department_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `head_employee_id` INT NULL,
  FOREIGN KEY (`company_id`) REFERENCES `COMPANY`(`company_id`) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 9. EMPLOYEE TABLE (Profile + Face Scanner Code)
CREATE TABLE IF NOT EXISTS `EMPLOYEE` (
  `employee_id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NULL UNIQUE,
  `branch_id` INT NOT NULL,
  `department_id` INT NOT NULL,
  `emp_code` VARCHAR(50) NOT NULL UNIQUE,
  `biometric_emp_code` VARCHAR(50) NULL UNIQUE, -- Offline Face Scanner Machine ID
  `full_name` VARCHAR(120) NOT NULL,
  `designation` VARCHAR(100) NOT NULL,
  `join_date` DATE NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'active',
  FOREIGN KEY (`user_id`) REFERENCES `USER`(`user_id`) ON DELETE SET NULL,
  FOREIGN KEY (`branch_id`) REFERENCES `BRANCH`(`branch_id`),
  FOREIGN KEY (`department_id`) REFERENCES `DEPARTMENT`(`department_id`)
) ENGINE=InnoDB;

-- 10. ATTENDANCE_IMPORT TABLE (Face Scanner Excel Logs)
CREATE TABLE IF NOT EXISTS `ATTENDANCE_IMPORT` (
  `import_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `uploaded_by` INT NOT NULL,
  `file_name` VARCHAR(255) NOT NULL,
  `total_records` INT DEFAULT 0,
  `success_count` INT DEFAULT 0,
  `error_log` JSON NULL,
  `uploaded_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`company_id`) REFERENCES `COMPANY`(`company_id`) ON DELETE CASCADE,
  FOREIGN KEY (`uploaded_by`) REFERENCES `USER`(`user_id`)
) ENGINE=InnoDB;

-- 11. ATTENDANCE TABLE (Daily Records)
CREATE TABLE IF NOT EXISTS `ATTENDANCE` (
  `attendance_id` INT AUTO_INCREMENT PRIMARY KEY,
  `employee_id` INT NOT NULL,
  `import_id` INT NULL,
  `work_date` DATE NOT NULL,
  `check_in` DATETIME NULL,
  `check_out` DATETIME NULL,
  `status` VARCHAR(20) NOT NULL, -- 'Present', 'Late', 'Half-Day', 'Absent'
  `overtime_hours` DECIMAL(5,2) DEFAULT 0.00,
  FOREIGN KEY (`employee_id`) REFERENCES `EMPLOYEE`(`employee_id`) ON DELETE CASCADE,
  FOREIGN KEY (`import_id`) REFERENCES `ATTENDANCE_IMPORT`(`import_id`) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ============================================================
-- ACCOUNTS & FINANCE (module 04). The same DDL is also applied
-- automatically on server boot by src/config/db.js.
-- ============================================================

CREATE TABLE IF NOT EXISTS `finance_financial_year` (
  `fy_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `fy_name` VARCHAR(30) NOT NULL,
  `start_date` DATE NOT NULL,
  `end_date` DATE NOT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `is_closed` TINYINT(1) NOT NULL DEFAULT 0,
  UNIQUE KEY `uk_fy_company_name` (`company_id`, `fy_name`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_account` (
  `account_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `account_code` VARCHAR(20) NOT NULL,
  `account_name` VARCHAR(120) NOT NULL,
  `account_type` ENUM('Asset','Liability','Equity','Income','Expense') NOT NULL,
  `sub_group` VARCHAR(80) DEFAULT 'General',
  `opening_balance` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `current_balance` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_fa_company_code` (`company_id`, `account_code`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_voucher` (
  `voucher_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `voucher_no` VARCHAR(40) NOT NULL,
  `voucher_type` ENUM('Payment','Receipt','Journal','Contra','Sales','Purchase') NOT NULL,
  `voucher_date` DATE NOT NULL,
  `narration` TEXT NULL,
  `total_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `status` ENUM('POSTED','CANCELLED') NOT NULL DEFAULT 'POSTED',
  `cancel_reason` VARCHAR(255) NULL,
  `created_by` INT NULL,
  `cancelled_by` INT NULL,
  `cancelled_at` DATETIME NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_fv_company_no` (`company_id`, `voucher_no`),
  INDEX `idx_fv_date` (`voucher_date`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_voucher_item` (
  `item_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `voucher_id` INT NOT NULL,
  `account_id` INT NOT NULL,
  `debit_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `credit_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `description` VARCHAR(255) NULL,
  `department_id` INT NULL,
  `project_id` INT NULL,
  INDEX `idx_fvi_voucher` (`voucher_id`),
  INDEX `idx_fvi_account` (`account_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_vendor` (
  `vendor_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `vendor_name` VARCHAR(150) NOT NULL,
  `tax_no` VARCHAR(50) NULL,
  `gstin` VARCHAR(20) NULL,
  `pan` VARCHAR(20) NULL,
  `contact` VARCHAR(100) NULL,
  `address` TEXT NULL,
  `payment_terms` VARCHAR(80) NULL,
  `bank_name` VARCHAR(120) NULL,
  `bank_account_no` VARCHAR(60) NULL,
  `bank_ifsc` VARCHAR(20) NULL,
  `credit_limit` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  UNIQUE KEY `uk_fvend_company_name` (`company_id`, `vendor_name`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_customer` (
  `customer_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `customer_name` VARCHAR(150) NOT NULL,
  `tax_no` VARCHAR(50) NULL,
  `gstin` VARCHAR(20) NULL,
  `pan` VARCHAR(20) NULL,
  `contact` VARCHAR(100) NULL,
  `address` TEXT NULL,
  `credit_limit` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `payment_terms` VARCHAR(80) NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  UNIQUE KEY `uk_fcust_company_name` (`company_id`, `customer_name`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_bank_account` (
  `bank_account_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `bank_name` VARCHAR(120) NOT NULL,
  `account_ref` VARCHAR(80) NOT NULL,
  `ifsc` VARCHAR(30) NULL,
  `branch` VARCHAR(120) NULL,
  `account_type` VARCHAR(40) NULL,
  `current_balance` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  UNIQUE KEY `uk_fbank_company_ref` (`company_id`, `account_ref`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_bill` (
  `bill_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `vendor_id` INT NOT NULL,
  `bill_no` VARCHAR(40) NOT NULL,
  `bill_date` DATE NOT NULL,
  `due_date` DATE NULL,
  `po_no` VARCHAR(60) NULL,
  `grn_no` VARCHAR(60) NULL,
  `po_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `grn_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `total_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `tax_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `match_status` ENUM('NOT_CHECKED','MATCHED','FLAGGED') NOT NULL DEFAULT 'NOT_CHECKED',
  `status` ENUM('DRAFT','FLAGGED','APPROVED','PAID','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  `hold_reason` VARCHAR(255) NULL,
  `created_by` INT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_fbill_company_no` (`company_id`, `bill_no`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_bill_item` (
  `item_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `bill_id` INT NOT NULL,
  `description` VARCHAR(255) NULL,
  `qty` DECIMAL(12,3) NOT NULL DEFAULT 1,
  `rate` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  INDEX `idx_fbi_bill` (`bill_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_invoice` (
  `invoice_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `customer_id` INT NOT NULL,
  `project_id` INT NULL,
  `invoice_no` VARCHAR(40) NOT NULL,
  `invoice_date` DATE NOT NULL,
  `due_date` DATE NULL,
  `total_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `tax_amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `status` ENUM('DRAFT','ISSUED','PAID','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  `created_by` INT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_finv_company_no` (`company_id`, `invoice_no`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_invoice_item` (
  `item_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `invoice_id` INT NOT NULL,
  `description` VARCHAR(255) NULL,
  `qty` DECIMAL(12,3) NOT NULL DEFAULT 1,
  `rate` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  `amount` DECIMAL(14,2) NOT NULL DEFAULT 0.00,
  INDEX `idx_fii_invoice` (`invoice_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_payment` (
  `payment_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `bill_id` INT NULL,
  `invoice_id` INT NULL,
  `bank_account_id` INT NOT NULL,
  `pay_date` DATE NOT NULL,
  `amount` DECIMAL(14,2) NOT NULL,
  `mode` ENUM('NEFT','RTGS','Cheque','Cash','UPI') NOT NULL DEFAULT 'NEFT',
  `reference_no` VARCHAR(80) NULL,
  `voucher_id` INT NULL,
  `created_by` INT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_fpay_company_date` (`company_id`, `pay_date`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_number_series` (
  `series_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `doc_type` ENUM('INVOICE','BILL') NOT NULL,
  `prefix` VARCHAR(12) NOT NULL DEFAULT 'DOC',
  `last_number` INT NOT NULL DEFAULT 0,
  `updated_by` INT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_fns_company_type` (`company_id`, `doc_type`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `finance_audit_log` (
  `log_id` INT AUTO_INCREMENT PRIMARY KEY,
  `company_id` INT NOT NULL,
  `entity` VARCHAR(40) NOT NULL,
  `entity_id` INT NULL,
  `action` VARCHAR(30) NOT NULL,
  `summary` VARCHAR(255) NULL,
  `before_json` TEXT NULL,
  `after_json` TEXT NULL,
  `created_by` INT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_fal_company_date` (`company_id`, `created_at`),
  INDEX `idx_fal_entity` (`company_id`, `entity`, `entity_id`)
) ENGINE=InnoDB;

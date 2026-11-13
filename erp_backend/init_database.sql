sys_config-- ============================================================================
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

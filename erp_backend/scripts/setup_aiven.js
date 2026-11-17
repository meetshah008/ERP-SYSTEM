const mysql = require('mysql2/promise');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.join(__dirname, '../.env') });

async function initAiven() {
  const dbUrl = process.env.DATABASE_URL;
  const config = dbUrl ? {
    uri: dbUrl,
    ssl: { rejectUnauthorized: false },
    multipleStatements: true
  } : {
    host: process.env.DB_HOST || 'mysql-3a44ae2e-erp-system.a.aivencloud.com',
    port: parseInt(process.env.DB_PORT || '11850', 10),
    user: process.env.DB_USER || 'avnadmin',
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || 'defaultdb',
    ssl: { rejectUnauthorized: false },
    multipleStatements: true
  };

  console.log('⏳ Connecting to Aiven MySQL...');
  let connection;
  try {
    connection = await mysql.createConnection(config);
    console.log('✅ Connected to Aiven MySQL successfully!');

    // Read init_database.sql
    const sqlPath = path.join(__dirname, '../init_database.sql');
    let sql = fs.readFileSync(sqlPath, 'utf8');

    // Remove CREATE DATABASE and USE statements so it uses defaultdb
    sql = sql.replace(/CREATE DATABASE[\s\S]*?;/gi, '');
    sql = sql.replace(/USE\s+`?manufacturing_erp`?;/gi, '');

    console.log('⏳ Creating foundation tables in Aiven defaultdb...');
    await connection.query(sql);
    console.log('✅ Foundation tables created successfully!');

    // Now create project and task tables
    console.log('⏳ Creating project & task management tables...');
    await connection.query(`
      CREATE TABLE IF NOT EXISTS project (
        project_id INT AUTO_INCREMENT PRIMARY KEY,
        project_code VARCHAR(50) UNIQUE NOT NULL,
        project_name VARCHAR(150) NOT NULL,
        client_name VARCHAR(100) DEFAULT NULL,
        description TEXT DEFAULT NULL,
        department_id INT DEFAULT NULL,
        head_user_id INT DEFAULT NULL,
        project_leader_id INT DEFAULT NULL,
        status ENUM('Active', 'Planning', 'Completed', 'On Hold') DEFAULT 'Active',
        priority ENUM('Low', 'Medium', 'High', 'Urgent') DEFAULT 'Medium',
        start_date DATE DEFAULT NULL,
        target_end_date DATE DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS task (
        task_id INT AUTO_INCREMENT PRIMARY KEY,
        title VARCHAR(150) NOT NULL,
        description TEXT NULL,
        assigned_to INT NULL,
        project_id INT NULL,
        priority ENUM('Low', 'Medium', 'High', 'Urgent') DEFAULT 'Medium',
        status ENUM('Pending', 'In Progress', 'Completed', 'On Hold') DEFAULT 'Pending',
        due_date DATE NULL,
        estimated_hours DECIMAL(6,2) DEFAULT 0.00,
        actual_hours DECIMAL(6,2) DEFAULT 0.00,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS project_member (
        id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        employee_id INT NOT NULL,
        role_in_project VARCHAR(50) DEFAULT 'Member',
        assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_project_employee (project_id, employee_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS task_assignees (
        id INT AUTO_INCREMENT PRIMARY KEY,
        task_id INT NOT NULL,
        employee_id INT NOT NULL,
        assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_task_emp (task_id, employee_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS task_subtask (
        subtask_id INT AUTO_INCREMENT PRIMARY KEY,
        task_id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
        is_completed BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS project_timesheet (
        timesheet_id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        task_id INT NULL,
        employee_id INT NOT NULL,
        log_date DATE NOT NULL,
        hours_spent DECIMAL(5, 2) NOT NULL,
        description TEXT,
        status ENUM('Submitted', 'Approved', 'Rejected') DEFAULT 'Submitted',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS project_material (
        material_id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        material_name VARCHAR(150) NOT NULL,
        unit VARCHAR(20) DEFAULT 'PCS',
        quantity_required DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
        quantity_used DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
        cost_per_unit DECIMAL(10, 2) DEFAULT 0.00,
        status ENUM('Required', 'Issued', 'Consumed', 'Returned') DEFAULT 'Required',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS LEAVE_REQUEST (
        leave_id INT AUTO_INCREMENT PRIMARY KEY,
        company_id INT NOT NULL DEFAULT 1,
        employee_id INT NOT NULL,
        leave_type VARCHAR(50) NOT NULL,
        start_date DATE NOT NULL,
        end_date DATE NOT NULL,
        total_days INT NOT NULL DEFAULT 1,
        reason TEXT,
        status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await connection.query(`
      CREATE TABLE IF NOT EXISTS EMPLOYEE_PERMISSION (
        employee_id INT NOT NULL,
        permission_key VARCHAR(60) NOT NULL,
        is_granted TINYINT(1) DEFAULT 1,
        PRIMARY KEY (employee_id, permission_key)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    console.log('🎉 ALL TABLES CREATED SUCCESSFULLY IN AIVEN MYSQL!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error initializing Aiven DB:', err.message);
    process.exit(1);
  } finally {
    if (connection) await connection.end();
  }
}

initAiven();

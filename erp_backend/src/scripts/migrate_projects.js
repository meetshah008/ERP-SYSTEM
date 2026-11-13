const db = require('../config/db');

async function migrateProjects() {
  try {
    console.log('🔄 Running Project & Task Management Database Migration...');

    // 1. PROJECT TABLE
    await db.query(`
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
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (department_id) REFERENCES department(department_id) ON DELETE SET NULL,
        FOREIGN KEY (head_user_id) REFERENCES employee(employee_id) ON DELETE SET NULL,
        FOREIGN KEY (project_leader_id) REFERENCES employee(employee_id) ON DELETE SET NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);
    console.log('✅ 1. project table ready');

    // 2. PROJECT_MEMBER TABLE (Team Members)
    await db.query(`
      CREATE TABLE IF NOT EXISTS project_member (
        id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        employee_id INT NOT NULL,
        role_in_project VARCHAR(50) DEFAULT 'Member',
        assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_project_employee (project_id, employee_id),
        FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE CASCADE,
        FOREIGN KEY (employee_id) REFERENCES employee(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);
    console.log('✅ 2. project_member table ready');

    // 3. ALTER TASK TABLE (Add project_id, estimated_hours, actual_hours if missing)
    const [taskCols] = await db.query(`SHOW COLUMNS FROM task`);
    const colNames = taskCols.map(c => c.Field);

    if (!colNames.includes('project_id')) {
      await db.query(`
        ALTER TABLE task 
        ADD COLUMN project_id INT NULL AFTER assigned_to,
        ADD CONSTRAINT fk_task_project FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE CASCADE
      `);
      console.log('✅ 3a. Added project_id to task');
    }

    if (!colNames.includes('estimated_hours')) {
      await db.query(`ALTER TABLE task ADD COLUMN estimated_hours DECIMAL(6,2) DEFAULT 0.00`);
      console.log('✅ 3b. Added estimated_hours to task');
    }

    if (!colNames.includes('actual_hours')) {
      await db.query(`ALTER TABLE task ADD COLUMN actual_hours DECIMAL(6,2) DEFAULT 0.00`);
      console.log('✅ 3c. Added actual_hours to task');
    }

    // 4. TASK_SUBTASK TABLE (Checklist inside tasks)
    await db.query(`
      CREATE TABLE IF NOT EXISTS task_subtask (
        subtask_id INT AUTO_INCREMENT PRIMARY KEY,
        task_id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
        is_completed BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);
    console.log('✅ 4. task_subtask table ready');

    // 5. PROJECT_TIMESHEET TABLE (Daily work hours log)
    await db.query(`
      CREATE TABLE IF NOT EXISTS project_timesheet (
        timesheet_id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        task_id INT NULL,
        employee_id INT NOT NULL,
        log_date DATE NOT NULL,
        hours_spent DECIMAL(5, 2) NOT NULL,
        description TEXT,
        status ENUM('Submitted', 'Approved', 'Rejected') DEFAULT 'Submitted',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE CASCADE,
        FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE SET NULL,
        FOREIGN KEY (employee_id) REFERENCES employee(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);
    console.log('✅ 5. project_timesheet table ready');

    // 6. PROJECT_MATERIAL TABLE (Raw materials required/used)
    await db.query(`
      CREATE TABLE IF NOT EXISTS project_material (
        material_id INT AUTO_INCREMENT PRIMARY KEY,
        project_id INT NOT NULL,
        material_name VARCHAR(150) NOT NULL,
        unit VARCHAR(20) DEFAULT 'PCS',
        quantity_required DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
        quantity_used DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
        cost_per_unit DECIMAL(10, 2) DEFAULT 0.00,
        status ENUM('Required', 'Issued', 'Consumed', 'Returned') DEFAULT 'Required',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (project_id) REFERENCES project(project_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);
    console.log('✅ 6. project_material table ready');

    // 7. INSERT A SAMPLE PROJECT IF NONE EXISTS
    const [existing] = await db.query('SELECT COUNT(*) as cnt FROM project');
    if (existing[0].cnt === 0) {
      const [emp] = await db.query('SELECT employee_id FROM employee LIMIT 1');
      const empId = emp.length > 0 ? emp[0].employee_id : null;

      const [insertPrj] = await db.query(`
        INSERT INTO project (project_code, project_name, client_name, description, head_user_id, project_leader_id, status, priority, start_date, target_end_date)
        VALUES ('PRJ-001', 'Heavy Duty Pipe Brackets Batch A', 'Apex Engineering', 'Fabrication of 250 units with anti-corrosion coating', ?, ?, 'Active', 'High', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 20 DAY))
      `, [empId, empId]);

      const newProjectId = insertPrj.insertId;

      if (empId) {
        await db.query(`
          INSERT INTO project_member (project_id, employee_id, role_in_project)
          VALUES (?, ?, 'Lead Fabricator')
        `, [newProjectId, empId]);
      }

      // Link any existing tasks to this project
      await db.query(`UPDATE task SET project_id = ? WHERE project_id IS NULL`, [newProjectId]);

      // Add a couple of subtasks to existing tasks
      const [tasks] = await db.query('SELECT task_id FROM task LIMIT 1');
      if (tasks.length > 0) {
        const tId = tasks[0].task_id;
        await db.query(`
          INSERT INTO task_subtask (task_id, title, is_completed) VALUES
          (?, 'Raw sheet metal cut to size (10mm)', 1),
          (?, 'CNC Drilling and Hole Punching', 0),
          (?, 'TIG Welding and joint inspection', 0)
        `, [tId, tId, tId]);
      }

      // Add sample material
      await db.query(`
        INSERT INTO project_material (project_id, material_name, unit, quantity_required, quantity_used, cost_per_unit, status)
        VALUES 
        (?, 'Mild Steel Sheet 10mm', 'KG', 150.00, 50.00, 85.00, 'Issued'),
        (?, 'M10 High Tensile Bolts', 'PCS', 500.00, 100.00, 4.50, 'Issued')
      `, [newProjectId, newProjectId]);

      console.log('✅ 7. Sample Project & Data Seeded successfully!');
    }

    console.log('🎉 Project Management Tables Migration Completed Successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration Error:', error);
    process.exit(1);
  }
}

migrateProjects();

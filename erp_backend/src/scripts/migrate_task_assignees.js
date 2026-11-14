const db = require('../config/db');

async function migrate() {
  try {
    await db.query(`
      CREATE TABLE IF NOT EXISTS task_assignees (
        id INT AUTO_INCREMENT PRIMARY KEY,
        task_id INT NOT NULL,
        employee_id INT NOT NULL,
        assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_task_emp (task_id, employee_id),
        FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE CASCADE,
        FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);
    console.log('✅ task_assignees table created / verified successfully!');

    // Populate existing assigned_to into task_assignees
    await db.query(`
      INSERT IGNORE INTO task_assignees (task_id, employee_id)
      SELECT task_id, assigned_to FROM task WHERE assigned_to IS NOT NULL;
    `);
    console.log('✅ Existing task assignments populated into task_assignees!');
    process.exit(0);
  } catch (e) {
    console.error('Error during migration:', e);
    process.exit(1);
  }
}

migrate();

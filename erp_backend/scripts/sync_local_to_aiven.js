const mysql = require('mysql2/promise');

async function syncLocalToAiven() {
  console.log('🔄 Starting Local -> Aiven Data Migration...');

  let localConn;
  let aivenConn;

  try {
    localConn = await mysql.createConnection({
      host: 'localhost',
      port: 3306,
      user: 'root',
      password: '1234',
      database: 'manufacturing_erp'
    });
    console.log('✅ Connected to Local MySQL!');

    aivenConn = await mysql.createConnection({
      host: process.env.DB_HOST || 'mysql-3a44ae2e-erp-system.a.aivencloud.com',
      port: parseInt(process.env.DB_PORT || '11850', 10),
      user: process.env.DB_USER || 'avnadmin',
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME || 'defaultdb',
      ssl: { rejectUnauthorized: false }
    });
    console.log('✅ Connected to Aiven Cloud MySQL!');

    // Temporarily disable foreign key checks in Aiven for smooth batch insert
    await aivenConn.query('SET FOREIGN_KEY_CHECKS = 0');

    // Make sure notification and employee_increment tables exist on Aiven if not already
    await aivenConn.query(`
      CREATE TABLE IF NOT EXISTS notification (
        notification_id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        title VARCHAR(150) NOT NULL,
        message TEXT NOT NULL,
        module VARCHAR(50) DEFAULT 'GENERAL',
        is_read TINYINT(1) DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    await aivenConn.query(`
      CREATE TABLE IF NOT EXISTS employee_increment (
        increment_id INT AUTO_INCREMENT PRIMARY KEY,
        employee_id INT NOT NULL,
        old_salary DECIMAL(12,2) NOT NULL,
        new_salary DECIMAL(12,2) NOT NULL,
        increment_date DATE NOT NULL,
        effective_date DATE NOT NULL,
        remarks TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    `);

    // Tables in insertion order
    const tables = [
      'company',
      'branch',
      'department',
      'role',
      'permission',
      'role_permission',
      'user',
      'employee',
      'employee_permission',
      'employee_increment',
      'leave_request',
      'notification',
      'project',
      'project_member',
      'task',
      'task_assignees',
      'task_subtask',
      'project_timesheet',
      'project_material',
      'attendance_import',
      'attendance',
      'audit_log'
    ];

    let totalCopied = 0;

    for (const tbl of tables) {
      try {
        const [rows] = await localConn.query(`SELECT * FROM \`${tbl}\``);
        if (rows.length === 0) {
          console.log(`⚪ Table \`${tbl}\`: 0 rows (skipped)`);
          continue;
        }

        // Check if table exists in Aiven
        let targetTable = tbl;
        const [aivenTables] = await aivenConn.query(`SHOW TABLES LIKE ?`, [tbl]);
        if (aivenTables.length === 0) {
          const [upperTables] = await aivenConn.query(`SHOW TABLES LIKE ?`, [tbl.toUpperCase()]);
          if (upperTables.length > 0) {
            targetTable = tbl.toUpperCase();
          } else {
            // Create table using local CREATE TABLE
            const [createTbl] = await localConn.query(`SHOW CREATE TABLE \`${tbl}\``);
            const createSql = createTbl[0]['Create Table'];
            await aivenConn.query(createSql);
            console.log(`🔨 Created missing table \`${targetTable}\` in Aiven!`);
          }
        }

        // Sync missing columns from local to Aiven
        const [localCols] = await localConn.query(`SHOW COLUMNS FROM \`${tbl}\``);
        const [aivenCols] = await aivenConn.query(`SHOW COLUMNS FROM \`${targetTable}\``);
        const aivenColNames = aivenCols.map(c => c.Field.toLowerCase());

        for (const col of localCols) {
          if (!aivenColNames.includes(col.Field.toLowerCase())) {
            const nullStr = col.Null === 'YES' ? 'NULL' : 'NOT NULL';
            const defaultStr = col.Default !== null ? `DEFAULT '${col.Default}'` : (col.Null === 'YES' ? 'DEFAULT NULL' : '');
            try {
              await aivenConn.query(`ALTER TABLE \`${targetTable}\` ADD COLUMN \`${col.Field}\` ${col.Type} ${nullStr} ${defaultStr}`);
              console.log(`➕ Added missing column \`${col.Field}\` to \`${targetTable}\` in Aiven`);
            } catch (alterErr) {
              // Ignore if already added
            }
          }
        }

        // If task table, relax status column to VARCHAR(50)
        if (tbl.toLowerCase() === 'task') {
          try {
            await aivenConn.query(`ALTER TABLE \`${targetTable}\` MODIFY COLUMN \`status\` VARCHAR(50) DEFAULT 'Pending'`);
          } catch (_) {}
        }

        let insertedCount = 0;
        for (const row of rows) {
          const keys = Object.keys(row);
          const values = Object.values(row);
          const placeholders = keys.map(() => '?').join(', ');
          const columns = keys.map(k => `\`${k}\``).join(', ');
          const updateClause = keys.map(k => `\`${k}\`=VALUES(\`${k}\`)`).join(', ');

          const sql = `INSERT INTO \`${targetTable}\` (${columns}) VALUES (${placeholders}) ON DUPLICATE KEY UPDATE ${updateClause}`;
          await aivenConn.query(sql, values);
          insertedCount++;
        }

        console.log(`✅ Table \`${targetTable}\`: Synced ${insertedCount} rows!`);
        totalCopied += insertedCount;
      } catch (err) {
        console.warn(`⚠️ Warning syncing \`${tbl}\`:`, err.message);
      }
    }

    // Re-enable foreign key checks
    await aivenConn.query('SET FOREIGN_KEY_CHECKS = 1');

    console.log(`\n🎉 DATA SYNC COMPLETE! Total ${totalCopied} records successfully migrated to Aiven Cloud!`);
  } catch (e) {
    console.error('❌ Data migration failed:', e);
  } finally {
    if (localConn) await localConn.end();
    if (aivenConn) await aivenConn.end();
    process.exit(0);
  }
}

syncLocalToAiven();

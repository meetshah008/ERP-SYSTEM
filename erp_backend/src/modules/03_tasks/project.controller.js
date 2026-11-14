const db = require('../../config/db');

// 1. NAYA PROJECT CREATE KARNA (Leader & Team ke sath)
exports.createProject = async (req, res) => {
  try {
    const {
      project_code,
      project_name,
      client_name,
      description,
      department_id,
      head_user_id,
      project_leader_id,
      priority,
      start_date,
      target_end_date,
      member_ids // Array of employee_ids [1, 2, 3]
    } = req.body;

    if (!project_code || !project_name) {
      return res.status(400).json({ success: false, message: 'Project Code aur Name zaroori hain!' });
    }

    // A. Project table mein entry daali
    const [result] = await db.query(
      `INSERT INTO project (
        project_code, project_name, client_name, description,
        department_id, head_user_id, project_leader_id,
        priority, start_date, target_end_date, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Active')`,
      [
        project_code,
        project_name,
        client_name || null,
        description || null,
        department_id || null,
        head_user_id || null,
        project_leader_id || null,
        priority || 'Medium',
        start_date || null,
        target_end_date || null
      ]
    );

    const projectId = result.insertId;

    // B. Agar Team Members select kiye hain toh unhe project_member mein add kiya
    if (Array.isArray(member_ids) && member_ids.length > 0) {
      for (const empId of member_ids) {
        await db.query(
          `INSERT IGNORE INTO project_member (project_id, employee_id, role_in_project) VALUES (?, ?, 'Member')`,
          [projectId, empId]
        );
      }
    }

    // C. Agar project leader bhi select kiya hai aur members mein nahi hai toh use bhi add kiya
    if (project_leader_id) {
      await db.query(
        `INSERT IGNORE INTO project_member (project_id, employee_id, role_in_project) VALUES (?, ?, 'Team Leader')`,
        [projectId, project_leader_id]
      );
    }

    return res.status(201).json({
      success: true,
      message: 'Project created successfully with Team Leader and Members!',
      project_id: projectId
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 2. SAARE PROJECTS KI LIST LANA (Dashboard ke cards ke liye)
exports.getProjects = async (req, res) => {
  try {
    const [projects] = await db.query(`
      SELECT
        p.*,
        leader.full_name as leader_name,
        head.full_name as head_name,
        dept.name as department_name,
        (SELECT COUNT(*) FROM project_member pm WHERE pm.project_id = p.project_id) as total_members,
        (SELECT COUNT(*) FROM task t WHERE t.project_id = p.project_id) as total_tasks,
        (SELECT COUNT(*) FROM task t WHERE t.project_id = p.project_id AND t.status = 'DONE') as completed_tasks
      FROM project p
      LEFT JOIN employee leader ON p.project_leader_id = leader.employee_id
      LEFT JOIN employee head ON p.head_user_id = head.employee_id
      LEFT JOIN department dept ON p.department_id = dept.department_id
      ORDER BY p.project_id DESC
    `);

    return res.status(200).json({ success: true, data: projects });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 3. EK PROJECT KA PURA DATA (Tasks, Subtasks, Team, Timesheets, Materials)
exports.getProjectDetails = async (req, res) => {
  try {
    const { id } = req.params;

    // A. Project Info
    const [prj] = await db.query(`
      SELECT p.*, leader.full_name as leader_name, dept.name as department_name
      FROM project p
      LEFT JOIN employee leader ON p.project_leader_id = leader.employee_id
      LEFT JOIN department dept ON p.department_id = dept.department_id
      WHERE p.project_id = ?
    `, [id]);

    if (prj.length === 0) {
      return res.status(404).json({ success: false, message: 'Project nahi mila!' });
    }

    // B. Team Members
    const [members] = await db.query(`
      SELECT pm.id, pm.role_in_project, pm.assigned_at, e.employee_id, e.full_name, e.emp_code
      FROM project_member pm
      JOIN employee e ON pm.employee_id = e.employee_id
      WHERE pm.project_id = ?
    `, [id]);

    // C. Tasks aur unke Subtasks
    const [tasks] = await db.query(`
      SELECT t.*, e.full_name as assigned_worker, e.emp_code
      FROM task t
      LEFT JOIN employee e ON t.assigned_to = e.employee_id
      WHERE t.project_id = ?
      ORDER BY t.task_id DESC
    `, [id]);

    // Har task ke subtasks aur assignees attach karna
    for (const task of tasks) {
      const [subtasks] = await db.query(
        `SELECT * FROM task_subtask WHERE task_id = ? ORDER BY subtask_id ASC`,
        [task.task_id]
      );
      task.subtasks = subtasks;

      const [assignees] = await db.query(
        `SELECT e.employee_id, e.full_name, e.emp_code, e.designation
         FROM task_assignees ta
         JOIN employee e ON ta.employee_id = e.employee_id
         WHERE ta.task_id = ?`,
        [task.task_id]
      );
      task.assignees = assignees;
      if (assignees.length > 0) {
        task.assigned_worker = assignees.map(a => a.full_name).join(', ');
      }
    }

    // D. Timesheets (Kisne kitne ghante kaam kiya)
    const [timesheets] = await db.query(`
      SELECT ts.*, e.full_name as worker_name, t.title as task_title
      FROM project_timesheet ts
      JOIN employee e ON ts.employee_id = e.employee_id
      LEFT JOIN task t ON ts.task_id = t.task_id
      WHERE ts.project_id = ?
      ORDER BY ts.log_date DESC
    `, [id]);

    // E. Materials Required & Used
    const [materials] = await db.query(`
      SELECT * FROM project_material WHERE project_id = ? ORDER BY material_id DESC
    `, [id]);

    return res.status(200).json({
      success: true,
      data: {
        project: prj[0],
        members,
        tasks,
        timesheets,
        materials
      }
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4. US PROJECT KE ANDAR TASK + SUBTASKS CREATE KARNA
exports.createProjectTask = async (req, res) => {
  try {
    const { id } = req.params; // project_id
    const { title, description, assigned_to, priority, due_date, estimated_hours, subtasks } = req.body;

    if (!title || !assigned_to) {
      return res.status(400).json({ success: false, message: 'Title aur Worker select karna zaroori hai!' });
    }

    const [taskRes] = await db.query(`
      INSERT INTO task (project_id, assigned_to, title, description, priority, status, due_date, estimated_hours)
      VALUES (?, ?, ?, ?, ?, 'TODO', ?, ?)
    `, [id, assigned_to, title, description || '', priority || 'MEDIUM', due_date || null, estimated_hours || 0]);

    const taskId = taskRes.insertId;

    // Subtasks insert karna agar diye gaye hain
    if (Array.isArray(subtasks) && subtasks.length > 0) {
      for (const st of subtasks) {
        if (st && st.trim()) {
          await db.query(
            `INSERT INTO task_subtask (task_id, title, is_completed) VALUES (?, ?, 0)`,
            [taskId, st.trim()]
          );
        }
      }
    }

    return res.status(201).json({
      success: true,
      message: 'Project task created with subtasks checklist!',
      task_id: taskId
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 5. SUBTASK TICK/UNTICK KARNA (Checklist Toggle)
exports.toggleSubtask = async (req, res) => {
  try {
    const { subtaskId } = req.params;
    const { is_completed } = req.body; // true ya false (1 ya 0)

    await db.query(
      `UPDATE task_subtask SET is_completed = ? WHERE subtask_id = ?`,
      [is_completed ? 1 : 0, subtaskId]
    );

    return res.status(200).json({ success: true, message: 'Subtask status updated!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 5B. NAYA SUBTASK DIRECTLY ADD KARNA (Task ke andar)
exports.addSubtask = async (req, res) => {
  try {
    const { taskId } = req.params;
    const { title } = req.body;

    if (!title || !title.trim()) {
      return res.status(400).json({ success: false, message: 'Subtask title zaroori hai!' });
    }

    const [result] = await db.query(
      `INSERT INTO task_subtask (task_id, title, is_completed) VALUES (?, ?, 0)`,
      [taskId, title.trim()]
    );

    return res.status(201).json({
      success: true,
      message: 'Subtask added successfully!',
      subtask_id: result.insertId
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 6. TIMESHEET LOG KARNA (Hours spent)
exports.logTimesheet = async (req, res) => {
  try {
    const { id } = req.params; // project_id
    const { task_id, employee_id, log_date, hours_spent, description } = req.body;

    if (!employee_id || !hours_spent) {
      return res.status(400).json({ success: false, message: 'Worker aur Hours zaroori hain!' });
    }

    await db.query(`
      INSERT INTO project_timesheet (project_id, task_id, employee_id, log_date, hours_spent, description)
      VALUES (?, ?, ?, ?, ?, ?)
    `, [id, task_id || null, employee_id, log_date || new Date(), hours_spent, description || '']);

    // Agar task_id diya hai toh task ke actual_hours mein bhi add kiya
    if (task_id) {
      await db.query(`
        UPDATE task SET actual_hours = actual_hours + ? WHERE task_id = ?
      `, [hours_spent, task_id]);
    }

    return res.status(201).json({ success: true, message: 'Timesheet logged successfully!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 7. PROJECT MATERIAL ADD KARNA
exports.addProjectMaterial = async (req, res) => {
  try {
    const { id } = req.params; // project_id
    const { material_name, unit, quantity_required, cost_per_unit } = req.body;

    if (!material_name || !quantity_required) {
      return res.status(400).json({ success: false, message: 'Material Name aur Quantity zaroori hain!' });
    }

    await db.query(`
      INSERT INTO project_material (project_id, material_name, unit, quantity_required, quantity_used, cost_per_unit, status)
      VALUES (?, ?, ?, ?, 0.00, ?, 'Required')
    `, [id, material_name, unit || 'PCS', quantity_required, cost_per_unit || 0.00]);

    return res.status(201).json({ success: true, message: 'Material added to project requirements!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
// 8. PROJECT UPDATE KARNA (Edit details & team)
exports.updateProject = async (req, res) => {
  try {
    const { id } = req.params;
    const {
      project_code,
      project_name,
      client_name,
      description,
      department_id,
      head_user_id,
      project_leader_id,
      priority,
      status,
      start_date,
      target_end_date,
      member_ids
    } = req.body;

    // A. Project details update ki
    await db.query(
      `UPDATE project SET
        project_code = COALESCE(?, project_code),
        project_name = COALESCE(?, project_name),
        client_name = ?,
        description = ?,
        department_id = ?,
        head_user_id = ?,
        project_leader_id = ?,
        priority = COALESCE(?, priority),
        status = COALESCE(?, status),
        start_date = ?,
        target_end_date = ?
      WHERE project_id = ?`,
      [
        project_code || null,
        project_name || null,
        client_name !== undefined ? client_name : null,
        description !== undefined ? description : null,
        department_id !== undefined ? department_id : null,
        head_user_id !== undefined ? head_user_id : null,
        project_leader_id !== undefined ? project_leader_id : null,
        priority || null,
        status || null,
        start_date !== undefined ? start_date : null,
        target_end_date !== undefined ? target_end_date : null,
        id
      ]
    );

    // B. Agar Team Members ki list aayi hai toh use project_member table mein sync kiya
    if (Array.isArray(member_ids)) {
      // Purane members hataye
      await db.query(`DELETE FROM project_member WHERE project_id = ?`, [id]);

      // Naye members jode
      for (const empId of member_ids) {
        if (empId) {
          await db.query(
            `INSERT IGNORE INTO project_member (project_id, employee_id, role_in_project) VALUES (?, ?, 'Member')`,
            [id, empId]
          );
        }
      }

      // Leader ko bhi team member mein Team Leader role ke sath ensure kiya
      if (project_leader_id) {
        await db.query(
          `INSERT INTO project_member (project_id, employee_id, role_in_project) VALUES (?, ?, 'Team Leader')
           ON DUPLICATE KEY UPDATE role_in_project = 'Team Leader'`,
          [id, project_leader_id]
        );
      }
    }

    return res.status(200).json({ success: true, message: 'Project updated successfully!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
// 9. PROJECT DELETE KARNA (Cascading safe delete)
exports.deleteProject = async (req, res) => {
  try {
    const { id } = req.params;

    // Step-by-step child tables clean karna
    await db.query(`DELETE FROM task_subtask WHERE task_id IN (SELECT task_id FROM task WHERE project_id = ?)`, [id]);
    await db.query(`DELETE FROM project_timesheet WHERE project_id = ?`, [id]);
    await db.query(`DELETE FROM project_material WHERE project_id = ?`, [id]);
    await db.query(`DELETE FROM project_member WHERE project_id = ?`, [id]);
    await db.query(`DELETE FROM task WHERE project_id = ?`, [id]);

    // Main project delete kiya
    const [result] = await db.query(`DELETE FROM project WHERE project_id = ?`, [id]);

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Project nahi mila!' });
    }

    return res.status(200).json({ success: true, message: 'Project aur uske saare tasks safely delete ho gaye!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
// 10. SUBTASK DELETE KARNA
exports.deleteSubtask = async (req, res) => {
  try {
    const { subtaskId } = req.params;

    const [result] = await db.query(`DELETE FROM task_subtask WHERE subtask_id = ?`, [subtaskId]);

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Subtask nahi mila!' });
    }

    return res.status(200).json({ success: true, message: 'Subtask deleted successfully!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 11. PROJECT MATERIAL / COMPONENT DELETE KARNA
exports.deleteProjectMaterial = async (req, res) => {
  try {
    const { materialId } = req.params;
    const [result] = await db.query(`DELETE FROM project_material WHERE material_id = ?`, [materialId]);

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Component nahi mila!' });
    }

    return res.status(200).json({ success: true, message: 'Component successfully removed!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
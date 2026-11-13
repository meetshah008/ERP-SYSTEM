const db = require('../../config/db');

// 1. NAYA TASK ASSIGN KARNA (General ya Project Task)
exports.createTask = async (req, res) => {
  try {
    const { assigned_to, title, description, priority, due_date, project_id, estimated_hours, subtasks } = req.body;

    if (!assigned_to || !title) {
      return res.status(400).json({ success: false, message: 'Assignee aur Task ka Title zaroori hai!' });
    }

    const [result] = await db.query(
      `INSERT INTO task (assigned_to, project_id, title, description, priority, status, due_date, estimated_hours)
       VALUES (?, ?, ?, ?, ?, 'TODO', ?, ?)`,
      [assigned_to, project_id || null, title, description || '', priority || 'MEDIUM', due_date || null, estimated_hours || 0]
    );

    const taskId = result.insertId;

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
      message: 'Task successfully created!',
      task_id: taskId
    });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 2. SAARE TASKS KI LIST DEKHNA (Get All Tasks with Project name if linked)
exports.getTasks = async (req, res) => {
  try {
    const [tasks] = await db.query(
      `SELECT t.*,
              e.employee_id, e.full_name as assigned_worker, e.emp_code,
              p.project_name, p.project_code
       FROM task t
       JOIN employee e ON t.assigned_to = e.employee_id
       LEFT JOIN project p ON t.project_id = p.project_id
       ORDER BY t.task_id DESC`
    );

    for (const task of tasks) {
      const [subtasks] = await db.query(
        `SELECT * FROM task_subtask WHERE task_id = ? ORDER BY subtask_id ASC`,
        [task.task_id]
      );
      task.subtasks = subtasks;
    }

    return res.status(200).json({ success: true, data: tasks });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};


// 2B. EK TASK KI DETAIL DATA (Single Task Details with subtasks, timesheets, assignee, project)
exports.getTaskDetails = async (req, res) => {
  try {
    const { id } = req.params;
    const [tasks] = await db.query(
      `SELECT t.*,
              e.employee_id, e.full_name as assigned_worker, e.emp_code, e.designation as worker_designation,
              p.project_name, p.project_code, p.status as project_status
       FROM task t
       LEFT JOIN employee e ON t.assigned_to = e.employee_id
       LEFT JOIN project p ON t.project_id = p.project_id
       WHERE t.task_id = ?`,
      [id]
    );

    if (tasks.length === 0) {
      return res.status(404).json({ success: false, message: 'Task nahi mila!' });
    }

    const task = tasks[0];

    // Subtasks
    const [subtasks] = await db.query(
      `SELECT * FROM task_subtask WHERE task_id = ? ORDER BY subtask_id ASC`,
      [id]
    );
    task.subtasks = subtasks;

    // Timesheets (hours logged for this specific task)
    let timesheets = [];
    try {
      const [ts] = await db.query(
        `SELECT ts.*, e.full_name as worker_name, e.emp_code
         FROM project_timesheet ts
         LEFT JOIN employee e ON ts.employee_id = e.employee_id
         WHERE ts.task_id = ?
         ORDER BY ts.log_date DESC`,
        [id]
      );
      timesheets = ts;
    } catch (_) {}
    task.timesheets = timesheets;

    return res.status(200).json({ success: true, data: task });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 3. TASK KA STATUS BADALNA (TODO -> IN_PROGRESS -> DONE)
exports.updateTaskStatus = async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body; // 'TODO', 'IN_PROGRESS', 'DONE'

    await db.query('UPDATE task SET status = ? WHERE task_id = ?', [status, id]);

    return res.status(200).json({ success: true, message: `Task status changed to ${status}!` });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};
// 4. TASK UPDATE KARNA (Title, Description, Assignee, Priority, Hours)
exports.updateTask = async (req, res) => {
  try {
    const { id } = req.params;
    const { assigned_to, project_id, title, description, priority, status, due_date, estimated_hours } = req.body;

    if (!title || !assigned_to) {
      return res.status(400).json({ success: false, message: 'Assignee aur Title zaroori hain!' });
    }

    await db.query(
      `UPDATE task SET
        assigned_to = ?,
        project_id = ?,
        title = ?,
        description = ?,
        priority = COALESCE(?, priority),
        status = COALESCE(?, status),
        due_date = ?,
        estimated_hours = COALESCE(?, estimated_hours)
      WHERE task_id = ?`,
      [
        assigned_to,
        project_id !== undefined ? project_id : null,
        title,
        description !== undefined ? description : '',
        priority || null,
        status || null,
        due_date !== undefined ? due_date : null,
        estimated_hours !== undefined ? estimated_hours : 0,
        id
      ]
    );

    return res.status(200).json({ success: true, message: 'Task updated successfully!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 5. TASK DELETE KARNA (Safely remove subtasks & task)
exports.deleteTask = async (req, res) => {
  try {
    const { id } = req.params;

    // 1. Task ke checklist subtasks delete kiye
    await db.query('DELETE FROM task_subtask WHERE task_id = ?', [id]);
    // 2. Task ki timesheets unlink ki
    await db.query('DELETE FROM project_timesheet WHERE task_id = ?', [id]);
    // 3. Main task delete kiya
    const [result] = await db.query('DELETE FROM task WHERE task_id = ?', [id]);

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Task nahi mila!' });
    }

    return res.status(200).json({ success: true, message: 'Task deleted successfully!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};


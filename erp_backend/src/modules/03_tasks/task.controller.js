const db = require('../../config/db');
const jwt = require('jsonwebtoken');
const { resolveCompanyId, resolveRequesterInfo } = require('../../utils/tenant');
const {
  normalizeEmployeeIds,
  normalizeStatus,
  hasReviewers,
  canAssigneeSetStatus,
  canApproveTask,
} = require('../../utils/task_workflow');

async function resolveRequesterEmployee(req) {
  // 1. Direct req.user
  if (req.user && (req.user.employeeId || req.user.employee_id)) {
    return parseInt(req.user.employeeId || req.user.employee_id, 10);
  }

  // 2. Authorization Bearer Token
  if (req.headers && req.headers.authorization && req.headers.authorization.startsWith('Bearer ')) {
    try {
      const token = req.headers.authorization.split(' ')[1];
      const decoded = jwt.verify(token, process.env.JWT_SECRET || 'secret');
      if (decoded && (decoded.employeeId || decoded.employee_id)) {
        return parseInt(decoded.employeeId || decoded.employee_id, 10);
      }
      if (decoded && (decoded.userId || decoded.user_id)) {
        const uId = parseInt(decoded.userId || decoded.user_id, 10);
        const [empRows] = await db.query('SELECT employee_id FROM employee WHERE user_id = ? LIMIT 1', [uId]);
        if (empRows.length > 0) return empRows[0].employee_id;
      }
    } catch (_) {}
  }

  // 3. Headers
  if (req.headers && req.headers['x-employee-id']) {
    const eid = parseInt(req.headers['x-employee-id'], 10);
    if (!isNaN(eid)) return eid;
  }
  if (req.headers && req.headers['x-user-id']) {
    const uid = parseInt(req.headers['x-user-id'], 10);
    if (!isNaN(uid)) {
      const [empRows] = await db.query('SELECT employee_id FROM employee WHERE user_id = ? LIMIT 1', [uid]);
      if (empRows.length > 0) return empRows[0].employee_id;
    }
  }

  // 4. Body / Query
  const rawEmpId = req.body?.employee_id || req.query?.employee_id;
  if (rawEmpId) {
    const eid = parseInt(rawEmpId, 10);
    if (!isNaN(eid)) return eid;
  }
  const rawUserId = req.body?.user_id || req.query?.user_id || req.user?.id || req.user?.userId;
  if (rawUserId) {
    const uid = parseInt(rawUserId, 10);
    if (!isNaN(uid)) {
      const [empRows] = await db.query('SELECT employee_id FROM employee WHERE user_id = ? LIMIT 1', [uid]);
      if (empRows.length > 0) return empRows[0].employee_id;
    }
  }

  return null;
}

const sendNotification = async ({ companyId = 1, title, message, type, referenceId, targetUserId }) => {
  try {
    await db.query(`
      CREATE TABLE IF NOT EXISTS NOTIFICATION (
        notification_id INT AUTO_INCREMENT PRIMARY KEY,
        company_id INT NOT NULL DEFAULT 1,
        title VARCHAR(150) NOT NULL,
        message TEXT NOT NULL,
        type VARCHAR(50) DEFAULT 'GENERAL',
        reference_id INT DEFAULT NULL,
        target_user_id INT DEFAULT NULL,
        target_role VARCHAR(50) DEFAULT NULL,
        sender_user_id INT DEFAULT NULL,
        is_read TINYINT(1) DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await db.query(`
      INSERT INTO NOTIFICATION (company_id, title, message, type, reference_id, target_user_id)
      VALUES (?, ?, ?, ?, ?, ?)
    `, [companyId, title, message, type, referenceId, targetUserId]);
  } catch (err) {
    console.warn('Task notification failed:', err.message);
  }
};

async function fetchTaskReviewers(taskId) {
  try {
    const [rows] = await db.query(
      `SELECT e.employee_id, e.full_name, e.emp_code, e.designation
       FROM task_reviewers tr
       JOIN employee e ON tr.employee_id = e.employee_id
       WHERE tr.task_id = ?`,
      [taskId]
    );
    return rows;
  } catch (_) {
    return [];
  }
}

// 1. NAYA TASK ASSIGN KARNA (General ya Project Task - Supports Single or Multiple Assignees)
exports.createTask = async (req, res) => {
  try {
    const { assigned_to, assignees, reviewers, title, description, priority, status, due_date, project_id, estimated_hours, subtasks, is_private } = req.body;

    // Handle multiple assignees or single assigned_to
    let assigneeList = [];
    if (Array.isArray(assignees) && assignees.length > 0) {
      assigneeList = assignees.map(id => parseInt(id)).filter(id => !isNaN(id));
    } else if (assigned_to) {
      assigneeList = [parseInt(assigned_to)];
    }

    if (assigneeList.length === 0 || !title) {
      return res.status(400).json({ success: false, message: 'At least 1 Assignee and Task Title are required!' });
    }

    const reviewerList = normalizeEmployeeIds(reviewers);
    // With reviewers configured, DONE is only reachable through an approval.
    const requestedStatus = normalizeStatus(status, 'TODO');
    const initialStatus = canAssigneeSetStatus(requestedStatus, reviewerList) ? requestedStatus : 'TODO';

    const requester = await resolveRequesterInfo(req);
    const assignedBy = requester.employeeId || null;

    const primaryAssignee = assigneeList[0];
    let effCompanyId = resolveCompanyId(req) || req.body.company_id;
    if (!effCompanyId && project_id) {
      try {
        const [pRows] = await db.query('SELECT company_id FROM project WHERE project_id = ?', [project_id]);
        if (pRows.length > 0 && pRows[0].company_id) effCompanyId = pRows[0].company_id;
      } catch (_) {}
    }
    effCompanyId = effCompanyId || 1;

    const [result] = await db.query(
      `INSERT INTO task (company_id, assigned_to, assigned_by, project_id, title, description, priority, status, due_date, estimated_hours, is_private)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [effCompanyId, primaryAssignee, assignedBy, project_id || null, title, description || '', priority || 'MEDIUM', initialStatus, due_date || null, estimated_hours || 0, is_private ? 1 : 0]
    );

    const taskId = result.insertId;

        // Notification to assigned employees
        if (assigneeList.length > 0) {
          const [empUsers] = await db.query(
            `SELECT employee_id, user_id FROM EMPLOYEE WHERE employee_id IN (?)`,
            [assigneeList]
          );
          for (const eu of empUsers) {
            if (eu.user_id) {
              await sendNotification({
                companyId: effCompanyId,
                title: 'New Task Assigned 📋',
                message: `You have been assigned a new task "${title}" (Priority: ${priority || 'MEDIUM'}).`,
                type: 'TASK_ASSIGNED',
                referenceId: taskId,
                targetUserId: eu.user_id
              });
            }
          }
        }

    // Insert all assignees into task_assignees table
    for (const empId of assigneeList) {
      await db.query(
        `INSERT IGNORE INTO task_assignees (task_id, employee_id) VALUES (?, ?)`,
        [taskId, empId]
      );
    }

    // Insert chosen reviewers and inform them that approval may be requested.
    if (reviewerList.length > 0) {
      try {
        for (const empId of reviewerList) {
          await db.query(
            `INSERT IGNORE INTO task_reviewers (task_id, employee_id) VALUES (?, ?)`,
            [taskId, empId]
          );
        }
      } catch (err) {
        console.warn('Could not save task reviewers:', err.message);
      }
      try {
        const [reviewerUsers] = await db.query(
          `SELECT employee_id, user_id FROM EMPLOYEE WHERE employee_id IN (?)`,
          [reviewerList]
        );
        for (const ru of reviewerUsers) {
          if (ru.user_id) {
            await sendNotification({
              companyId: effCompanyId,
              title: 'Task Review Assigned 🔎',
              message: `You are a reviewer for task "${title}". You can approve it once it is sent for review.`,
              type: 'TASK_REVIEW_ASSIGNED',
              referenceId: taskId,
              targetUserId: ru.user_id
            });
          }
        }
      } catch (err) {
        console.warn('Reviewer notification failed:', err.message);
      }
    }

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

// 2. SAARE TASKS KI LIST DEKHNA (Get All Tasks with Project name & Multi-Assignees)
exports.getTasks = async (req, res) => {
  try {
    const { employee_id, user_id, role, project_id } = req.query;
    const normalizedRole = String(role || req.user?.role || req.user?.role_name || '')
      .trim()
      .toLowerCase();
    // Accept Admin / ADMIN / Super Admin consistently with permissions.js.
    const isSuperAdmin = normalizedRole.includes('admin');

    // Agar role ya employee_id ya user_id explicitly bheja hai tabhi filtering karenge
    const isFilteringRequested = Boolean(role || employee_id || user_id);

    let empId = employee_id ? parseInt(employee_id, 10) : (req.user?.employeeId || null);

    // Agar employee_id nahi mila par user_id mila hai, toh employee dhundo
    if (isFilteringRequested && !isSuperAdmin && !empId && (user_id || req.user?.id || req.user?.userId)) {
      const uId = user_id || req.user?.id || req.user?.userId;
      try {
        const [empRows] = await db.query(
          'SELECT employee_id FROM employee WHERE user_id = ? LIMIT 1',
          [uId]
        );
        if (empRows.length > 0) {
          empId = empRows[0].employee_id;
        }
      } catch (err) {
        console.warn('Error finding employee by user_id in getTasks:', err.message);
      }
    }

    let query = `
      SELECT t.*,
             e.employee_id, e.full_name as assigned_worker, e.emp_code,
             p.project_name, p.project_code
      FROM task t
      LEFT JOIN employee e ON t.assigned_to = e.employee_id
      LEFT JOIN project p ON t.project_id = p.project_id
    `;

    const companyId = resolveCompanyId(req);
    const whereConditions = [];
    const params = [];

    if (companyId) {
      whereConditions.push('(t.company_id = ? OR p.company_id = ?)');
      params.push(companyId, companyId);
    } else {
      whereConditions.push('1 = 0');
    }

    if (project_id) {
      whereConditions.push('t.project_id = ?');
      params.push(project_id);
    }

    // Strict task privacy rules:
    // 1. If a task belongs to a project (project_id IS NOT NULL), it is visible to all members of that project (including self-assigned tasks).
    // 2. If it is a General Task (project_id IS NULL), private tasks (is_private = 1) remain visible ONLY to the assigned employee!
    whereConditions.push(`(
      t.project_id IS NOT NULL
      OR (t.is_private = 0 OR t.is_private IS NULL)
      OR (
        ? IS NOT NULL AND (
          t.assigned_to = ?
          OR EXISTS (SELECT 1 FROM task_assignees ta WHERE ta.task_id = t.task_id AND ta.employee_id = ?)
        )
      )
    )`);
    params.push(empId, empId, empId);

    // Agar filtering requested hai aur non-super-admin employee hai
    if (isFilteringRequested && !isSuperAdmin) {
      if (empId) {
        whereConditions.push(`(
            t.assigned_to = ?
            OR EXISTS (SELECT 1 FROM task_assignees ta WHERE ta.task_id = t.task_id AND ta.employee_id = ?)
            OR EXISTS (
              SELECT 1 FROM project_member pm
              WHERE pm.project_id = t.project_id AND pm.employee_id = ?
            )
            OR EXISTS (
              SELECT 1 FROM project pr
              WHERE pr.project_id = t.project_id AND (pr.project_leader_id = ? OR pr.head_user_id = ?)
            )
          )`);
        params.push(empId, empId, empId, empId, empId);
      } else {
        // Non-admin employee jiska koi employee record linked nahi hai
        whereConditions.push('1 = 0');
      }
    }

    if (whereConditions.length > 0) {
      query += ` WHERE ${whereConditions.join(' AND ')} `;
    }

    query += ` ORDER BY t.task_id DESC`;

    const [tasks] = await db.query(query, params);

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
      task.reviewers = await fetchTaskReviewers(task.task_id);
    }

    return res.status(200).json({ success: true, data: tasks });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};


// 2B. EK TASK KI DETAIL DATA (Single Task Details with subtasks, timesheets, assignees, project)
exports.getTaskDetails = async (req, res) => {
  try {
    const { id } = req.params;
    const [tasks] = await db.query(
      `SELECT t.*,
              e.employee_id, e.full_name as assigned_worker, e.emp_code, e.designation as worker_designation,
              ab.full_name as assigned_by_name,
              p.project_name, p.project_code, p.status as project_status
       FROM task t
       LEFT JOIN employee e ON t.assigned_to = e.employee_id
       LEFT JOIN employee ab ON t.assigned_by = ab.employee_id
       LEFT JOIN project p ON t.project_id = p.project_id
       WHERE t.task_id = ?`,
      [id]
    );

    if (tasks.length === 0) {
      return res.status(404).json({ success: false, message: 'Task not found!' });
    }

    const task = tasks[0];

    // Subtasks
    const [subtasks] = await db.query(
      `SELECT * FROM task_subtask WHERE task_id = ? ORDER BY subtask_id ASC`,
      [id]
    );
    task.subtasks = subtasks;

    // Multi-Assignees
    const [assignees] = await db.query(
      `SELECT e.employee_id, e.full_name, e.emp_code, e.designation
       FROM task_assignees ta
       JOIN employee e ON ta.employee_id = e.employee_id
       WHERE ta.task_id = ?`,
      [id]
    );
    task.assignees = assignees;
    if (assignees.length > 0) {
      task.assigned_worker = assignees.map(a => a.full_name).join(', ');
    }

    // Multi-Reviewers
    task.reviewers = await fetchTaskReviewers(id);

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

// 3. TASK STATUS: TODO -> IN_PROGRESS -> REVIEW -> DONE
// Assignees can move a task to REVIEW; a chosen reviewer must approve to reach DONE.
exports.updateTaskStatus = async (req, res) => {
  try {
    const { id } = req.params;
    const targetStatus = normalizeStatus(req.body?.status, null);

    if (!targetStatus) {
      return res.status(400).json({
        success: false,
        message: 'Invalid status! Allowed: TODO, IN_PROGRESS, REVIEW, DONE.'
      });
    }

    // A. Fetch task details
    const [tasks] = await db.query(
      'SELECT task_id, assigned_to, company_id, title, status FROM task WHERE task_id = ?',
      [id]
    );
    if (tasks.length === 0) {
      return res.status(404).json({ success: false, message: 'Task not found!' });
    }
    const currentTask = tasks[0];

    // B. Collect all assigned employee IDs
    const [assigneeRows] = await db.query('SELECT employee_id FROM task_assignees WHERE task_id = ?', [id]);
    const assigneeIds = new Set(
      [currentTask.assigned_to, ...assigneeRows.map(r => r.employee_id)]
        .filter(e => e !== null && e !== undefined)
        .map(e => parseInt(e, 10))
    );

    // C. Resolve authenticated requester employee ID & admin status
    const requester = await resolveRequesterInfo(req);

    // D. Enforce permission: ONLY assigned user OR Super Admin can update status
    if (!requester.isSuperAdmin && (!requester.employeeId || !assigneeIds.has(requester.employeeId))) {
      return res.status(403).json({
        success: false,
        message: 'Access Denied: Only the assigned employee or admin can change task status!'
      });
    }

    // E. Reviewers gate completion. Admins must use the approval endpoint too.
    const reviewers = await fetchTaskReviewers(id);
    const reviewerIds = reviewers.map(r => r.employee_id);
    if (!canAssigneeSetStatus(targetStatus, reviewerIds)) {
      return res.status(403).json({
        success: false,
        message: 'Review approval required: this task can only be completed after a chosen reviewer approves it.'
      });
    }

    if (targetStatus === 'DONE') {
      await db.query('UPDATE task SET status = ?, reviewed_at = NULL WHERE task_id = ?', [targetStatus, id]);
    } else {
      await db.query(
        'UPDATE task SET status = ?, reviewed_by = NULL, reviewed_at = NULL WHERE task_id = ?',
        [targetStatus, id]
      );
    }

    // F. Notify reviewers when the task is sent for review.
    if (targetStatus === 'REVIEW' && reviewerIds.length > 0) {
      try {
        const [reviewerUsers] = await db.query(
          `SELECT employee_id, user_id FROM EMPLOYEE WHERE employee_id IN (?)`,
          [reviewerIds]
        );
        for (const ru of reviewerUsers) {
          if (ru.user_id) {
            await sendNotification({
              companyId: currentTask.company_id || 1,
              title: 'Task Sent for Review 🔎',
              message: `Task "${currentTask.title}" is waiting for your approval.`,
              type: 'TASK_REVIEW_REQUEST',
              referenceId: id,
              targetUserId: ru.user_id
            });
          }
        }
      } catch (err) {
        console.warn('Review request notification failed:', err.message);
      }
    }

    return res.status(200).json({ success: true, message: `Task status changed to ${targetStatus}!` });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4. TASK UPDATE KARNA (Title, Description, Multiple Assignees, Priority, Status, Hours)
exports.updateTask = async (req, res) => {
  try {
    const { id } = req.params;
    const { assigned_to, assignees, reviewers, project_id, title, description, priority, status, due_date, estimated_hours } = req.body;

    // Fetch existing task
    const [existingTasks] = await db.query('SELECT task_id, assigned_to, status FROM task WHERE task_id = ?', [id]);
    if (existingTasks.length === 0) {
      return res.status(404).json({ success: false, message: 'Task not found!' });
    }
    const existing = existingTasks[0];

    // Resolve requester once for all checks
    const requester = await resolveRequesterInfo(req);

    // PERMISSION CHECK: Only the assigned employee (self-assigned task owner) OR Admin can edit this task!
    if (!requester.isSuperAdmin) {
      const [assigneeRows] = await db.query('SELECT employee_id FROM task_assignees WHERE task_id = ?', [id]);
      const assigneeIds = new Set(
        [existing.assigned_to, ...assigneeRows.map(r => r.employee_id)]
          .filter(e => e !== null && e !== undefined)
          .map(e => parseInt(e, 10))
      );
      if (!requester.employeeId || !assigneeIds.has(requester.employeeId)) {
        return res.status(403).json({
          success: false,
          message: 'Access Denied: Only the assigned employee or admin can edit this task!'
        });
      }
    }

    // Handle multiple assignees or single assigned_to
    let assigneeList = [];
    if (Array.isArray(assignees) && assignees.length > 0) {
      assigneeList = assignees.map(empId => parseInt(empId)).filter(empId => !isNaN(empId));
    } else if (assigned_to) {
      assigneeList = [parseInt(assigned_to)];
    }

    if (!title || assigneeList.length === 0) {
      return res.status(400).json({ success: false, message: 'At least 1 Assignee and Title are required!' });
    }

    // Effective reviewers (edit form always sends the full list).
    const reviewerList = reviewers === undefined
      ? (await fetchTaskReviewers(id)).map(r => r.employee_id)
      : normalizeEmployeeIds(reviewers);

    // Status change: already verified requester is assigned or admin.
    let targetStatus = existing.status;
    if (status) {
      const requestedStatus = normalizeStatus(status, existing.status);
      if (!canAssigneeSetStatus(requestedStatus, reviewerList)) {
        return res.status(403).json({
          success: false,
          message: 'Review approval required: this task can only be completed after a chosen reviewer approves it.'
        });
      }
      targetStatus = requestedStatus;
    }

    const primaryAssignee = assigneeList[0];

    await db.query(
      `UPDATE task SET
        assigned_to = ?,
        project_id = ?,
        title = ?,
        description = ?,
        priority = COALESCE(?, priority),
        status = ?,
        due_date = ?,
        estimated_hours = COALESCE(?, estimated_hours)
      WHERE task_id = ?`,
      [
        primaryAssignee,
        project_id !== undefined ? project_id : null,
        title,
        description !== undefined ? description : '',
        priority || null,
        targetStatus,
        due_date !== undefined ? due_date : null,
        estimated_hours !== undefined ? estimated_hours : 0,
        id
      ]
    );

    // Sync task_assignees table
    await db.query('DELETE FROM task_assignees WHERE task_id = ?', [id]);
    for (const empId of assigneeList) {
      await db.query('INSERT IGNORE INTO task_assignees (task_id, employee_id) VALUES (?, ?)', [id, empId]);
    }

    // Sync task_reviewers table when the form provides the list
    if (reviewers !== undefined) {
      try {
        await db.query('DELETE FROM task_reviewers WHERE task_id = ?', [id]);
        for (const empId of reviewerList) {
          await db.query('INSERT IGNORE INTO task_reviewers (task_id, employee_id) VALUES (?, ?)', [id, empId]);
        }
      } catch (err) {
        console.warn('Could not sync task reviewers:', err.message);
      }
    }

    return res.status(200).json({ success: true, message: 'Task updated successfully!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4B. REVIEW APPROVAL - only a chosen reviewer (or admin) may complete a REVIEW task.
exports.approveTask = async (req, res) => {
  try {
    const { id } = req.params;
    const [tasks] = await db.query(
      'SELECT task_id, assigned_to, company_id, title, status FROM task WHERE task_id = ?',
      [id]
    );
    if (tasks.length === 0) {
      return res.status(404).json({ success: false, message: 'Task not found!' });
    }
    const task = tasks[0];
    const reviewers = await fetchTaskReviewers(id);
    const requester = await resolveRequesterInfo(req);

    if (!canApproveTask({
      isSuperAdmin: requester.isSuperAdmin,
      employeeId: requester.employeeId,
      reviewerIds: reviewers.map(r => r.employee_id),
      currentStatus: task.status,
    })) {
      const status = normalizeStatus(task.status, '');
      return res.status(403).json({
        success: false,
        message: status === 'REVIEW'
          ? 'Access Denied: Only a chosen reviewer or admin can approve this task!'
          : 'This task is not waiting for review!'
      });
    }

    await db.query(
      `UPDATE task SET status = 'DONE', reviewed_by = ?, reviewed_at = NOW() WHERE task_id = ?`,
      [requester.employeeId || requester.userId || null, id]
    );

    // Inform assignees that their work was approved.
    try {
      const assigneeIds = normalizeEmployeeIds([task.assigned_to]);
      if (assigneeIds.length > 0) {
        const [empUsers] = await db.query(
          `SELECT employee_id, user_id FROM EMPLOYEE WHERE employee_id IN (?)`,
          [assigneeIds]
        );
        for (const eu of empUsers) {
          if (eu.user_id) {
            await sendNotification({
              companyId: task.company_id || 1,
              title: 'Task Approved ✅',
              message: `Task "${task.title}" was approved and marked complete.`,
              type: 'TASK_APPROVED',
              referenceId: task.task_id,
              targetUserId: eu.user_id
            });
          }
        }
      }
    } catch (err) {
      console.warn('Task approval notification failed:', err.message);
    }

    return res.status(200).json({ success: true, message: 'Task approved and marked complete!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// 4C. RETURN A TASK FOR REVISION (reviewer sends it back to the assignee)
exports.rejectTaskReview = async (req, res) => {
  try {
    const { id } = req.params;
    const [tasks] = await db.query(
      'SELECT task_id, assigned_to, company_id, title, status FROM task WHERE task_id = ?',
      [id]
    );
    if (tasks.length === 0) {
      return res.status(404).json({ success: false, message: 'Task not found!' });
    }
    const task = tasks[0];
    const reviewers = await fetchTaskReviewers(id);
    const requester = await resolveRequesterInfo(req);

    if (!canApproveTask({
      isSuperAdmin: requester.isSuperAdmin,
      employeeId: requester.employeeId,
      reviewerIds: reviewers.map(r => r.employee_id),
      currentStatus: task.status,
    })) {
      return res.status(403).json({
        success: false,
        message: 'Only a chosen reviewer or admin can return this task for revision!'
      });
    }

    await db.query(
      `UPDATE task SET status = 'IN_PROGRESS', reviewed_by = NULL, reviewed_at = NULL WHERE task_id = ?`,
      [id]
    );

    return res.status(200).json({ success: true, message: 'Task returned for revision.' });
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
    // Reviewer rows (older tables may not have the FK cascade)
    try {
      await db.query('DELETE FROM task_reviewers WHERE task_id = ?', [id]);
    } catch (_) {}
    // 2. Task ki timesheets unlink ki
    await db.query('DELETE FROM project_timesheet WHERE task_id = ?', [id]);
    // 3. Main task delete kiya
    const [result] = await db.query('DELETE FROM task WHERE task_id = ?', [id]);

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'Task not found!' });
    }

    return res.status(200).json({ success: true, message: 'Task deleted successfully!' });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};


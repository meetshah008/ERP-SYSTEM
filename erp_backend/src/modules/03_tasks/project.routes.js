const express = require('express');
const router = express.Router();
const projectController = require('./project.controller');

// 1. Naya Project create karna & Saare projects fetch karna
router.post('/', projectController.createProject);
router.get('/', projectController.getProjects);

// 2. Ek specific project ka pura data (Tasks, Subtasks, Team, Timesheets, Materials)
router.get('/:id', projectController.getProjectDetails);

// 3. Project ke andar naya Task create karna (with Subtasks)
router.post('/:id/tasks', projectController.createProjectTask);

// 4. Subtask ko tick / untick karna & Naya Subtask jodna
router.put('/subtasks/:subtaskId', projectController.toggleSubtask);
router.post('/tasks/:taskId/subtasks', projectController.addSubtask);

// 5. Timesheet log karna (Worker work hours)
router.post('/:id/timesheets', projectController.logTimesheet);

// 6. Project material add karna
router.post('/:id/materials', projectController.addProjectMaterial);

// 7.Project Edit & Delete routes
router.put('/:id', projectController.updateProject);
router.delete('/:id', projectController.deleteProject);

router.delete('/materials/:materialId', projectController.deleteProjectMaterial);

// Single Subtask Delete route
router.delete('/subtasks/:subtaskId', projectController.deleteSubtask);

// Single Subtask Delete route
router.delete('/subtasks/:subtaskId', projectController.deleteSubtask);
router.delete('/:id', projectController.deleteProject);

// Single Subtask Delete route
router.delete('/subtasks/:subtaskId', projectController.deleteSubtask);

module.exports = router;
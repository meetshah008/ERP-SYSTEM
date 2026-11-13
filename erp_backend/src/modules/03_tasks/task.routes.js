const express = require('express');
const router = express.Router();
const taskController = require('./task.controller');

// 1. Naya task banana (POST)
router.post('/', taskController.createTask);

// 2. Saare tasks mangwana (GET)
router.get('/', taskController.getTasks);
router.get('/:id', taskController.getTaskDetails);

// 3. Task ka status badalna (PUT)
router.put('/:id/status', taskController.updateTaskStatus);

// 4. Task Edit & Delete routes
router.put('/:id', taskController.updateTask);
router.delete('/:id', taskController.deleteTask);


module.exports = router;
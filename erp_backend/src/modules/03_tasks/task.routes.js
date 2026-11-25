const express = require('express');
const router = express.Router();
const taskController = require('./task.controller');
const multer = require('multer');
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB max per file
});


// 1. Naya task banana (POST)
router.post('/', taskController.createTask);

// 2. Saare tasks mangwana (GET)
router.get('/', taskController.getTasks);
router.get('/:id', taskController.getTaskDetails);

// 3. Task ka status badalna (PUT)
router.put('/:id/status', taskController.updateTaskStatus);

// 3B. Review approval flow (POST)
router.post('/:id/approve', taskController.approveTask);
router.post('/:id/reject-review', taskController.rejectTaskReview);

// 4. Task Edit & Delete routes
router.put('/:id', taskController.updateTask);
router.delete('/:id', taskController.deleteTask);

// 5. Task File Sharing / Attachments Routes
router.post('/:id/attachments', upload.single('file'), taskController.uploadTaskAttachment);
router.get('/:id/attachments/:attachmentId/download', taskController.downloadTaskAttachment);
router.delete('/:id/attachments/:attachmentId', taskController.deleteTaskAttachment);


module.exports = router;
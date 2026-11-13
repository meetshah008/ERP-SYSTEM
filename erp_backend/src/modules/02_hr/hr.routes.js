const express = require('express');
const router = express.Router();
const hrController = require('./hr.controller');
const multer = require('multer');
const upload = multer({ storage: multer.memoryStorage() }); // File memory mein rakhega

// Naya employee save karne ka route (POST)
router.post('/employees', hrController.addEmployee);

// Excel upload endpoint
router.get('/attendance-imports', hrController.getAttendanceImports);
router.post('/upload-attendance', upload.single('file'), hrController.uploadBiometricSheet);
router.post('/preview-attendance', upload.single('file'), hrController.previewBiometricSheet);

// Attendance records & manual override routes
router.get('/attendance', hrController.getAttendanceRecords);
router.put('/attendance/:id', hrController.updateAttendanceRecord);

// Saare employees ki list mangwane ka route (GET)
router.get('/employees', hrController.getEmployees);

router.get('/stats', hrController.getEmployeeStats);

// Salary Increment & Appraisal Routes
router.post('/increments', hrController.createIncrement);
router.get('/increments', hrController.getIncrements);

// Leave Management Routes
router.post('/leaves', hrController.applyLeave);
router.get('/leaves', hrController.getLeaves);
router.put('/leaves/:leaveId/status', hrController.updateLeaveStatus);
router.delete('/leaves/:leaveId', hrController.deleteLeave);
// Employee Lifecycle & Termination Routes
router.put('/employees/:id/role', hrController.updateEmployeeRole);   // Promote / Change Role (Admin/Manager/Employee)
router.put('/employees/:id/status', hrController.updateEmployeeStatus); // Terminate / Ban / Activate
router.put('/employees/:id', hrController.updateEmployee);             // Edit Profile
router.delete('/employees/:id', hrController.deleteEmployee);          // Delete

// Employee Live Performance Analysis
router.get('/employees/:id/performance', hrController.getEmployeePerformance);

// Department Management Routes
router.get('/departments', hrController.getDepartments);
router.post('/departments', hrController.addDepartment);
router.put('/departments/:id', hrController.updateDepartment);
router.delete('/departments/:id', hrController.deleteDepartment);

// Employee Full Profile & Permissions Routes
router.get('/employees/:id/full-profile', hrController.getEmployeeFullProfile);
router.put('/employees/:id/permissions', hrController.updateEmployeePermissions);
router.put('/employees/:id/lifecycle', hrController.updateEmployeeLifecycle);
router.post('/employees/:id/create-login', hrController.createEmployeeLoginAccount);

// Notification Routes
router.get('/notifications', hrController.getNotifications);
router.put('/notifications/mark-all-read', hrController.markAllNotificationsAsRead);
router.put('/notifications/:id/read', hrController.markNotificationAsRead);


// Employee Lifecycle & Role Routes
router.put('/employees/:id/role', hrController.updateEmployeeRole);   // Promote / Change Role (Admin/Manager/Employee)
router.put('/employees/:id/status', hrController.updateEmployeeStatus); // Terminate / Ban / Activate
router.put('/employees/:id', hrController.updateEmployee);             // Edit Profile
router.delete('/employees/:id', hrController.deleteEmployee);          // Delete
module.exports = router;

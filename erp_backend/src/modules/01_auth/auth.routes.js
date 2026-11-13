const express = require('express');
const router = express.Router();
const authController = require('./auth.controller');

// Route 1: Register Company (First-time setup)
router.post('/register-company', authController.registerCompany);

// Route 2: Daily Login
router.post('/login', authController.login);

module.exports = router;

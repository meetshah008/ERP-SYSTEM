const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());

// Routes
const authRoutes = require('./modules/01_auth/auth.routes');
app.use('/api/auth', authRoutes);

const hrRoutes = require('./modules/02_hr/hr.routes');
app.use('/api/hr',hrRoutes)

const taskRoutes = require('./modules/03_tasks/task.routes');
app.use('/api/tasks', taskRoutes);

const projectRoutes = require('./modules/03_tasks/project.routes');
app.use('/api/projects', projectRoutes);

// Health Check
app.get('/api/health', (req, res) => {
  res.json({ status: 'UP', message: 'Manufacturing ERP Backend Server is running smoothly!' });
});


// Start Server
app.listen(PORT, () => {
  console.log(`🚀 ERP Backend Server running on http://localhost:${PORT}`);
});

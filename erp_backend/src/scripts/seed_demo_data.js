// erp_backend/src/scripts/seed_demo_data.js
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const db = require('../config/db');

async function seedITCompanyData() {
  console.log('🚀 Seeding High-Tech Software & IT Company Demo Data...\n');

  try {
    // 1. Company Setup (Software Tech Solutions)
    const [companies] = await db.query('SELECT company_id FROM COMPANY LIMIT 1');
    let companyId = 1;
    if (companies.length > 0) {
      companyId = companies[0].company_id;
      await db.query(`UPDATE COMPANY SET name = 'Apex Cloud & Software Technologies Pvt Ltd' WHERE company_id = ?`, [companyId]);
    } else {
      const [compRes] = await db.query(
        `INSERT INTO COMPANY (company_code, name, currency, financial_year_start)
         VALUES ('TECH-01', 'Apex Cloud & Software Technologies Pvt Ltd', 'INR', '2026-04-01')`
      );
      companyId = compRes.insertId;
    }

    const [branches] = await db.query('SELECT branch_id FROM BRANCH WHERE company_id = ? LIMIT 1', [companyId]);
    let branchId = 1;
    if (branches.length > 0) {
      branchId = branches[0].branch_id;
      await db.query(`UPDATE BRANCH SET name = 'Tech Park Headquarters - Silicon Bay' WHERE branch_id = ?`, [branchId]);
    } else {
      const [brRes] = await db.query(
        `INSERT INTO BRANCH (company_id, name, address) VALUES (?, 'Tech Park Headquarters - Silicon Bay', 'Tower B, Tech Park')`,
        [companyId]
      );
      branchId = brRes.insertId;
    }

        // 2. Clean Up Old Factory Demo Records
        console.log('🧹 Cleaning old demo data...');
        await db.query('SET FOREIGN_KEY_CHECKS = 0'); // <-- Yeh line jodi
        await db.query(`DELETE FROM task_subtask WHERE task_id IN (SELECT task_id FROM task WHERE title LIKE '%Weld%' OR title LIKE '%CNC%' OR title LIKE '%Bolt%')`);
        await db.query(`DELETE FROM task WHERE title LIKE '%Weld%' OR title LIKE '%CNC%' OR title LIKE '%Bolt%' OR title LIKE '%ELCB%' OR title LIKE '%Siemens%'`);
        await db.query(`DELETE FROM project WHERE project_code LIKE 'PRJ-2026-%'`);
        await db.query(`DELETE FROM DEPARTMENT WHERE name LIKE '%Fabrication%' OR name LIKE '%CNC%' OR name LIKE '%Welding%'`);
        await db.query('SET FOREIGN_KEY_CHECKS = 1'); // <-- Yeh line jodi

    // 3. Insert IT Departments
    console.log('💻 Seeding IT Departments...');
    const itDepartments = [
      'Frontend & Mobile Engineering',
      'Backend & Cloud Architecture',
      'UI/UX Design & Product Experience',
      'DevOps & Cyber Security',
      'QA & Automation Testing',
      'Human Resources & Talent Acquisition'
    ];

    const deptMap = {};
    for (const d of itDepartments) {
      const [existing] = await db.query('SELECT department_id FROM DEPARTMENT WHERE name = ? AND company_id = ?', [d, companyId]);
      if (existing.length > 0) {
        deptMap[d] = existing[0].department_id;
      } else {
        const [res] = await db.query('INSERT INTO DEPARTMENT (company_id, name) VALUES (?, ?)', [companyId, d]);
        deptMap[d] = res.insertId;
      }
    }

    // 4. Insert 10 Software Engineers & Tech Professionals
    console.log('👨‍💻 Seeding Software Engineers & Staff...');
    const itEmployees = [
      { code: 'EMP101', bio: 'BIO-101', name: 'Aarav Sharma', desig: 'Lead Full-Stack Architect', dept: 'Backend & Cloud Architecture', sal: 95000, type: 'Permanent' },
      { code: 'EMP102', bio: 'BIO-102', name: 'Rohan Mehta', desig: 'Senior Flutter Developer', dept: 'Frontend & Mobile Engineering', sal: 78000, type: 'Permanent' },
      { code: 'EMP103', bio: 'BIO-103', name: 'Priya Nair', desig: 'Lead UI/UX Product Designer', dept: 'UI/UX Design & Product Experience', sal: 72000, type: 'Permanent' },
      { code: 'EMP104', bio: 'BIO-104', name: 'Ananya Joshi', desig: 'Backend Microservices Engineer', dept: 'Backend & Cloud Architecture', sal: 65000, type: 'Permanent' },
      { code: 'EMP105', bio: 'BIO-105', name: 'Vikram Malhotra', desig: 'Cloud DevOps Specialist', dept: 'DevOps & Cyber Security', sal: 82000, type: 'Permanent' },
      { code: 'EMP106', bio: 'BIO-106', name: 'Siddharth Sen', desig: 'QA Automation Lead', dept: 'QA & Automation Testing', sal: 60000, type: 'Permanent' },
      { code: 'EMP107', bio: 'BIO-107', name: 'Tanvi Verma', desig: 'Frontend React/Next.js Dev', dept: 'Frontend & Mobile Engineering', sal: 55000, type: 'Permanent' },
      { code: 'EMP108', bio: 'BIO-108', name: 'Kunal Singhania', desig: 'Android & iOS App Dev', dept: 'Frontend & Mobile Engineering', sal: 58000, type: 'Permanent' },
      { code: 'EMP109', bio: 'BIO-109', name: 'Aditya Rao', desig: 'Systems & InfoSec Admin', dept: 'DevOps & Cyber Security', sal: 68000, type: 'Permanent' },
      { code: 'EMP110', bio: 'BIO-110', name: 'Sneha Kapoor', desig: 'HR & Technical Talent Lead', dept: 'Human Resources & Talent Acquisition', sal: 62000, type: 'Permanent' }
    ];

    const empIdList = [];
    for (const emp of itEmployees) {
      const deptId = deptMap[emp.dept] || Object.values(deptMap)[0];
      const [existing] = await db.query('SELECT employee_id FROM EMPLOYEE WHERE emp_code = ?', [emp.code]);

      let empId;
      if (existing.length > 0) {
        empId = existing[0].employee_id;
        await db.query(
          `UPDATE EMPLOYEE SET full_name = ?, designation = ?, department_id = ?, salary_base = ?, email = ? WHERE employee_id = ?`,
          [emp.name, emp.desig, deptId, emp.sal, `${emp.code.toLowerCase()}@apexsoftware.com`, empId]
        );
      } else {
        const [res] = await db.query(
          `INSERT INTO EMPLOYEE (
            branch_id, department_id, emp_code, biometric_emp_code, full_name,
            designation, join_date, status, employment_type, weekly_off,
            salary_grade, salary_base, phone, email, leave_balance_casual, leave_balance_sick, leave_balance_paid
          ) VALUES (?, ?, ?, ?, ?, ?, '2025-02-01', 'active', ?, 'Sunday', 'Grade A', ?, '9876543210', ?, 12, 8, 15)`,
          [branchId, deptId, emp.code, emp.bio, emp.name, emp.desig, emp.type, emp.sal, `${emp.code.toLowerCase()}@apexsoftware.com`]
        );
        empId = res.insertId;
      }
      empIdList.push(empId);
    }

    // 5. Insert Modern IT Software Projects
    console.log('📱 Seeding IT Software Projects...');
    const itProjects = [
      { code: 'IT-PRJ-01', name: 'NextGen AI Analytics SaaS Platform', client: 'FinTech Global Corp', priority: 'Urgent', start: '2026-09-01', end: '2026-12-31' },
      { code: 'IT-PRJ-02', name: 'Cross-Platform E-Commerce Mobile App', client: 'RetailHub International', priority: 'High', start: '2026-10-01', end: '2027-01-15' },
      { code: 'IT-PRJ-03', name: 'Cloud Infrastructure & Kubernetes Migration', client: 'Nexus Health Systems', priority: 'Medium', start: '2026-10-15', end: '2027-02-28' }
    ];

    const projIdList = [];
    for (const prj of itProjects) {
      const [exist] = await db.query('SELECT project_id FROM project WHERE project_code = ?', [prj.code]);
      let prjId;
      if (exist.length > 0) {
        prjId = exist[0].project_id;
      } else {
        const [res] = await db.query(
          `INSERT INTO project (project_code, project_name, client_name, priority, start_date, target_end_date, status, project_leader_id)
           VALUES (?, ?, ?, ?, ?, ?, 'Active', ?)`,
          [prj.code, prj.name, prj.client, prj.priority, prj.start, prj.end, empIdList[0]]
        );
        prjId = res.insertId;
      }
      projIdList.push(prjId);
    }

    // 6. Insert Software Development Tasks (Kanban Board)
    console.log('⚡ Seeding Software Development Tasks & Subtasks...');
    const itTasks = [
      { title: 'Implement OAuth2.0 & Biometric Fingerprint Auth', desc: 'Secure Flutter client login using JWT tokens and biometric face unlock', prio: 'URGENT', status: 'IN_PROGRESS', prj: projIdList[1], emp: empIdList[1] },
      { title: 'Design Glassmorphic UI Design System in Figma', desc: 'Create dark & light mode token components with Emerald (#059669) accents', prio: 'HIGH', status: 'DONE', prj: projIdList[0], emp: empIdList[2] },
      { title: 'Optimize PostgreSQL & Redis Cache Query Latency', desc: 'Index high-traffic analytical endpoints to reduce p99 response time below 100ms', prio: 'HIGH', status: 'TODO', prj: projIdList[0], emp: empIdList[3] },
      { title: 'Setup GitHub Actions CI/CD with Docker & K8s', desc: 'Automate build, lint check, and rolling deployment to AWS EKS cluster', prio: 'URGENT', status: 'IN_PROGRESS', prj: projIdList[2], emp: empIdList[4] },
      { title: 'Automate End-to-End Test Suite with Cypress', desc: 'Write E2E test specs for user checkout, payment gateway, and invoice generation', prio: 'MEDIUM', status: 'DONE', prj: projIdList[1], emp: empIdList[5] },
      { title: 'Fix Memory Leak in Flutter Infinite Scroll List', desc: 'Profile widget disposal lifecycle and optimize image cache memory limits', prio: 'URGENT', status: 'TODO', prj: projIdList[1], emp: empIdList[1] },
      { title: 'Configure AWS CloudFront CDN & S3 Asset Storage', desc: 'Setup edge caching with SSL certificate for media assets and files', prio: 'MEDIUM', status: 'TODO', prj: projIdList[2], emp: empIdList[4] },
      { title: 'Conduct OWASP Top-10 Security Penetration Test', desc: 'Scan for SQL injections, XSS vulnerabilities, and outdated npm packages', prio: 'LOW', status: 'DONE', prj: null, emp: empIdList[8] }
    ];

    for (const t of itTasks) {
      const [res] = await db.query(
        `INSERT INTO task (assigned_to, project_id, title, description, priority, status, due_date, estimated_hours)
         VALUES (?, ?, ?, ?, ?, ?, '2026-11-30', 16.0)`,
        [t.emp, t.prj, t.title, t.desc, t.prio, t.status]
      );

      const taskId = res.insertId;
      await db.query(`INSERT INTO task_subtask (task_id, title, is_completed) VALUES (?, 'Architecture Design & PR Review', 1)`, [taskId]);
      await db.query(`INSERT INTO task_subtask (task_id, title, is_completed) VALUES (?, 'Code Implementation & Unit Tests', ${t.status === 'DONE' ? 1 : 0})`, [taskId]);
      await db.query(`INSERT INTO task_subtask (task_id, title, is_completed) VALUES (?, 'Staging Deployment & Verification', ${t.status === 'DONE' ? 1 : 0})`, [taskId]);
    }

    console.log('\n🎉 ALL SOFTWARE & IT COMPANY DEMO DATA SEEDED SUCCESSFULLY!');
    console.log('✅ Company: Apex Cloud & Software Technologies Pvt Ltd');
    console.log('✅ 6 IT Departments (Frontend, Backend, UI/UX, DevOps, QA, HR)');
    console.log('✅ 10 Tech Professionals (Flutter Dev, Architects, Cloud Engineers)');
    console.log('✅ 3 Software Projects (AI SaaS, E-Commerce App, K8s Migration)');
    console.log('✅ 8 Kanban Tasks with IT Checklists (TODO, IN PROGRESS, DONE)');
    process.exit(0);

  } catch (err) {
    console.error('❌ Error during seeding:', err.message);
    process.exit(1);
  }
}

seedITCompanyData();
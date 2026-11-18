const fs = require('fs');
const path = require('path');

const targetDir = path.join(__dirname, '../lib/features');

function processFile(filePath) {
  let content = fs.readFileSync(filePath, 'utf8');
  if (!content.includes('http://localhost:5000') && !content.includes('http://127.0.0.1:5000')) {
    return;
  }

  console.log('Processing:', filePath);

  // Check if ApiClient is already imported
  if (!content.includes('api_client.dart')) {
    // calculate relative path to lib/core/network/api_client.dart
    const fileDir = path.dirname(filePath);
    const apiPath = path.join(__dirname, '../lib/core/network/api_client.dart');
    let rel = path.relative(fileDir, apiPath).replace(/\\/g, '/');
    if (!rel.startsWith('.')) rel = './' + rel;

    // Insert import after the last import line
    const importRegex = /import\s+['"][^'"]+['"];/g;
    let match;
    let lastIndex = 0;
    while ((match = importRegex.exec(content)) !== null) {
      lastIndex = match.index + match[0].length;
    }

    if (lastIndex > 0) {
      content = content.slice(0, lastIndex) + `\nimport '${rel}';` + content.slice(lastIndex);
    } else {
      content = `import '${rel}';\n` + content;
    }
  }

  // Replace http://localhost:5000 with ${ApiClient.apiHost}
  content = content.replace(/http:\/\/localhost:5000/g, '${ApiClient.apiHost}');
  content = content.replace(/http:\/\/127\.0\.0\.1:5000/g, '${ApiClient.apiHost}');

  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Updated:', filePath);
}

function traverse(dir) {
  const files = fs.readdirSync(dir);
  for (const f of files) {
    const full = path.join(dir, f);
    if (fs.statSync(full).isDirectory()) {
      traverse(full);
    } else if (full.endsWith('.dart')) {
      processFile(full);
    }
  }
}

traverse(targetDir);
console.log('Done fixing endpoints!');

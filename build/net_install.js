const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const OUTPUT_NAME = 'net_installer.lua';
const OUTPUT_PATH = path.join(PROJECT_ROOT, OUTPUT_NAME);
const LUA_EXTENSION = '.lua';
const REPO_BASE_URL = "https://raw.githubusercontent.com/Arcadesys/computercraft_scripts/main/";

const IGNORE_DIRS = new Set([
    '.git',
    '.vscode',
    'build',
    'docs',
    'factory/dist',
    'node_modules'
]);
const IGNORE_FILES = new Set([
    OUTPUT_NAME,
    'arcadesys_installer.lua', // Don't include the big installer
    'package-lock.json',
    'package.json'
]);

function normalizePath(p) {
    return p.replace(/\\/g, '/');
}

function shouldSkip(relativePath, stat) {
    const segments = normalizePath(relativePath).split('/');
    if (segments.some((segment, idx) => {
        const needle = segments.slice(0, idx + 1).join('/');
        return IGNORE_DIRS.has(segment) || IGNORE_DIRS.has(needle);
    })) {
        return true;
    }
    if (stat.isFile() && IGNORE_FILES.has(path.basename(relativePath))) {
        return true;
    }
    return false;
}

function collectLuaFiles(dir, base = '') {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const files = [];

    entries.forEach(entry => {
        const absPath = path.join(dir, entry.name);
        const relPath = normalizePath(path.join(base, entry.name));

        if (shouldSkip(relPath, entry)) {
            return;
        }

        if (entry.isDirectory()) {
            files.push(...collectLuaFiles(absPath, relPath));
        } else if (entry.isFile() && path.extname(entry.name) === LUA_EXTENSION) {
            files.push(relPath);
        }
    });

    return files;
}

function buildNetInstaller() {
    console.log('🌐 Building Network Installer...');
    const files = collectLuaFiles(PROJECT_ROOT)
        .sort((a, b) => a.localeCompare(b));

    if (files.length === 0) {
        console.error('❌ No Lua files found.');
        process.exitCode = 1;
        return;
    }

    let lua = `-- Arcadesys Network Installer\n` +
        `-- Auto-generated at ${new Date().toISOString()}\n` +
        `-- Downloads files from GitHub to bypass file size limits\n\n` +
        `local BASE_URL = "${REPO_BASE_URL}"\n` +
        `local files = {\n`;

    files.forEach(file => {
        console.log(`   • ${file}`);
        lua += `    "${file}",\n`;
    });

    lua += `}\n\n` +
        `print("Starting Network Install...")\n` +
        `print("Source: " .. BASE_URL)\n\n` +
        `local function download(path)\n` +
        `    local url = BASE_URL .. path\n` +
        `    print("Downloading " .. path .. "...")\n` +
        `    local response = http.get(url)\n` +
        `    if not response then\n` +
        `        printError("Failed to download " .. path)\n` +
        `        return false\n` +
        `    end\n` +
        `    \n` +
        `    local content = response.readAll()\n` +
        `    response.close()\n` +
        `    \n` +
        `    local dir = fs.getDir(path)\n` +
        `    if dir ~= "" and not fs.exists(dir) then\n` +
        `        fs.makeDir(dir)\n` +
        `    end\n` +
        `    \n` +
        `    local file = fs.open(path, "w")\n` +
        `    if not file then\n` +
        `        printError("Failed to write " .. path)\n` +
        `        return false\n` +
        `    end\n` +
        `    \n` +
        `    file.write(content)\n` +
        `    file.close()\n` +
        `    return true\n` +
        `end\n\n` +
        `local successCount = 0\n` +
        `local failCount = 0\n\n` +
        `for _, file in ipairs(files) do\n` +
        `    if download(file) then\n` +
        `        successCount = successCount + 1\n` +
        `    else\n` +
        `        failCount = failCount + 1\n` +
        `    end\n` +
        `    sleep(0.1)\n` +
        `end\n\n` +
        `print("")\n` +
        `print("Install Complete!")\n` +
        `print("Downloaded: " .. successCount)\n` +
        `print("Failed: " .. failCount)\n` +
        `\nprint("Verifying installation...")\n` +
        `local errors = 0\n` +
        `for _, file in ipairs(files) do\n` +
        `    if not fs.exists(file) then\n` +
        `        printError("Missing: " .. file)\n` +
        `        errors = errors + 1\n` +
        `    end\n` +
        `end\n` +
        `if failCount == 0 and errors == 0 then\n` +
        `    print("Verification successful.")\n` +
        `    print("Reboot or run startup to launch.")\n` +
        `else\n` +
        `    print("Installation issues detected.")\n` +
        `    if failCount > 0 then print("Failed downloads: " .. failCount) end\n` +
        `    if errors > 0 then print("Missing files: " .. errors) end\n` +
        `end\n`;

    fs.writeFileSync(OUTPUT_PATH, lua, 'utf8');
    console.log(`✅ Wrote network installer to ${OUTPUT_PATH}`);
}

buildNetInstaller();

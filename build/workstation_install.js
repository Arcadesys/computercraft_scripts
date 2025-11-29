const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const OUTPUT_NAME = 'workstation_install.lua';
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
    'net_installer.lua',
    'package-lock.json',
    'package.json'
]);

const ALLOWED_PREFIXES = [
    'arcade/',
    'factory/',
    'lib/',
    'tools/',
    'ui/',
];
const ALLOWED_FILES = new Set([
    'startup.lua',
    'factory_planner.lua',
    'printer.lua',
    'ae2_drive_monitor.lua',
    'games/arcade.lua',
    'kiosk.lua',
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

function filterFiles(allFiles) {
    return allFiles.filter(rel => {
        if (ALLOWED_FILES.has(rel)) return true;
        return ALLOWED_PREFIXES.some(prefix => rel.startsWith(prefix));
    });
}

function buildInstaller() {
    console.log('🖥️ Building Workstation installer...');
    const files = filterFiles(collectLuaFiles(PROJECT_ROOT))
        .sort((a, b) => a.localeCompare(b));

    if (files.length === 0) {
        console.error('No Lua files found to bundle.');
        process.exitCode = 1;
        return;
    }

    let lua = `-- Arcadesys Workstation Installer\n` +
        `-- Auto-generated at ${new Date().toISOString()}\n` +
        `-- Refreshes or installs the workstation experience (computer)\n\n` +
        `local VARIANT = "workstation"\n` +
        `local BASE_URL = "${REPO_BASE_URL}"\n` +
        `local ROOTS = { "arcade", "factory", "lib", "tools", "ui", "kiosk.lua", "games" }\n` +
        `local files = {\n`;

    files.forEach(file => {
        console.log(`   • ${file}`);
        lua += `    "${file}",\n`;
    });

    lua += `}\n\n` +
        `local function persistExperience()\n` +
        `    local h = fs.open("experience.settings", "w")\n` +
        `    if h then\n` +
        `        h.write(textutils.serialize({ experience = VARIANT }))\n` +
        `        h.close()\n` +
        `    end\n` +
        `end\n\n` +
        `local function cleanup()\n` +
        `    for _, root in ipairs(ROOTS) do\n` +
        `        if fs.exists("/" .. root) then\n` +
        `            fs.delete("/" .. root)\n` +
        `        end\n` +
        `    end\n` +
        `end\n\n` +
        `local function download(path)\n` +
        `    local url = BASE_URL .. path\n` +
        `    local response = http.get(url)\n` +
        `    if not response then\n` +
        `        printError("Failed to download " .. path)\n` +
        `        return false\n` +
        `    end\n` +
        `    local content = response.readAll()\n` +
        `    response.close()\n` +
        `    local installPath = "/" .. path\n` +
        `    local dir = fs.getDir(installPath)\n` +
        `    if dir ~= "" and not fs.exists(dir) then\n` +
        `        fs.makeDir(dir)\n` +
        `    end\n` +
        `    local file = fs.open(installPath, "w")\n` +
        `    if not file then\n` +
        `        printError("Cannot write " .. installPath)\n` +
        `        return false\n` +
        `    end\n` +
        `    file.write(content)\n` +
        `    file.close()\n` +
        `    return true\n` +
        `end\n\n` +
        `print("Arcadesys Workstation installer")\n` +
        `persistExperience()\n` +
        `local existing = fs.exists("/arcade") or fs.exists("/factory")\n` +
        `if existing then\n` +
        `    print("Existing install detected. Refreshing...")\n` +
        `else\n` +
        `    print("Fresh install.")\n` +
        `end\n` +
        `cleanup()\n` +
        `local success, fail = 0, 0\n` +
        `for _, file in ipairs(files) do\n` +
        `    if download(file) then\n` +
        `        success = success + 1\n` +
        `    else\n` +
        `        fail = fail + 1\n` +
        `    end\n` +
        `    sleep(0.05)\n` +
        `end\n` +
        `print(string.format("Done. Success: %d, Failed: %d", success, fail))\n` +
        `print("Rebooting in 2 seconds...")\n` +
        `sleep(2)\n` +
        `os.reboot()\n`;

    fs.writeFileSync(OUTPUT_PATH, lua, 'utf8');
    console.log(`✅ Wrote ${OUTPUT_PATH}`);
}

buildInstaller();

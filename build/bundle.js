const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..');
const OUTPUT_NAME = 'arcadesys_installer.lua';
const OUTPUT_PATH = path.join(PROJECT_ROOT, OUTPUT_NAME);
const LUA_EXTENSION = '.lua';
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
    'package-lock.json',
    'package.json'
]);

function normalizePath(p) {
    return p.replace(/\\/g, '/');
}

function toLuaString(str) {
    let equals = '';
    while (str.includes(`[${equals}[`) || str.includes(`]${equals}]`)) {
        equals += '=';
    }
    return `[${equals}[${str}]${equals}]`;
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
            files.push({ absPath, relPath });
        }
    });

    return files;
}

function buildInstaller() {
    console.log('📦 Building Arcadesys installer...');
    const files = collectLuaFiles(PROJECT_ROOT)
        .sort((a, b) => a.relPath.localeCompare(b.relPath));

    if (files.length === 0) {
        console.error('❌ No Lua files found to bundle.');
        process.exitCode = 1;
        return;
    }

    let lua = `-- Arcadesys Unified Installer\n` +
        `-- Auto-generated at ${new Date().toISOString()}\n` +
        `print("Starting Arcadesys install...")\n` +
        `local files = {}\n\n`;

    files.forEach(file => {
        const content = fs.readFileSync(file.absPath, 'utf8');
        console.log(`   • ${file.relPath}`);
        lua += `files["${file.relPath}"] = ${toLuaString(content)}\n`;
    });

    lua += `\nprint("Unpacking ${files.length} files...")\n` +
        `for path, content in pairs(files) do\n` +
        `    local dir = fs.getDir(path)\n` +
        `    if dir ~= "" and not fs.exists(dir) then\n` +
        `        fs.makeDir(dir)\n` +
        `    end\n` +
        `    local handle = fs.open(path, "w")\n` +
        `    if not handle then\n` +
        `        printError("Failed to write " .. path)\n` +
        `    else\n` +
        `        handle.write(content)\n` +
        `        handle.close()\n` +
        `    end\n` +
        `end\n` +
        `print("Arcadesys install complete. Reboot or run startup to launch.")\n`;

    fs.writeFileSync(OUTPUT_PATH, lua, 'utf8');
    console.log(`✅ Wrote installer to ${OUTPUT_PATH}`);
}

buildInstaller();
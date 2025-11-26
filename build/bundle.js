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
    'package.json',
    'README_ARTILLERY.md',
    'projectile.lua',
    'tank.lua',
    'arcadeos.lua' // Exclude old installer/OS file
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
    if (stat.isFile()) {
        const filename = path.basename(relativePath);
        if (IGNORE_FILES.has(filename)) {
            return true;
        }
        // Exclude harness/test files
        if (filename.startsWith('harness_') || filename.startsWith('test_') || filename.startsWith('spec_')) {
            return true;
        }
        // Exclude games from bundle (download separately), but keep system apps
        if (relativePath.startsWith('arcade/games/')) {
            const filename = path.basename(relativePath);
            if (filename !== 'store.lua'
                && filename !== 'themes.lua'
                && filename !== 'slots.lua'
                && filename !== 'idlecraft.lua'
                && filename !== 'cantstop.lua'
                && filename !== 'videopoker.lua'
                && filename !== 'warlords.lua'
                && filename !== 'blackjack.lua'
                && filename !== 'artillery.lua') {
                return true;
            }
        }
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

function minifyLua(content) {
    // Remove block comments --[[ ... ]]
    content = content.replace(/--\[\[[\s\S]*?\]\]/g, '');
    
    return content.split('\n')
        .map(line => line.trim()) // Remove indentation/whitespace
        .filter(line => {
            // Remove empty lines
            if (line.length === 0) return false;
            // Remove single-line comments
            if (line.startsWith('--')) return false;
            return true;
        })
        .join('\n');
}

function incrementBuildCounter() {
    const versionPath = path.join(PROJECT_ROOT, 'lib', 'version.lua');
    let content = fs.readFileSync(versionPath, 'utf8');
    const buildMatch = content.match(/version\.BUILD\s*=\s*(\d+)/);
    if (buildMatch) {
        const oldBuild = parseInt(buildMatch[1], 10);
        const newBuild = oldBuild + 1;
        content = content.replace(/version\.BUILD\s*=\s*\d+/, `version.BUILD = ${newBuild}`);
        fs.writeFileSync(versionPath, content, 'utf8');
        console.log(`🔢 Build counter: ${oldBuild} → ${newBuild}`);

        const major = content.match(/version\.MAJOR\s*=\s*(\d+)/)?.[1] || 0;
        const minor = content.match(/version\.MINOR\s*=\s*(\d+)/)?.[1] || 0;
        const patch = content.match(/version\.PATCH\s*=\s*(\d+)/)?.[1] || 0;
        return `v${major}.${minor}.${patch} (build ${newBuild})`;
    }
    return "v0.0.0 (build 0)";
}

function buildInstaller() {
    const versionString = incrementBuildCounter();
    console.log('📦 Building Arcadesys installer...');
    const files = collectLuaFiles(PROJECT_ROOT)
        .sort((a, b) => a.relPath.localeCompare(b.relPath));

    if (files.length === 0) {
        console.error('❌ No Lua files found to bundle.');
        process.exitCode = 1;
        return;
    }

    const generatedAt = new Date().toISOString();
    let lua = `-- Arcadesys Unified Installer\n` +
        `-- Auto-generated at ${generatedAt}\n` +
        `print("Starting Arcadesys install ${versionString}...")\n` +
        `local EXPERIENCE_FILE = "experience.settings"\n\n` +
        `local function promptChoice(prompt, choices)\n` +
        `    term.setBackgroundColor(colors.black)\n` +
        `    term.setTextColor(colors.white)\n` +
        `    term.clear()\n` +
        `    term.setCursorPos(1, 1)\n` +
        `    print(prompt)\n` +
        `    for i, option in ipairs(choices) do\n` +
        `        print(string.format("  [%d] %s", i, option.label))\n` +
        `    end\n` +
        `    while true do\n` +
        `        term.setCursorPos(1, #choices + 3)\n` +
        `        term.clearLine()\n` +
        `        write("Select option: ")\n` +
        `        local reply = read()\n` +
        `        local idx = tonumber(reply)\n` +
        `        if idx and choices[idx] then\n` +
        `            return choices[idx].id\n` +
        `        end\n` +
        `        print("Invalid selection. Try again.")\n` +
        `    end\n` +
        `end\n\n` +
        `local function detectPlatform()\n` +
        `    if turtle then return "turtle" end\n` +
        `    return "computer"\n` +
        `end\n\n` +
        `local function persistExperience(mode)\n` +
        `    local handle = fs.open(EXPERIENCE_FILE, "w")\n` +
        `    if handle then\n` +
        `        handle.write(textutils.serialize({ experience = mode }))\n` +
        `        handle.close()\n` +
        `    else\n` +
        `        printError("Failed to save experience settings")\n` +
        `    end\n` +
        `end\n\n` +
        `local platform = detectPlatform()\n` +
        `local INSTALL_VARIANT = "workstation"\n` +
        `if platform == "turtle" then\n` +
        `    INSTALL_VARIANT = "turtle"\n` +
        `    print("Detected turtle: installing TurtleOS experience.")\n` +
        `else\n` +
        `    local choice = promptChoice("Choose installation profile:", {\n` +
        `        { id = "workstation", label = "Workstation (factory tools)" },\n` +
        `        { id = "arcade", label = "Arcade (ArcadeOS + games)" },\n` +
        `    })\n` +
        `    INSTALL_VARIANT = choice or "workstation"\n` +
        `    print("Selected profile: " .. INSTALL_VARIANT)\n` +
        `end\n` +
        `persistExperience(INSTALL_VARIANT)\n\n` +
        `local files = {}\n\n`;

    files.forEach(file => {
        let content = fs.readFileSync(file.absPath, 'utf8');
        content = minifyLua(content);
        console.log(`   • ${file.relPath} (${content.length} bytes)`);
        lua += `files["${file.relPath}"] = ${toLuaString(content)}\n`;
    });

    lua += `\nprint("Cleaning old installation...")\n` +
        `if fs.exists("arcade") then fs.delete("arcade") end\n` +
        `if fs.exists("lib") then fs.delete("lib") end\n` +
        `if fs.exists("factory") then fs.delete("factory") end\n` +
        `\nprint("Unpacking ${files.length} files...")\n` +
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
        `\nprint("Verifying installation...")\n` +
        `local errors = 0\n` +
        `for path, _ in pairs(files) do\n` +
        `    if not fs.exists(path) then\n` +
        `        printError("Missing: " .. path)\n` +
        `        errors = errors + 1\n` +
        `    end\n` +
        `end\n` +
        `if errors == 0 then\n` +
        `    print("Verification successful.")\n` +
        `    print("Arcadesys install complete. Reboot or run startup to launch.")\n` +
        `else\n` +
        `    printError("Verification failed with " .. errors .. " missing files.")\n` +
        `end\n`;

    fs.writeFileSync(OUTPUT_PATH, lua, 'utf8');
    console.log(`✅ Wrote installer to ${OUTPUT_PATH}`);
}

buildInstaller();
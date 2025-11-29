const path = require('path');
const { spawnSync } = require('child_process');

const BUILDERS = [
    'turtle_os_install.js',
    'arcade_os_install.js',
    'workstation_install.js',
];

function runBuilder(builder) {
    const scriptPath = path.join(__dirname, builder);
    console.log(`▶️  Running ${builder}...`);
    const result = spawnSync('node', [scriptPath], { stdio: 'inherit' });
    if (result.error) {
        console.error(`Failed to run ${builder}:`, result.error);
        process.exit(1);
    }
    if (result.status !== 0) {
        console.error(`${builder} exited with code ${result.status}`);
        process.exit(result.status || 1);
    }
}

function main() {
    console.log('Bundling all installers...');
    BUILDERS.forEach(runBuilder);
    console.log('✅ All installers built.');
}

main();

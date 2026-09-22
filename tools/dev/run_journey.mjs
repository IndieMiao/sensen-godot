import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const godot = process.env.GODOT_BIN || 'godot';
const mining = process.argv.includes('--journey-mining');
const inventory = process.argv.includes('--journey-inventory');
const character = process.argv.includes('--journey-character');
const requests = process.argv.includes('--journey-requests');
const combat = process.argv.includes('--journey-combat');
const output = path.join(root, combat ? 'output/combat-playtest' : requests ? 'output/requests-playtest' : character ? 'output/character-playtest' : inventory ? 'output/inventory-playtest' : mining ? 'output/mining-playtest' : 'output/journey-playtest');
const project = path.join(output, 'project');
const run = (command, args, options = {}) => new Promise((resolve, reject) => {
  const child = spawn(command, args, { cwd: root, stdio: 'inherit', ...options });
  child.on('error', reject);
  child.on('exit', code => code === 0 ? resolve() : reject(new Error(`${command} exited ${code}`)));
});
await run(godot, ['--headless', '--path', root, '--editor', '--import', '--quit']);
await run(godot, ['--headless', '--path', root, '--script', 'res://tools/dev/prepare_journey_playtest.gd', '--', ...process.argv.slice(2)]);
const server = spawn(process.execPath, ['--import', 'tsx', 'tools/journey_playtest_server.ts'],
  { cwd: path.join(root, 'server'), stdio: ['ignore', 'pipe', 'inherit'],
    env: { ...process.env, JOURNEY_DATABASE: process.env.JOURNEY_DATABASE ?? (combat
      ? 'sensen_farm_journey_combat_playtest_20260915' : requests
      ? 'sensen_farm_journey_requests_playtest_20260914' : character
      ? 'sensen_farm_journey_character_playtest_20260914' : inventory
      ? 'sensen_farm_journey_inventory_playtest_20260914' : mining
      ? 'sensen_farm_journey_mining_playtest_20260914' : 'sensen_farm_journey_playtest_v7') } });
let game;
const stop = () => { game?.kill('SIGTERM'); server.kill('SIGTERM'); };
process.once('SIGINT', stop);
process.once('SIGTERM', stop);
try {
  const base = await new Promise((resolve, reject) => {
    let buffer = '';
    server.once('error', reject);
    server.once('exit', code => reject(new Error(`Playtest server exited ${code}`)));
    server.stdout.on('data', data => {
      process.stdout.write(data);
      buffer += data;
      for (const line of buffer.split('\n')) {
        try { const value = JSON.parse(line); if (value.listening) resolve(value.listening + '/v1'); } catch {}
      }
    });
  });
  game = spawn(godot, ['--path', project, ...process.argv.slice(2).filter(arg => !['--journey-mining', '--journey-inventory', '--journey-character', '--journey-requests', '--journey-combat'].includes(arg))],
    { cwd: root, stdio: 'inherit', env: { ...process.env, SENSEN_JOURNEY_BASE: base,
      SENSEN_JOURNEY_OUTPUT: output } });
  await new Promise((resolve, reject) => {
    game.once('error', reject);
    game.once('exit', code => code === 0 ? resolve() : reject(new Error(`Godot exited ${code}`)));
  });
} finally { stop(); }

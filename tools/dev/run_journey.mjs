import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const godot = process.env.GODOT_BIN || 'godot';
const project = path.join(root, 'output/journey-playtest/project');
const run = (command, args, options = {}) => new Promise((resolve, reject) => {
  const child = spawn(command, args, { cwd: root, stdio: 'inherit', ...options });
  child.on('error', reject);
  child.on('exit', code => code === 0 ? resolve() : reject(new Error(`${command} exited ${code}`)));
});
await run(godot, ['--headless', '--path', root, '--editor', '--import', '--quit']);
await run(godot, ['--headless', '--path', root, '--script', 'res://tools/dev/prepare_journey_playtest.gd', '--', ...process.argv.slice(2)]);
const server = spawn(process.execPath, ['--import', 'tsx', 'tools/journey_playtest_server.ts'],
  { cwd: path.join(root, 'server'), stdio: ['ignore', 'pipe', 'inherit'],
    env: { ...process.env, JOURNEY_DATABASE: process.env.JOURNEY_DATABASE ?? 'sensen_farm_journey_playtest_v7' } });
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
  game = spawn(godot, ['--path', project, ...process.argv.slice(2)],
    { cwd: root, stdio: 'inherit', env: { ...process.env, SENSEN_JOURNEY_BASE: base,
      SENSEN_JOURNEY_OUTPUT: path.join(root, 'output/journey-playtest') } });
  await new Promise((resolve, reject) => {
    game.once('error', reject);
    game.once('exit', code => code === 0 ? resolve() : reject(new Error(`Godot exited ${code}`)));
  });
} finally { stop(); }

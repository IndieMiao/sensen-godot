import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import { runSerial } from './run_serial.mjs';
const exec = promisify(execFile);
// Same order as tools/android/run_test.sh (C-212, C-216).
const serial = runSerial(['JOURNEY_SERIAL']) || 'emulator-5560';
const directory = 'output/online-2026-09-16/android';
const adb = args => exec('adb', ['-s', serial, ...args], { encoding: 'buffer', maxBuffer: 16 * 1024 * 1024 });
await mkdir(directory, { recursive: true });
await adb(['logcat', '-c']);
await adb(['shell', 'uiautomator', 'dump', '/sdcard/online-qa-ui.xml']);
const ui = (await adb(['exec-out', 'cat', '/sdcard/online-qa-ui.xml'])).stdout.toString();
await writeFile(directory + '/initial-ui.xml', ui);
for (const node of ui.match(/<node\b[^>]+>/g) ?? []) {
  if (!/text="(?:OK|确定|Continue|继续)"/.test(node) || !/clickable="true"/.test(node)) continue;
  const bounds = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.exec(node);
  if (bounds) await adb(['shell', 'input', 'tap', String(Math.round((+bounds[1] + +bounds[3]) / 2)), String(Math.round((+bounds[2] + +bounds[4]) / 2))]);
}
const started = Date.now();
let captured = false;
while (Date.now() - started < 35000) {
  await new Promise(resolve => setTimeout(resolve, 1000));
  if (!captured && Date.now() - started > 9000) {
    await writeFile(directory + '/mine-300.png', (await adb(['exec-out', 'screencap', '-p'])).stdout);
    captured = true;
  }
  const logs = (await adb(['logcat', '-d', '-s', 'godot'])).stdout.toString();
  const match = /ONLINE_PROBE_RESULT (\{[^\n]+\})/.exec(logs);
  if (!match) continue;
  await writeFile(directory + '/godot.log', logs);
  const report = JSON.parse(match[1]);
  await writeFile(directory + '/report.json', JSON.stringify(report, null, 2));
  if (/SCRIPT ERROR|Parse Error|Compile Error/.test(logs)) throw new Error('Android Godot script error');
  if (report.maximum_remote_players !== 299 || report.connected_seconds < 5 || report.maximum_motion_m <= .25 || report.crowd_rigs !== 8 || !report.reconnect_restored_instance)
    throw new Error('Android 300-player scenario did not pass: ' + JSON.stringify(report));
  console.log(JSON.stringify(report));
  process.exit(0);
}
throw new Error('Android probe did not finish');

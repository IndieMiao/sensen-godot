import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const execute = promisify(execFile);
const serial = process.env.JOURNEY_SERIAL;
if (!serial) throw new Error('Set JOURNEY_SERIAL to the authorized test device serial');
const packageId = process.env.JOURNEY_PACKAGE ?? 'com.sensen.journeyqa';
if (!/^com\.sensen\.journey[a-z0-9_]*qa$/.test(packageId)) throw new Error('Use a journey QA package');
const [action = 'status', selector, destination, factor = '1.5'] = process.argv.slice(2);
const directory = path.resolve(process.env.JOURNEY_EVIDENCE_DIR ?? 'output/journey-device/evidence');
await mkdir(directory, { recursive: true });
const adb = args => execute('adb', ['-s', serial, ...args], { timeout: 20000, maxBuffer: 16 * 1024 * 1024, encoding: 'buffer' });
const snapshot = async () => {
  const value = await (await fetch(process.env.JOURNEY_SCENE_URL ?? 'http://127.0.0.1:3117/v1/qa/journey/scene')).json();
  if (!value.controls) throw new Error('Device scene has not been published');
  return value;
};
let before = await snapshot();
if (action !== 'status') {
  const foreground = (await adb(['shell', 'dumpsys', 'window'])).stdout.toString();
  const packagePattern = packageId.replaceAll('.', '\\.');
  if (!new RegExp('mCurrentFocus=Window\\{[^\\n]*' + packagePattern + '/').test(foreground))
    throw new Error('Journey QA is not the focused app; no input sent');
  const initial = before;
  const deadline = Date.now() + 5000;
  while (before.launch_id === initial.launch_id && before.ticks_ms <= initial.ticks_ms && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 40));
    before = await snapshot();
  }
  if (before.launch_id === initial.launch_id && before.ticks_ms <= initial.ticks_ms)
    throw new Error('Device scene is stale; restore the connection before sending input');
}
if (action === 'status') {
  console.log(JSON.stringify({ scene: before.scene, launch: before.launch_id, ticks: before.ticks_ms,
    version: before.version, fps: before.fps, native_map: before.native_map_plugin, fallback: before.map_fallback,
    world: before.world && { ...before.world, controls: before.world.controls.map(c => c.path) },
    state: { journey: before.state.journey, inventory: before.state.inventory, wallet: before.state.wallet,
      cells: before.state.cells },
    controls: before.controls.map(c => ({ text: c.text, tooltip: c.tooltip, disabled: c.disabled,
      path: c.button && !c.text && !c.tooltip ? c.path : undefined })).filter(c => c.text || c.tooltip || c.path) }, null, 2));
} else {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const prefix = path.join(directory, `${stamp}-${action}`);
  await writeFile(prefix + '-before.json', JSON.stringify(before, null, 2));
  let args;
  let target;
  let touchPoints;
  const controls = [...before.controls, ...(before.world?.controls ?? [])];
  if (action === 'tap') {
    const candidates = controls.filter(c => c.button && !c.disabled && [c.text, c.tooltip, c.path, c.path.split('/').at(-1)].includes(selector));
    if (candidates.length !== 1) throw new Error(`Expected one enabled target for ${selector}, found ${candidates.length}`);
    target = candidates[0];
    const [x, y, width, height] = target.rect;
    const point = [Math.round(x + width / 2), Math.round(y + height / 2)].map(String);
    const holdMs = Number(destination ?? 80);
    if (!Number.isInteger(holdMs) || holdMs < 40 || holdMs > 800) throw new Error('Tap duration must be 40..800 ms');
    args = ['shell', 'input', 'swipe', ...point, ...point, String(holdMs)];
  } else if (action === 'swipe' || action === 'pinch') {
    const points = [selector, destination].flatMap(value => {
      const matches = controls.filter(c => [c.text, c.tooltip, c.path].includes(value));
      if (matches.length !== 1) throw new Error(`Expected one visible swipe anchor for ${value}`);
      const [x, y, width, height] = matches[0].rect;
      return [Math.round(x + width / 2), Math.round(y + height / 2)].map(String);
    });
    if (action === 'pinch') {
      const scale = Number(factor);
      if (!Number.isFinite(scale) || scale < 0.3 || scale > 2.5) throw new Error('Pinch factor must be 0.3..2.5');
      const start = points.map(Number);
      const center = [(start[0] + start[2]) / 2, (start[1] + start[3]) / 2];
      const end = start.map((v, i) => Math.round(center[i % 2] + (v - center[i % 2]) * scale));
      const display = (await adb(['shell', 'wm', 'size'])).stdout.toString();
      const [, width, height] = display.match(/(?:Override|Physical) size: (\d+)x(\d+)/) ?? [];
      if (!width || end.some((v, i) => v < 48 || v > Number(i % 2 ? height : width) - 48))
        throw new Error('Pinch endpoints leave the safe display area');
      args = ['shell', 'env', 'CLASSPATH=/data/local/tmp/journey-touch.dex', 'app_process', '/data/local/tmp', 'JourneyTouch', ...points, ...end.map(String), '500'];
      touchPoints = [[start[0], start[1]], [start[2], start[3]]];
    } else args = ['shell', 'input', 'swipe', ...points, '500'];
  } else if (action === 'back') args = ['shell', 'input', 'keyevent', '4'];
  else if (action !== 'capture') throw new Error(`Unsupported action ${action}`);
  const inputStarted = Date.now();
  if (args) await adb(args);
  const inputFinished = Date.now();
  await new Promise(resolve => setTimeout(resolve, 2000));
  let after = await snapshot();
  const deadline = Date.now() + 10000;
  while (after.launch_id === before.launch_id && after.ticks_ms <= before.ticks_ms && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 250));
    after = await snapshot();
  }
  if (after.launch_id === before.launch_id && after.ticks_ms <= before.ticks_ms)
    throw new Error('Device scene did not advance; no screenshot recorded against stale geometry');
  const motionDeadline = Date.now() + 15000;
  while (args && (after.world?.moving || after.world?.busy || after.world?.pending) && Date.now() < motionDeadline) {
    await new Promise(resolve => setTimeout(resolve, 300));
    after = await snapshot();
  }
  const screenshot = await adb(['exec-out', 'screencap', '-p']);
  await writeFile(prefix + '.png', screenshot.stdout);
  await writeFile(prefix + '-after.json', JSON.stringify(after, null, 2));
  const evidence = { serial, package: packageId, action, selector, destination, target, adb_args: args,
    input_started_ms: inputStarted, input_finished_ms: inputFinished, capture_padding_ms: 2000,
    before_version: before.version,
    after_version: after.version, screenshot: prefix + '.png', scene: after.scene,
    received_touches: after.touches.filter(t => t.ticks_ms > before.ticks_ms) };
  if (action === 'tap' || action === 'swipe' || action === 'pinch') {
    touchPoints ??= [[Number(args[3]), Number(args[4])]];
    evidence.touch_observed = touchPoints.every(([x, y]) => evidence.received_touches.some(t => Math.hypot(t.screen[0] - x, t.screen[1] - y) < 3));
    const matched = evidence.received_touches.filter(t => touchPoints.some(([x, y]) => Math.hypot(t.screen[0] - x, t.screen[1] - y) < 3));
    evidence.geometry_age_ms = matched.length ? Math.min(...matched.map(t => t.ticks_ms)) - before.ticks_ms : null;
    if (!evidence.touch_observed) process.exitCode = 1;
  }
  await writeFile(prefix + '-action.json', JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence, null, 2));
}

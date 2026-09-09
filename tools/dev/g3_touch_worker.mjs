import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execute = promisify(execFile);
const pause = ms => new Promise(done => setTimeout(done, ms));

export function parseArgs(args) {
  const options = { base: 'http://127.0.0.1:3103/v1', adb: 'adb', out: 'output/g3-week/touch-host', timeout: 3600 };
  for (const arg of args) {
    const match = /^--(base|serial|run|adb|out|timeout)=(.+)$/.exec(arg);
    if (!match) throw new Error(`Unknown argument: ${arg}`);
    options[match[1]] = match[2];
  }
  if (!options.serial || !/^[a-zA-Z0-9_.:-]+$/.test(options.serial)) throw new Error('An explicit --serial is required');
  if (!/^[a-zA-Z0-9_-]{1,96}$/.test(options.run ?? '')) throw new Error('An explicit --run is required');
  const url = new URL(options.base);
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)
    || url.username || url.password || url.search || url.hash || !/^\/v1\/?$/.test(url.pathname))
    throw new Error('Host --base must be the loopback QA /v1 endpoint');
  options.base = options.base.replace(/\/$/, '');
  options.timeout = Number(options.timeout);
  if (!Number.isFinite(options.timeout) || options.timeout < 10 || options.timeout > 7200) throw new Error('Invalid timeout');
  return options;
}

export function screenSize(output) {
  const sizes = [...output.matchAll(/(?:Physical|Override) size:\s*(\d+)x(\d+)/g)];
  if (!sizes.length) throw new Error('ADB wm size did not report display bounds');
  const last = sizes.at(-1);
  return [Number(last[1]), Number(last[2])];
}

export function classifyDevice(evidence) {
  const props = evidence.properties;
  const emulated = evidence.serial.startsWith('emulator-') || props['ro.kernel.qemu'] === '1'
    || props['ro.boot.qemu'] === '1' || /goldfish|ranchu|vbox/i.test(props['ro.hardware'] ?? '');
  const physical = !emulated && evidence.adb_state === 'device'
    && (props['ro.kernel.qemu'] === '0' || props['ro.boot.qemu'] === '0' || /\busb:/.test(evidence.transport_line));
  return { physical_device: physical, device_kind: emulated ? 'emulator' : physical ? 'physical' : 'unverified' };
}

export function inputArgs(action, bounds) {
  if (!['tap', 'swipe'].includes(action.kind)) throw new Error('Only tap and swipe actions are supported');
  if (!Array.isArray(action.screen_points) || action.screen_points.length !== (action.kind === 'tap' ? 1 : 2))
    throw new Error('Unexpected number of input points');
  const points = action.screen_points.flatMap(point => {
    if (!Array.isArray(point) || point.length !== 2) throw new Error('Invalid point');
    return point.map((value, axis) => {
      if (!Number.isFinite(value) || value < 0 || Math.round(value) >= bounds[axis])
        throw new Error(`Input point is outside ADB display bounds: ${JSON.stringify(point)}`);
      return String(Math.round(value));
    });
  });
  // Keep a tap down across several render frames without issuing a second input.
  if (action.kind === 'tap') return ['shell', 'input', 'swipe', ...points, ...points, '80'];
  if (!Number.isInteger(action.duration_ms) || action.duration_ms < 50 || action.duration_ms > 10000)
    throw new Error('Invalid swipe duration');
  return ['shell', 'input', 'swipe', ...points, String(action.duration_ms)];
}

export function mergedReport(run, host) {
  const acked = host.actions.filter(action => action.ok);
  const passed = run.report?.passed === true && host.errors.length === 0 && host.actions.length > 0
    && acked.length === host.actions.length && run.checkpoints.every(checkpoint => checkpoint.ack?.ok === true);
  return { ...run.report, passed, run_id: run.run_id, interaction: 'adb_input_tap_swipe',
    physical_device: host.device.physical_device, device: host.device,
    input_source: 'host_adb_worker', actual_touch_actions: acked.length, host,
    fully_touch_driven: passed && !(run.report?.interaction_bypasses ?? []).some(entry => entry.scope === 'product') };
}

export async function main(options) {
  const workerId = `host_${process.pid}_${Date.now()}`;
  const host = { worker_id: workerId, started_at: new Date().toISOString(), device: {}, actions: [], errors: [] };
  const directory = resolve(options.out);
  await mkdir(directory, { recursive: true });
  const persist = async (name, value) => writeFile(resolve(directory, name), JSON.stringify(value, null, 2));
  const adb = async args => {
    const result = await execute(options.adb, ['-s', options.serial, ...args], { timeout: 20000, maxBuffer: 1024 * 1024 });
    return result.stdout.trim();
  };
  const request = async (method, path, body) => {
    const response = await fetch(`${options.base}/qa/touch${path}`, {
      method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    const result = await response.json();
    if (!response.ok) throw Object.assign(new Error(`QA ${method} ${path}: ${response.status} ${result.code ?? ''}`), { status: response.status });
    return result;
  };
  const prefix = `/runs/${options.run}`;
  let exitCode = 1;
  try {
    const properties = {};
    for (const key of ['ro.kernel.qemu', 'ro.boot.qemu', 'ro.hardware', 'ro.product.model',
      'ro.product.manufacturer', 'ro.product.device', 'ro.build.fingerprint']) properties[key] = await adb(['shell', 'getprop', key]);
    const list = await execute(options.adb, ['devices', '-l'], { timeout: 10000 });
    const wmSize = await adb(['shell', 'wm', 'size']);
    const evidence = { serial: options.serial, adb_state: await adb(['get-state']),
      reported_serial: await adb(['get-serialno']), properties, wm_size: wmSize, screen_size: screenSize(wmSize),
      transport_line: list.stdout.split('\n').find(line => line.split(/\s+/)[0] === options.serial) ?? '',
      captured_at: new Date().toISOString() };
    if (evidence.adb_state !== 'device' || evidence.reported_serial !== options.serial)
      throw new Error('ADB target identity could not be verified');
    host.device = { ...evidence, ...classifyDevice(evidence) };
    await persist('device.json', host.device);
    const deadline = Date.now() + options.timeout * 1000;
    while (true) {
      if (Date.now() > deadline) throw new Error('Timed out waiting for Godot touch run');
      try { await request('GET', prefix); break; }
      catch (error) { if (error.status && error.status !== 404) throw error; }
      await pause(300);
    }
    await request('POST', `${prefix}/device`, { worker_id: workerId, device: host.device });
    while (Date.now() < deadline) {
      const next = await request('GET', `${prefix}/next?worker_id=${workerId}`);
      if (next.status === 'finished') {
        const run = await request('GET', prefix);
        host.finished_at = new Date().toISOString();
        const report = mergedReport(run, host);
        await persist('report.json', report);
        exitCode = report.passed ? 0 : 1;
        console.log(JSON.stringify({ run: options.run, passed: report.passed, physical_device: report.physical_device,
          interaction: report.interaction, actions: host.actions.length, report: resolve(directory, 'report.json') }));
        return exitCode;
      }
      if (!next.action) { await pause(100); continue; }
      const action = next.action;
      const result = { id: action.id, label: action.label, worker_id: workerId,
        started_at: new Date().toISOString(), ok: false };
      try {
        result.adb_args = inputArgs(action, host.device.screen_size);
        await adb(result.adb_args);
        result.ok = true;
      } catch (error) { result.error = error.message; host.errors.push(error.message); }
      result.finished_at = new Date().toISOString();
      host.actions.push(result);
      await persist('host.json', host);
      // Retry acknowledgement only. Repeating the Android input could purchase or gift twice.
      let acknowledged = false;
      for (let attempt = 0; attempt < 4; attempt++) {
        try { await request('POST', `${prefix}/checkpoints/${action.id}/ack`, result); acknowledged = true; break; }
        catch (error) { if (attempt === 3) throw error; await pause(200); }
      }
      if (!acknowledged) throw new Error(`Could not acknowledge touch ${action.id}`);
    }
    throw new Error('Godot run exceeded the worker deadline');
  } catch (error) {
    host.errors.push(error.message);
    console.error(error.message);
    return exitCode;
  } finally { host.finished_at ??= new Date().toISOString(); await persist('host.json', host); }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = await main(parseArgs(process.argv.slice(2))); }
  catch (error) { console.error(error.message); process.exitCode = 2; }
}

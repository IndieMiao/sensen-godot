import assert from 'node:assert/strict';
import { test } from 'node:test';
import { classifyDevice, inputArgs, mergedReport, parseArgs, screenSize } from './g3_touch_worker.mjs';

test('worker requires an explicit target, run and loopback QA server', () => {
  assert.throws(() => parseArgs(['--run=test']), /serial/);
  assert.throws(() => parseArgs(['--serial=target']), /run/);
  assert.throws(() => parseArgs(['--serial=target', '--run=test', '--base=https://farm.sensenjoy.cn/v1']), /loopback/);
  assert.equal(parseArgs(['--serial=emulator-5554', '--run=test']).base, 'http://127.0.0.1:3103/v1');
});

test('physical classification requires device evidence and cannot follow Android platform alone', () => {
  const base = { serial: 'phone_serial', adb_state: 'device', properties: {}, transport_line: '' };
  assert.deepEqual(classifyDevice(base), { physical_device: false, device_kind: 'unverified' });
  assert.equal(classifyDevice({ ...base, transport_line: 'phone_serial device usb:1-2 product:phone' }).physical_device, true);
  assert.equal(classifyDevice({ ...base, properties: { 'ro.kernel.qemu': '0' } }).physical_device, true);
  assert.equal(classifyDevice({ ...base, serial: 'emulator-5554', properties: { 'ro.kernel.qemu': '0' } }).physical_device, false);
  assert.equal(classifyDevice({ ...base, properties: { 'ro.kernel.qemu': '1' } }).device_kind, 'emulator');
});

test('ADB coordinates respect the active override display size and input whitelist', () => {
  assert.deepEqual(screenSize('Physical size: 1080x2400\nOverride size: 720x1600'), [720, 1600]);
  const action = { kind: 'tap', screen_points: [[100.2, 200.8]] };
  assert.deepEqual(inputArgs(action, [720, 1600]), ['shell', 'input', 'swipe', '100', '201', '100', '201', '80']);
  assert.deepEqual(inputArgs({ kind: 'swipe', screen_points: [[100, 300], [100, 100]], duration_ms: 350 }, [720, 1600]),
    ['shell', 'input', 'swipe', '100', '300', '100', '100', '350']);
  assert.throws(() => inputArgs({ ...action, kind: 'keyevent' }, [720, 1600]));
  assert.throws(() => inputArgs({ ...action, screen_points: [[720, 0]] }, [720, 1600]));
  assert.throws(() => inputArgs({ ...action, screen_points: [['100; reboot', 0]] }, [720, 1600]));
});

test('tap holds one contact for 80ms and swipe retains its explicit duration', () => {
  assert.deepEqual(inputArgs({ kind: 'tap', screen_points: [[114, 171]], duration_ms: 800 }, [1080, 2344]),
    ['shell', 'input', 'swipe', '114', '171', '114', '171', '80']);
  assert.deepEqual(inputArgs({ kind: 'swipe', screen_points: [[114, 171], [114, 171]], duration_ms: 800 }, [1080, 2344]),
    ['shell', 'input', 'swipe', '114', '171', '114', '171', '800']);
  assert.throws(() => inputArgs({ kind: 'swipe', screen_points: [[0, 0], [0, 0]], duration_ms: 0 }, [1080, 2344]), /duration/);
});

test('merged evidence fails missing input and keeps product bypasses explicit', () => {
  const run = { run_id: 'test', report: { passed: true, platform: 'Android', interaction_bypasses: [] }, checkpoints: [{ ack: { ok: true } }] };
  const host = { device: { physical_device: false }, actions: [{ ok: true }], errors: [] };
  assert.equal(mergedReport(run, host).passed, true);
  assert.equal(mergedReport(run, host).physical_device, false);
  assert.equal(mergedReport(run, { ...host, actions: [] }).passed, false);
  assert.equal(mergedReport({ ...run, report: { ...run.report, interaction_bypasses: [{ scope: 'product' }] } }, host).fully_touch_driven, false);
  assert.equal(mergedReport({ ...run, checkpoints: [{ ack: null }] }, host).passed, false);
});

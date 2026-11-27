// Device serial for the Android QA scripts, same rule as tools/android/run_serial.sh (C-212, C-216): the first set
// variable in `names`, else the Run's own device (`host`), else undefined. When the host gave this Run a device
// (CARDIGAN_EMULATOR_SERIAL or CARDIGAN_DEVICE_SERIAL is set), a variable naming any other device is skipped with a
// warning: a JOURNEY_SERIAL left in the login environment must not move the Run to a device it does not hold.
const RUN_DEVICES = ['ANDROID_SERIAL', 'CARDIGAN_EMULATOR_SERIAL', 'CARDIGAN_DEVICE_SERIAL'];

export function runSerial(names, { host = RUN_DEVICES, env = process.env, warn = console.error } = {}) {
  const inRun = Boolean(env.CARDIGAN_EMULATOR_SERIAL || env.CARDIGAN_DEVICE_SERIAL);
  const devices = RUN_DEVICES.map(name => env[name]).filter(Boolean);
  for (const name of names) {
    const value = env[name];
    if (!value) continue;
    if (!inRun || devices.includes(value)) return value;
    warn(`${name}=${value} is not a device of this Run; ignoring it.`);
  }
  return host.map(name => env[name]).find(Boolean);
}

// The emulator-only QA scripts refuse anything else, e.g. a phone picked by run_test.sh --device.
export function requireEmulator(serial) {
  if (!serial.startsWith('emulator-')) throw new Error(`${serial} is not an emulator; this script runs on emulators only.`);
  return serial;
}

// Serial for the emulator-only QA scripts: JOURNEY_SERIAL, then the Run's emulator, else emulator-5560 outside a Run.
// A Run the host gave only a physical device has no emulator of its own; emulator-5560 belongs to someone else (C-217).
export function runEmulator({ env = process.env, warn = console.error } = {}) {
  const serial = runSerial(['JOURNEY_SERIAL'], { host: ['CARDIGAN_EMULATOR_SERIAL'], env, warn });
  if (serial) return requireEmulator(serial);
  if (env.CARDIGAN_DEVICE_SERIAL) {
    throw new Error(`This Run holds no emulator (CARDIGAN_EMULATOR_SERIAL is not set, only the device ${env.CARDIGAN_DEVICE_SERIAL}); ` +
      'this script runs on emulators only and does not fall back to emulator-5560.');
  }
  return 'emulator-5560';
}

import { readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const directory = path.resolve(process.argv[2] ?? 'output/journey-emulator/evidence');
const names = await readdir(directory);
const files = names.filter(name => name.endsWith('-action.json')).sort();
const actions = [];
const launches = new Set();
let last;
for (const file of files) {
  const action = JSON.parse(await readFile(path.join(directory, file), 'utf8'));
  const before = JSON.parse(await readFile(path.join(directory, file.replace('-action.json', '-before.json')), 'utf8'));
  const snapshot = JSON.parse(await readFile(path.join(directory, file.replace('-action.json', '-after.json')), 'utf8'));
  launches.add(snapshot.launch_id);
  actions.push({ file, action: action.action, selector: action.selector, received: action.touch_observed,
    version: action.after_version, scene: snapshot.world?.place ?? snapshot.scene,
    fresh: before.launch_id !== snapshot.launch_id || before.ticks_ms < snapshot.ticks_ms });
  last = snapshot;
}
const input = actions.filter(a => ['tap', 'swipe', 'pinch'].includes(a.action));
const report = {
  evidence_directory: directory,
  recorded_inputs: input.length,
  observed_inputs: input.filter(a => a.received).length,
  missing_receipts: input.filter(a => !a.received),
  incomplete_trials: names.filter(name => name.endsWith('-before.json')
    && !names.includes(name.replace('-before.json', '-action.json'))).sort(),
  stale_captures: actions.filter(a => a.action === 'capture' && !a.fresh),
  launches: launches.size,
  world_gather_inputs: input.filter(a => /^(Target_|object:)((nursery|bistro|courtyard)_(west|east)|side_path)$/.test(a.selector ?? '')).length,
  ground_inputs: input.filter(a => a.selector?.startsWith('ground:')).length,
  plot_inputs: input.filter(a => a.selector?.startsWith('plot:')).length,
  final_version: last?.version,
  final_journey: last?.state.journey,
  final_decorations: last?.state.decorations,
  active_play_minutes_verified: false,
  duration_note: 'Input evidence includes development pauses and navigation checks. Wall time is not active play time.',
  actions,
};
const destination = path.resolve(directory, '../report.json');
await writeFile(destination, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ...report, actions: undefined, report: destination }, null, 2));

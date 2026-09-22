import { readFile, readdir, writeFile } from 'node:fs/promises';
import { isDeepStrictEqual } from 'node:util';

const root = 'output/combat-emulator-2026-09-15';
const files = await readdir(`${root}/actions`);
const snapshots = new Map();
for (const file of files.filter(name => /-(before|after)\.json$/.test(name))) {
  const snapshot = JSON.parse(await readFile(`${root}/actions/${file}`, 'utf8'));
  if (snapshot.state && snapshot.version >= 0) snapshots.set(snapshot.version, snapshot.state);
}
const s = version => { if (!snapshots.has(version)) throw new Error(`Missing recorded v${version}`); return snapshots.get(version); };
const quantity = (state, id) => [...state.bag.slots, ...state.bag.overflow, ...Object.values(state.bag.equipped).filter(Boolean)]
  .filter(stack => stack.item_id === id).reduce((sum, stack) => sum + stack.quantity, 0);
const checks = {};
checks.population = isDeepStrictEqual(s(1).mine.combat.monsters, { 1: [], 2: [], 3: [38], 4: [38, 38, 38], 5: [150] });
checks.starter_weapon_and_tool = s(1).bag.equipped.weapon.item_id === 'rusty_sword' && s(1).bag.equipped.tool.item_id === 'hand_tools';
checks.first_two_floors_without_damage = s(14).character.hp === 100 && s(14).mine.broken['1'].length === 6 && s(14).mine.broken['2'].length === 6;
checks.rescue_keeps_items = s(26).character.hp === 1 && s(26).mine.floor === 0 && isDeepStrictEqual(s(23).bag, s(26).bag) && s(23).wallet === s(26).wallet;
checks.rest_and_partial_enemy_save = s(27).character.hp === 100 && s(30).mine.combat.monsters['3'][0] === 24;
checks.held_sword_finishes_slime = s(32).mine.combat.monsters['3'][0] === 0 && s(32).character.hp === 100 && quantity(s(32), 'fiber') === quantity(s(30), 'fiber') + 1;
checks.three_slimes_and_multi_target_hit = isDeepStrictEqual(s(42).mine.combat.monsters['4'], [10, 10, 38]) && isDeepStrictEqual(s(48).mine.combat.monsters['4'], [0, 0, 0]);
checks.elite_keeps_damage_after_rescue = s(66).mine.combat.monsters['5'][0] === 54 && s(66).character.hp === 1 && s(66).mine.floor === 0;
checks.copper_sword_cost = quantity(s(68), 'wood') - quantity(s(69), 'wood') === 3
  && quantity(s(68), 'stone') - quantity(s(69), 'stone') === 2 && quantity(s(68), 'copper_ore') - quantity(s(69), 'copper_ore') === 5;
checks.boots_cost = quantity(s(69), 'fiber') - quantity(s(70), 'fiber') === 6 && quantity(s(69), 'copper_ore') - quantity(s(70), 'copper_ore') === 2;
checks.separate_slots_no_equip_heal = s(72).bag.equipped.weapon.item_id === 'copper_sword'
  && s(72).bag.equipped.accessory.item_id === 'trail_boots' && s(72).bag.equipped.tool.item_id === 'hand_tools' && s(72).character.hp === 100;
checks.food_heals_to_equipment_cap = s(74).character.hp === 120 && quantity(s(73), 'vegetable_soup') - quantity(s(74), 'vegetable_soup') === 1;
checks.defense_reduces_elite_hit = s(78).character.hp - s(82).character.hp === 18;
checks.elite_loot_once = quantity(s(82), 'copper_ore') - quantity(s(78), 'copper_ore') === 3 && quantity(s(82), 'rock_salt') - quantity(s(78), 'rock_salt') === 2;
checks.healing_preserves_active_uses = s(83).character.hp === 120 && isDeepStrictEqual(s(82).character.buffs, s(83).character.buffs)
  && s(83).character.buffs[0].remaining_uses === 3 && quantity(s(82), 'vegetable_soup') - quantity(s(83), 'vegetable_soup') === 1;
checks.elite_alone_does_not_unlock = s(82).mine.elevator_unlocked === false;
checks.rocks_and_elite_unlock = s(89).mine.elevator_unlocked && s(89).mine.cleared_floors.length === 5;
checks.mining_meal_expires_on_rocks = quantity(s(89), 'stone') - quantity(s(83), 'stone') === 9 && s(89).character.buffs.length === 0;
checks.elevator_roundtrip = s(90).mine.floor === 1 && s(91).mine.floor === 5 && isDeepStrictEqual(s(90).bag, s(91).bag);
checks.new_run_respawns_keeps_elevator = s(94).mine.run === 1 && s(94).mine.elevator_unlocked && isDeepStrictEqual(s(94).mine.combat.monsters, s(1).mine.combat.monsters);
checks.full_bag_combat_overflow = s(107).bag.slots.length === 24 && s(107).mine.combat.monsters['5'][0] === 0
  && isDeepStrictEqual(s(107).bag.overflow.map(stack => [stack.item_id, stack.quantity]), [['copper_ore', 3], ['rock_salt', 2]]);
checks.resident_requests_preserved = isDeepStrictEqual(s(1).residents, s(107).residents)
  && isDeepStrictEqual(s(1).journey.opportunities, s(107).journey.opportunities);
for (const version of [54, 107, 121]) {
  const report = JSON.parse(await readFile(`${root}/cold-start-${version}.json`, 'utf8'));
  checks[`cold_start_${version}`] = report.passed;
}
const gestures = files.filter(name => name.endsWith('-move-attack.json'));
checks.ready_for_next_session = s(121).character.hp === 120 && s(121).mine.run === 2 && s(121).mine.floor === 0
  && s(121).bag.overflow.length === 0 && s(121).bag.slots.length < 24 && s(121).mine.elevator_unlocked
  && isDeepStrictEqual(s(121).mine.combat.monsters, s(1).mine.combat.monsters);
checks.two_pointer_move_and_attack = gestures.length >= 2;
for (const name of gestures) checks.two_pointer_move_and_attack &&= JSON.parse(await readFile(`${root}/actions/${name}`, 'utf8')).passed;
const report = { passed: Object.values(checks).every(Boolean), checks, observed_versions: [...snapshots.keys()].sort((a, b) => a - b),
  recorded_touch_actions: files.filter(name => name.endsWith('-action.json')).length, multitouch_actions: gestures.length,
  artificial_fixtures: ['materials v67', 'full bag v95', 'restore v108'], physical_device_verified: false, natural_player_verified: false };
await writeFile(`${root}/playtest.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ passed: report.passed, checks: Object.keys(checks).length, failed: Object.keys(checks).filter(key => !checks[key]) }));
if (!report.passed) process.exitCode = 1;

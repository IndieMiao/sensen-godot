import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const base = process.env.VERIFY_BASE ?? 'http://127.0.0.1:3137/v1';
const output = process.env.VERIFY_OUTPUT ?? 'output/localization-qa-20260913-investor/http';
const phase = process.argv[2] ?? 'plant';
assert.ok(['plant', 'harvest'].includes(phase));
mkdirSync(path.join(output, 'private'), { recursive: true, mode: 0o700 });
const savedPath = path.join(output, 'private/accounts.json');
const accounts = phase === 'harvest' ? JSON.parse(readFileSync(savedPath, 'utf8')) : [];
let token = '';
const checks = [];
async function request(method, route, body, expected = 200) {
  const response = await fetch(base + route, { method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(15000) });
  const result = await response.json();
  assert.equal(response.status, expected, `${method} ${route}: ${result.code ?? ''}`);
  checks.push({ method, route, status: response.status });
  return result;
}
async function command(farm, type, payload, replay = false) {
  const body = { idempotency_key: randomUUID(), base_version: farm.version, type, payload };
  const result = await request('POST', '/farms/me/commands', body);
  assert.equal(result.outcome, 'applied');
  if (replay) {
    const repeated = await request('POST', '/farms/me/commands', body);
    assert.equal(repeated.outcome, 'replayed');
    assert.deepEqual(repeated.state, result.state);
    assert.equal(repeated.version, result.version);
  }
  return result;
}
const health = await request('GET', '/healthz');
assert.equal(health.domain_version, '14');
if (phase === 'plant') {
  for (const region of ['shanghai', 'los_angeles']) {
    const installKey = randomBytes(16).toString('hex');
    const auth = await request('POST', '/auth/anonymous', { install_key: installKey });
    token = auth.token;
    const account = { installKey, token, playerId: auth.player_id, region };
    const body = { idempotency_key: randomUUID(), region_id: region,
      layout_patch_id: region === 'shanghai' ? 'sh_b' : 'la_a', blueprint_revision: 2 };
    let farm = await request('POST', '/farms', body, 201);
    assert.equal((await request('POST', '/farms', body)).farm_id, farm.farm_id);
    assert.equal(farm.state.field_progress.plots, 4);
    assert.equal(farm.state.qa?.scale ?? 1, 1);
    account.farmId = farm.farm_id;
    const order = farm.state.field_progress.order;
    const locked = await request('POST', '/farms/me/commands', { idempotency_key: randomUUID(),
      base_version: farm.version, type: 'clear_cells', payload: { cell_ids: [order[4]] } }, 422);
    assert.equal(locked.code, 'CELL_LOCKED');
    for (const cells of [order.slice(0, 4), order.slice(4, 6)]) {
      for (const type of ['clear_cells', 'till_cells']) farm = await command(farm, type, { cell_ids: cells });
      farm = await command(farm, 'sow_cells', { cell_ids: cells, crop: 'R', lot: 'bound' }, true);
      assert.equal(farm.state.field_progress.plots, 6);
      const weather = JSON.parse(readFileSync('assets/farm/data/weather_script.json', 'utf8'));
      const kind = weather.care_action[farm.state.cells[cells[0]].care_weather];
      farm = await command(farm, 'apply_care', { cell_ids: cells, kind });
    }
    account.cells = order.slice(0, 6);
    account.readyAt = Math.max(...account.cells.map(id => farm.state.cells[id].ready_at));
    const nearby = await request('GET', `/nearby?region_id=${region}`);
    const demos = nearby.entries.filter(entry => entry.avatar_ref.startsWith('demo_') || entry.avatar_ref.startsWith('preset_'));
    assert.equal(demos.length, 18);
    for (const entry of demos) {
      const snapshot = await request('GET', `/farms/${entry.farm_id}/snapshot`);
      assert.equal(snapshot.farm_id, entry.farm_id);
      assert.equal(snapshot.region_id, region);
      assert.ok(snapshot.cells.length >= 9);
      for (const key of ['owner_id', 'wallet', 'inventory', 'residents', 'field_progress']) assert.ok(!(key in snapshot));
    }
    account.snapshot = await request('GET', '/farms/me');
    assert.deepEqual(account.snapshot.state, farm.state);
    accounts.push(account);
  }
} else {
  for (const account of accounts) {
    token = account.token;
    let farm = await request('GET', '/farms/me');
    assert.equal(farm.farm_id, account.farmId);
    assert.ok(farm.server_time >= account.readyAt, `Natural growth completes at ${new Date(account.readyAt).toISOString()}`);
    const before = farm.state.inventory.produce.R;
    farm = await command(farm, 'harvest_cells', { cell_ids: account.cells }, true);
    assert.equal(farm.state.field_progress.plots, 9);
    assert.equal(farm.state.field_progress.harvested, 6);
    assert.equal(farm.state.inventory.produce.R, before + 6);
    account.snapshot = await request('GET', '/farms/me');
    assert.deepEqual(account.snapshot.state, farm.state);
  }
}
writeFileSync(savedPath, JSON.stringify(accounts), { mode: 0o600 });
const report = { passed: true, phase, base, health, checks, accounts: accounts.map(account => ({
  region: account.region, farmId: account.farmId, plots: account.snapshot.state.field_progress.plots,
  readyAt: new Date(account.readyAt).toISOString(), version: account.snapshot.version,
})) };
writeFileSync(path.join(output, `${phase}.json`), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ passed: true, phase, accounts: report.accounts, requests: checks.length }));

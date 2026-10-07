/** SGODOT-232 S7: the observation log (one line per command, plus reported UI moments) and the session report. */
import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { P0EventLog, type LogRecord } from '../../src/p0/telemetry.js';
import { sessionReport } from '../../tools/p0_session_report.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2);
const headers = { 'x-p0-player': 'telemetry-player' };

async function withServer(fn: (app: ReturnType<typeof Fastify>, records: LogRecord[], tick: (ms: number) => void) => Promise<void>, dir?: string) {
  const records: LogRecord[] = [];
  let now = T0;
  const app = Fastify();
  registerP0Routes(app, { content: c, store: new P0Store(c), now: () => now, dev: false, log: new P0EventLog(dir, r => records.push(r)) });
  try { await fn(app, records, ms => { now += ms; }); } finally { await app.close(); }
}

describe('observation log (§14.8.1, §17.2.2; SGODOT-232 S7)', () => {
  it('writes one line per command with how it was pressed, the result, the Energy before and after and the events', async () => {
    await withServer(async (app, records) => {
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'sow', plot: 0, seed: 'seed_radish', src: 'hold', space: 'home', note: 'x'.repeat(500) } });
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'sow', plot: 0, seed: 'seed_radish', src: 'tap' } });
      const [sow, again] = records as Extract<LogRecord, { kind: 'command' }>[];
      expect(sow).toMatchObject({ kind: 'command', t: T0, player: 'telemetry-player', seq: 0, ok: true, energy: [200, 198],
        cmd: { type: 'sow', plot: 0, seed: 'seed_radish', src: 'hold', space: 'home' } });
      expect(sow.cmd).not.toHaveProperty('note');
      expect(sow.events).toContainEqual({ kind: 'energy', delta: -2, reason: 'sow' });
      expect(again).toMatchObject({ ok: false, code: 'wrong_state', energy: [198, 198], events: [] });
    });
  });

  it('keeps reported UI moments of known kinds only, with short flat fields, and limits them per minute', async () => {
    await withServer(async (app, records, tick) => {
      const events = [{ kind: 'tip_shown', key: 'sow', text: 'y'.repeat(200) }, { kind: 'secret_location', lat: 31.2 }, { kind: 'card_shown', card: { nested: 1 } }];
      const r = await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events } });
      expect(r.json()).toEqual({ ok: true, accepted: 2 });
      expect(records).toEqual([
        { kind: 'ui', t: T0, player: 'telemetry-player', event: { kind: 'tip_shown', key: 'sow', text: 'y'.repeat(80) } },
        { kind: 'ui', t: T0, player: 'telemetry-player', event: { kind: 'card_shown' } }]);
      for (let i = 0; i < 7; i++) await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: Array(20).fill({ kind: 'screen' }) } });
      expect(records.length).toBe(120);   // 2 + 118 more this minute
      tick(60_000);
      await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: [{ kind: 'screen' }] } });
      expect(records.length).toBe(121);
      expect((await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: Array(21).fill({ kind: 'screen' }) } })).statusCode).toBe(400);
    });
  });

  it('appends to a daily JSONL file', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-events-'));
    try {
      await withServer(async app => {
        await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'rest' } });
      }, dir);
      const lines = readFileSync(path.join(dir, 'p0-events-2026-10-08.jsonl'), 'utf8').trim().split('\n');
      expect(lines).toHaveLength(1);
      expect(JSON.parse(lines[0])).toMatchObject({ kind: 'command', cmd: { type: 'rest' }, ok: false });
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});

describe('first-session report (§14.2 director table; SGODOT-232 S7)', () => {
  it('finds the milestones, the end Energy and every Energy spend with how it was pressed', () => {
    const rec = (min: number, cmd: Record<string, unknown>, events: unknown[], energy: [number, number], code?: string) =>
      ({ kind: 'command', t: T0 + min * 60_000, clock: T0 + min * 60_000, player: 'p1', seq: 0, cmd, ok: !code, ...(code ? { code } : {}),
        energy, events }) as LogRecord;
    const records: LogRecord[] = [
      { kind: 'ui', t: T0, player: 'p1', event: { kind: 'session_start' } },   // the app opened at minute 0
      rec(1, { type: 'sow', src: 'hold' }, [{ kind: 'energy', delta: -2, reason: 'sow' }], [200, 198]),
      rec(9, { type: 'cast', src: 'tap' }, [{ kind: 'energy', delta: -5, reason: 'cast' }], [180, 175]),
      rec(10, { type: 'reel' }, [{ kind: 'catch', fish: 'fish_crucian', result: 'landed' }], [175, 175]),
      rec(15, { type: 'collect' }, [{ kind: 'dish', dish: 'dish_grilled_crucian', quality: 1 }], [150, 150]),
      rec(16, { type: 'eat' }, [{ kind: 'meal', gain: 25 }, { kind: 'energy', delta: 25, reason: 'eat' }], [151, 176]),
      rec(21, { type: 'reel' }, [{ kind: 'level', skill: 'fishing', level: 2, energy: 50 }], [148, 198]),
      rec(27, { type: 'collect' }, [{ kind: 'level', skill: 'cooking', level: 2, energy: 0 }], [213, 213]),
      rec(28, { type: 'sell' }, [], [213, 213], 'not_sellable'),
      rec(200, { type: 'harvest' }, [], [200, 200]),   // a later session
    ];
    const [p] = sessionReport(records);
    expect(p).toMatchObject({ player: 'p1', sessions: 2, first: {
      minutes: 28, end_energy: 213, refusals: { not_sellable: 1 },
      milestones: { first_sow: 1, first_cast: 9, first_catch: 10, first_dish: 15, first_meal: 16, fishing_lv2: 21, cooking_lv2: 27 },
    } });
    expect(p.first.spends).toEqual([{ minute: 1, type: 'sow', src: 'hold', energy: 2 }, { minute: 9, type: 'cast', src: 'tap', energy: 5 }]);
    expect(p.first.checks).toMatchObject({ loop_by_20: true, fishing_lv2_by_30: true, cooking_lv2_by_30: true });
  });
});

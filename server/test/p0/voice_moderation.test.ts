import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { AccessToken } from 'livekit-server-sdk';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { inForce } from '../../src/p0/accounts/identify.js';
import { P0Voice } from '../../src/p0/online/voice.js';
import { OutpostRooms } from '../../src/p0/online/rooms.js';
import { loadOutposts } from '../../src/p0/online/outposts.js';
import type { Sanction } from '../../src/p0/state.js';

const dirs: string[] = [];
afterEach(() => { vi.restoreAllMocks(); for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
function setup() {
  const dir = mkdtempSync(path.join(tmpdir(), 'voice-ban-')); dirs.push(dir);
  const files = { ages: path.join(dir, 'ages.json'), blocks: path.join(dir, 'blocks.json'), reports: path.join(dir, 'reports.jsonl') };
  writeFileSync(files.ages, JSON.stringify({ 'player-target': true, 'player-other': true }));
  writeFileSync(files.blocks, JSON.stringify({ 'player-target': ['player-other'] }));
  writeFileSync(files.reports, '{"retained":"report"}\n');
  const rooms = new OutpostRooms(loadOutposts());
  let now = 1_000_000, sanction: Sanction | undefined;
  const participants = new Map<string, string>();
  const removeParticipant = vi.fn(async (room: string, peer: string) => { participants.delete(room + '/' + peer); });
  const media = { getParticipant: async (room: string, peer: string) => ({ metadata: participants.get(room + '/' + peer) }), removeParticipant };
  const voice = new P0Voice({ url: 'ws://fake-voice.test', apiKey: 'fake', apiSecret: 'fake-only-secret-at-least-32-characters', namespace: 'test-ban' }, rooms, files, () => now, media);
  voice.voiceBanned = p => p === 'player-target' && !!inForce(sanction, now);
  const enter = (p: string) => { rooms.join(p, 'sh_tea_1'); };
  enter('player-target'); enter('player-other');
  const grant = async (p: string) => {
    const g = await voice.join(p) as Record<string, any>;
    participants.set(g.room + '/' + g.self, g.lease_id); return g;
  };
  return { voice, rooms, files, grant, participants, removeParticipant,
    ban: (until: number | null = null) => { sanction = { until, at: now }; }, tick: (ms: number) => { now += ms; }, now: () => now };
}

describe('484 voice moderation without deleting account/age/blocks', () => {
  it('refuses new grants, allows expiry on real time, and preserves room/age/blocks/report', async () => {
    const f = setup(), before = Object.values(f.files).map(p => readFileSync(p, 'utf8'));
    f.ban(f.now() + 1000);
    await expect(f.voice.join('player-target')).resolves.toEqual({ code: 'VOICE_BANNED', status: 403 });
    await expect(f.voice.join('player-other')).resolves.toMatchObject({ ok: true });
    f.tick(1000);
    await expect(f.voice.join('player-target')).resolves.toMatchObject({ ok: true });
    expect(f.rooms.occupant('player-target')).toBeDefined();
    expect(Object.values(f.files).map(p => readFileSync(p, 'utf8'))).toEqual(before);
  });

  it('management drop immediately withdraws only the target lease; heartbeat cannot renew while banned', async () => {
    const f = setup(), target = await f.grant('player-target'), other = await f.grant('player-other');
    const before = Object.values(f.files).map(p => readFileSync(p, 'utf8'));
    f.ban(); const dropping = f.voice.drop('player-target');
    expect(f.voice.heartbeat('player-target', target.lease_id)).toEqual({ code: 'VOICE_BANNED', status: 403 });
    await dropping;
    expect(f.removeParticipant).toHaveBeenCalledWith(target.room, target.self);
    expect(f.voice.heartbeat('player-other', other.lease_id)).toMatchObject({ ok: true });
    expect(Object.values(f.files).map(p => readFileSync(p, 'utf8'))).toEqual(before);
    expect(f.rooms.occupant('player-target')).toBeDefined();
  });

  it('heartbeat detects a stored ban even if the management drop was interrupted', async () => {
    const f = setup(), target = await f.grant('player-target');
    f.ban();
    expect(f.voice.heartbeat('player-target', target.lease_id)).toEqual({ code: 'VOICE_BANNED', status: 403 });
    await vi.waitFor(() => expect(f.removeParticipant).toHaveBeenCalledWith(target.room, target.self));
  });

  it('checks again after JWT signing so an in-flight grant cannot bypass a new ban', async () => {
    const f = setup(); let finish!: (v: string) => void;
    vi.spyOn(AccessToken.prototype, 'toJwt').mockReturnValue(new Promise<string>(resolve => { finish = resolve; }));
    const joining = f.voice.join('player-target'); f.ban(); finish('fake-token');
    await expect(joining).resolves.toEqual({ code: 'VOICE_BANNED', status: 403 });
  });

  it('drop is idempotent and never kicks a different lease that reused the same peer id', async () => {
    const f = setup(), target = await f.grant('player-target');
    f.participants.set(target.room + '/' + target.self, 'newcomer-lease');
    await f.voice.drop('player-target'); await f.voice.drop('player-target');
    expect(f.removeParticipant).not.toHaveBeenCalled();
    expect(f.participants.get(target.room + '/' + target.self)).toBe('newcomer-lease');
  });
});

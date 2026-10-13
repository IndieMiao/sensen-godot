/** SGODOT-270: the home city moves to San Francisco — the 04:00 rollover follows its time zone, and saves let go of a
 * Shanghai pond on load. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { dayKey, rolloverAfter, untilRollover } from '../../src/p0/rules.js';
import { freshState, upgradeState } from '../../src/p0/state.js';

const base = loadP0Content();
const withZone = (tz?: string): P0Content => ({ ...base, profile: { ...base.profile, timezone: tz } });
/** A Shanghai home set spelled out, so these cases hold whatever city the shipped content is in. */
const shanghai: P0Content = {
  ...base,
  profile: { ...base.profile, city: 'Shanghai', timezone: 'Asia/Shanghai' },
  day: { ...base.day, utc_offset_hours: 8 },
  fishing: { ...base.fishing, places: {
    pond_shanghai_05: { name: 'Reed Pond', site: 'pond', city: 'shanghai', beginner: true },
    pond_shanghai_04: { name: 'Pebble Pond', site: 'river', city: 'shanghai' },
  } },
};
const sf = withZone('America/Los_Angeles');
const H = 3_600_000;

describe('the 04:00 rollover in the home time zone (SGODOT-270)', () => {
  it('San Francisco: the player day turns at 04:00 Pacific time', () => {
    expect(dayKey(sf, null, Date.UTC(2026, 9, 9, 10, 59))).toBe('2026-10-08');   // 03:59 PDT
    expect(dayKey(sf, null, Date.UTC(2026, 9, 9, 11, 0))).toBe('2026-10-09');    // 04:00 PDT
    expect(untilRollover(sf, null, Date.UTC(2026, 9, 9, 14))).toBe(21 * H);       // 07:00 PDT → 04:00 tomorrow
  });

  it('follows daylight saving: 04:00 PDT before 1 November, 04:00 PST after; 14 March 2027 back to PDT', () => {
    expect(rolloverAfter(sf, null, '2026-10-30')).toBe(Date.UTC(2026, 9, 31, 11));   // 04:00 PDT = 11:00 UTC
    expect(rolloverAfter(sf, null, '2026-10-31')).toBe(Date.UTC(2026, 10, 1, 12));   // DST ends 02:00 → 04:00 PST = 12:00 UTC
    expect(untilRollover(sf, null, Date.UTC(2026, 10, 1, 8))).toBe(4 * H);          // 01:00 PDT, before the switch: 25 h day
    expect(rolloverAfter(sf, null, '2027-03-13')).toBe(Date.UTC(2027, 2, 14, 11));   // DST starts 02:00 → 04:00 PDT = 11:00 UTC
    expect(dayKey(sf, null, Date.UTC(2026, 10, 1, 11, 30))).toBe('2026-10-31');     // 03:30 PST: still the 31st's day
    expect(dayKey(sf, null, Date.UTC(2026, 10, 1, 12))).toBe('2026-11-01');
  });

  it('without a time zone the fixed offset still applies (Shanghai, UTC+8)', () => {
    const sh: P0Content = { ...shanghai, profile: { ...shanghai.profile, timezone: undefined } };
    expect(dayKey(sh, null, Date.UTC(2026, 9, 8, 19, 59))).toBe('2026-10-08');   // 03:59 CST
    expect(dayKey(sh, null, Date.UTC(2026, 9, 8, 20, 0))).toBe('2026-10-09');    // 04:00 CST
    expect(rolloverAfter(sh, null, '2026-10-09')).toBe(Date.UTC(2026, 9, 9, 20));
  });

  it('switching between 19:00 and 04:00 Beijing time keeps today\'s key (no extra daily reset)', () => {
    const sh = withZone('Asia/Shanghai');
    for (const h of [11, 14, 19.99]) {   // UTC hours: 19:00, 22:00 and 03:59 Beijing
      const t = Date.UTC(2026, 9, 9) + h * H;
      expect(dayKey(sf, null, t)).toBe(dayKey(sh, null, t));
    }
    expect(dayKey(sf, null, Date.UTC(2026, 9, 9, 21))).not.toBe(dayKey(sh, null, Date.UTC(2026, 9, 9, 21)));   // 05:00 Beijing: differs
  });
});

describe('a save lets go of a pond that is no longer on the map (SGODOT-270)', () => {
  const T = Date.UTC(2026, 9, 9, 14);
  const gone = 'pond_shanghai_05';
  const moved: P0Content = { ...shanghai, fishing: { ...shanghai.fishing, places: { pond_shanghai_04: shanghai.fishing.places.pond_shanghai_04 } } };

  it('forgets the place and brings an unfinished cast in with its Energy back', () => {
    const s = freshState(shanghai, 'switch-01', T);
    s.energy.value = 150;
    s.presence = { ...s.presence, space: 'pond', place: gone };
    s.cast = { fish: 'fish_crucian', site: 'pond', place: gone, at: T, bite_ms: 4000, bait: null, xp_pct: 100, breaks: null, pin: 'pin_first_cast' };
    s.firsts.push('pin_first_cast');
    const u = upgradeState(moved, structuredClone(s), T);
    expect(u.presence.place).toBeNull();
    expect(u.cast).toBeNull();
    expect(u.energy.value).toBe(150 + shanghai.fishing.cast_energy);
    expect(u.firsts).not.toContain('pin_first_cast');
  });

  it('a refund never lifts Energy past the bonus ceiling, and ponds still on the map are kept', () => {
    const s = freshState(shanghai, 'switch-02', T);
    const cap = shanghai.energy.max_base + shanghai.energy.bonus_zone;
    s.energy.value = cap - 1;
    s.cast = { fish: 'fish_crucian', site: 'pond', place: gone, at: T, bite_ms: 4000, bait: null, xp_pct: 100, breaks: null };
    expect(upgradeState(moved, structuredClone(s), T).energy.value).toBe(cap);
    const kept = 'pond_shanghai_04';
    s.presence = { ...s.presence, space: 'pond', place: kept };
    s.cast = { ...s.cast, place: kept };
    const u = upgradeState(moved, structuredClone(s), T);
    expect(u.presence.place).toBe(kept);
    expect(u.cast?.place).toBe(kept);
  });

  it('a pond still listed but in another city than home is let go too (as notePlace judges, 后裔 on #194)', () => {
    const s = freshState(shanghai, 'switch-03', T);
    s.presence = { ...s.presence, space: 'pond', place: gone };
    s.cast = { fish: 'fish_crucian', site: 'pond', place: gone, at: T, bite_ms: 4000, bait: null, xp_pct: 100, breaks: null };
    const elsewhere: P0Content = { ...shanghai, profile: { ...shanghai.profile, city: 'San Francisco' } };   // Shanghai's ponds still listed
    const u = upgradeState(elsewhere, structuredClone(s), T);
    expect(u.presence.place).toBeNull();
    expect(u.cast).toBeNull();
    expect(upgradeState(shanghai, structuredClone(s), T).presence.place).toBe(gone);   // at home in Shanghai it stays
  });
});

/** What the client receives: the settled state plus everything it would otherwise have to re-derive. */
import { cropBySeed, SKILLS, type P0Content } from './content.js';
import { dayKey, maxEnergy, nextTickIn, settleEnergy, skillLevel, untilRollover } from './rules.js';
import type { P0State } from './state.js';

export function viewOf(c: P0Content, input: P0State, now: number) {
  const s = structuredClone(input);
  settleEnergy(c, s, now);
  const restUsed = s.day.key === dayKey(c, now) ? s.day.rest : 0;
  const skills = Object.fromEntries(SKILLS.map(skill => {
    const level = skillLevel(c, s, skill), th = c.skills[skill];
    return [skill, { level, xp: s.skills[skill], floor: th[level - 1], next: level < th.length ? th[level] : null }];
  }));
  return {
    now, content_version: c.version, seq: s.seq,
    energy: { value: s.energy.value, max: maxEnergy(c, s), next_in: nextTickIn(c, s, now), regen_ms: c.energy.regen_ms },
    coins: s.coins,
    skills,
    plots: s.plots.map(p => ({
      id: p.id, state: p.state === 'growing' && (p.ready_at ?? Infinity) <= now ? 'ready' : p.state,
      crop: p.crop ?? null, ready_in: p.state === 'growing' && p.ready_at ? Math.max(0, p.ready_at - now) : null,
      xp_pct: p.xp_pct ?? null,
    })),
    bag: { capacity: c.bag.capacity, slots: s.bag },
    rest: { used: restUsed, limit: 1, resets_in: untilRollover(c, now), amount: c.energy.rest_amount },
    stall: {
      keeper: c.stall.keeper,
      buy: c.stall.buy.map(id => {
        const crop = cropBySeed(c, id)!;
        const level = skillLevel(c, s, 'farming');
        return { id, name: crop.seed_name, price: crop.seed_price, energy: crop.energy, gate: crop.gate,
          unlocked: level >= crop.gate, xp_to_go: Math.max(0, c.skills.farming[crop.gate - 1] - s.skills.farming) };
      }),
    },
    prices: Object.fromEntries(c.crops.map(crop => [crop.id, crop.price])),
    names: Object.fromEntries(c.crops.flatMap(crop => [[crop.id, crop.name], [crop.seed, crop.seed_name]])),
    crops: c.crops.map(crop => ({ id: crop.id, seed: crop.seed, energy: crop.energy, grow_h: crop.grow_h, level: crop.level })),
    firsts: s.firsts,
  };
}

import { RESIDENT_IDS, type Content } from './content.js';
import { stageOf } from './handlers/residents.js';
import { levelOf, type FarmState, type LifeChoice, type WeekSummary } from './state.js';

/** Called on a projected clone; only successful commands persist it. */
export function reconcileWeekSummary(s: FarmState, content: Content, completedAt: number): void {
  const finalChapter = content.chapters.chapters.length - 1;
  const validChoice = (value: unknown): value is LifeChoice =>
    value === 'gift' || value === 'keep' || value === 'sold';
  if (!s.week_summary) {
    if (s.chapters[finalChapter]?.status !== 'done' || !validChoice(s.life_choices[finalChapter])) return;
    const choices: Record<number, LifeChoice> = {};
    for (let chapter = 1; chapter <= finalChapter; chapter++) {
      const choice = s.life_choices[chapter];
      if (validChoice(choice)) choices[chapter] = choice;
    }
    const lifeCount = Object.values(choices).filter(choice => choice === 'gift' || choice === 'keep').length;
    const lifePriority = lifeCount >= content.chapters.life_priority_threshold;
    const relationships = Object.fromEntries(RESIDENT_IDS.map(id => [id, {
      points: s.residents[id].points, stage: stageOf(s.residents[id], { content }),
    }])) as WeekSummary['relationships'];
    s.week_summary = {
      id: 'first_week', completed_day: s.clock.player_day_id, completed_at: completedAt,
      life_priority: lifePriority, life_choice_count: lifeCount, choices,
      photo_variant: lifePriority ? 'personalized' : 'standard',
      journal_pages: lifePriority ? ['shared_harvest', 'familiar_faces'] : [],
      next_week_clue: lifePriority ? 'resident_seed_exchange' : 'nursery_next_stage',
      wallet: s.wallet, xp: s.xp.total, level: levelOf(s.xp.total, content.xp.level_thresholds),
      growth_choice: s.growth_choice.purchase,
      nursery: { stage: s.nursery.stage, appearance: s.nursery.appearance }, relationships,
    };
  }
  if (!s.handbook.some(entry => entry.kind === 'week_summary' && entry.key === s.week_summary!.id))
    s.handbook.push({ kind: 'week_summary', key: s.week_summary.id,
      day: s.week_summary.completed_day, life_priority: s.week_summary.life_priority });
}

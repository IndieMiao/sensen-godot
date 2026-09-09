import type { Command } from './commands.js';
import type { Content, CropId } from './content.js';
import { derive } from './derive.js';
import { materializeDay } from './handlers/day.js';
import type { Ctx } from './reducer.js';
import type { FarmState } from './state.js';
import { reconcileWeekSummary } from './week_summary.js';
import { reconcileJourney } from './journey.js';

const nextSown = (id: string) => `next_batch_sown:${id}`;
const nextCared = (id: string) => `next_batch_cared:${id}`;

/** Only persisted facts can repair old progress; current growing cells never prove a new batch. */
function reconcileChapter(s: FarmState, content: Content, blueprint: Ctx['blueprint']): void {
  const index = s.clock.chapter_index;
  const chapter = s.chapters[index];
  const definition = content.chapters.chapters[index];
  if (!chapter || !definition || chapter.status !== 'active') return;
  const flags = chapter.step_flags;
  switch (index) {
    case 0: {
      flags.farm_created = true;
      if (s.xp.first_harvest_crops.length > 0) flags.first_harvest = true;
      const beds = [...blueprint.cultivable].filter(id => !blueprint.reserved.has(id));
      if (flags.first_harvest && beds.length === 9 && beds.every(id =>
        flags[nextSown(id)] && flags[nextCared(id)] && s.cells[id]?.state === 'growing'))
        flags.next_batch_sown_and_cared = true;
      break;
    }
    case 1:
      if (s.requests_done.includes('d1_bistro_lettuce')) flags.request_d1_bistro_lettuce_done = true;
      break;
    case 2: {
      const choice = s.life_choices[2];
      if (choice !== undefined) flags.life_choice_resolved = true;
      if (choice !== undefined && s.residents.bistro_owner.choice_memories?.[2] === choice)
        flags.second_resident_remembers = true;
      break;
    }
    case 3:
      if (s.xp.first_recipes.includes('salad') && s.residents.bistro_owner.shared_event_done)
        flags.first_salad_cooked = true;
      if (s.requests_done.includes('d3_nursery_basket')) flags.request_d3_nursery_basket_done = true;
      break;
    case 4:
      if (Object.values(s.engineering.submitted).some(n => (n ?? 0) > 0))
        flags.engineering_first_submitted = true;
      break;
    case 5:
      if (s.growth_choice.intent !== null) flags.growth_intent_set = true;
      break;
    case 6:
      if (Object.entries(content.economy.engineering_quota).every(([crop, amount]) =>
        (s.engineering.submitted[crop as CropId] ?? 0) >= (amount ?? 0)))
        flags.engineering_quota_complete = true;
      if (s.residents.nursery_keeper.shared_event_done) flags.shared_scene_done = true;
      break;
  }
  if (!definition.min_facts.every(fact => flags[fact] === true)) return;
  chapter.status = 'done';
  const key = String(index);
  if (!s.handbook.some(entry => entry.kind === 'chapter_done' && entry.key === key))
    s.handbook.push({ kind: 'chapter_done', key, day: s.clock.player_day_id });
}

/** Called only after a successful command. Rejections cannot leave progress evidence. */
export function recordChapterProgress(before: FarmState, after: FarmState, cmd: Command, ctx: Ctx): FarmState {
  if (after.journey) return reconcileJourney(after, ctx.content);
  const next = structuredClone(after);
  const index = next.clock.chapter_index;
  const chapter = next.chapters[index];
  if (chapter.status === 'active') {
    const flags = chapter.step_flags;
    if (index === 0) {
      if (cmd.type === 'sow_cells' && before.xp.first_harvest_crops.length > 0) {
        for (const id of cmd.cell_ids) {
          flags[nextSown(id)] = true;
          delete flags[nextCared(id)];
        }
      }
      if (cmd.type === 'apply_care')
        for (const id of cmd.cell_ids) if (flags[nextSown(id)]) flags[nextCared(id)] = true;
      if (cmd.type === 'harvest_cells')
        for (const id of cmd.cell_ids) {
          delete flags[nextSown(id)];
          delete flags[nextCared(id)];
        }
    }
    if (index === 1 && cmd.type === 'apply_care' && cmd.kind === 'drain') flags.rain_care_done = true;
    if (index === 5 && cmd.type === 'apply_care' && cmd.kind === 'shelter') flags.wind_care_done = true;
    if (index === 2 && cmd.type === 'talk_to_resident' && cmd.resident_id === 'bistro_owner'
      && before.life_choices[2] !== undefined) {
      next.residents.bistro_owner.choice_memories ??= {};
      next.residents.bistro_owner.choice_memories[2] = before.life_choices[2];
    }
  }
  reconcileChapter(next, ctx.content, ctx.blueprint);
  reconcileWeekSummary(next, ctx.content, ctx.now);
  return next;
}

/** Pure owner-state projection. Callers provide effective server time, never the device clock. */
export function projectFarmState(
  s: FarmState, now: number, timezone: string, content: Content, blueprint: Ctx['blueprint'],
): FarmState {
  const next = structuredClone(s);
  if (next.journey) {
    const ctx: Ctx = { now, timezone, content, blueprint, derived: derive(next, now, timezone, content) };
    return reconcileJourney(materializeDay(next, ctx).state, content);
  }
  reconcileChapter(next, content, blueprint);
  // Legacy completed saves project the same snapshot repeatedly, anchored to their last persisted action.
  reconcileWeekSummary(next, content, next.clock.last_effective_now);
  const ctx: Ctx = { now, timezone, content, blueprint, derived: derive(next, now, timezone, content) };
  // Exactly one opening per projection; activated_day blocks another opening today.
  const materialized = materializeDay(next, ctx).state;
  reconcileChapter(materialized, content, blueprint);
  return materialized;
}

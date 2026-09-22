import type { Command } from './commands.js';
import type { Content, CropId, DishId, JourneyMaterial, JourneyOpportunity } from './content.js';
import { err, ok, type Result } from './errors.js';
import type { Ctx } from './reducer.js';
import type { FarmState, JourneyState } from './state.js';

type OpportunityCommand = Extract<Command, { type: 'accept_opportunity' | 'abandon_opportunity'
  | 'track_journey_opportunity' | 'fulfill_opportunity' | 'decline_opportunity' }>;
const COMMANDS = new Set(['accept_opportunity', 'abandon_opportunity', 'track_journey_opportunity',
  'fulfill_opportunity', 'decline_opportunity']);
const isOpportunityCommand = (cmd: Command): cmd is OpportunityCommand => COMMANDS.has(cmd.type);

export function opportunityAvailable(state: FarmState, slot: string, content: Content): boolean {
  if (!state.journey || !Object.hasOwn(state.journey.opportunities, slot)
    || !Object.hasOwn(content.journey.opportunities, slot)) return false;
  const offer = content.journey.opportunities[slot][state.journey.opportunities[slot].variant];
  return Boolean(offer && (!offer.requires || state.journey.unlocks.includes(offer.requires))
    && (slot !== 'bistro' || state.journey.facts.includes('shared_meal')));
}

/** Legacy tracked requests were explicit player choices; sequences alone are not completed work. */
export function reconcileOpportunities(state: FarmState, content: Content): void {
  const tracked = state.journey?.tracked_opportunity;
  if (!tracked || !opportunityAvailable(state, tracked.slot, content)) return;
  const slot = state.journey!.opportunities[tracked.slot];
  if (slot.sequence === tracked.sequence && slot.accepted === undefined) slot.accepted = true;
}

export function opportunityNeeds(offer: JourneyOpportunity): Record<string, number> {
  const needs: Record<string, number> = {};
  const add = (id: string, amount: number) => { if (amount > 0) needs[id] = (needs[id] ?? 0) + amount; };
  add('wood', offer.wood);
  for (const costs of [offer.produce, offer.dishes, offer.materials ?? {}, offer.props ?? {}])
    for (const [id, amount] of Object.entries(costs)) add(id, amount!);
  return needs;
}

function setTracked(journey: JourneyState, slot: string, sequence: number): void {
  journey.tracked_opportunity = { slot, sequence };
  delete journey.tracked_project;
  delete journey.tracked_discovery;
  if (journey.gathering) delete journey.gathering.planned;
  if (journey.workshop?.planned) {
    delete journey.workshop.planned;
    journey.workshop.sequence += 1;
  }
}

function clearTracked(journey: JourneyState, slot: string, sequence: number): void {
  if (journey.tracked_opportunity?.slot === slot && journey.tracked_opportunity.sequence === sequence)
    delete journey.tracked_opportunity;
}

/** Canonical bag projection supplies these counters; the reducer then spends the complete delta across stacks. */
function payOpportunity(state: FarmState, needs: Record<string, number>, content: Content): Result<FarmState> {
  let usedProps = false;
  for (const [id, amount] of Object.entries(needs)) {
    const item = content.items.items[id];
    if (!item) return err('NOT_AVAILABLE', 'Unknown request item');
    const source = item.source;
    let have: number;
    switch (source.kind) {
      case 'produce': have = state.inventory.produce[source.id as CropId] - (state.engineering.reserved[source.id as CropId] ?? 0); break;
      case 'dish': have = state.inventory.dishes[source.id as DishId] ?? 0; break;
      case 'material': have = source.id === 'wood' ? state.journey!.wood
        : state.journey!.materials?.[source.id as Exclude<JourneyMaterial, 'wood'>] ?? 0; break;
      case 'prop': have = state.journey!.workshop?.stock[source.id] ?? 0; break;
      default: return err('NOT_AVAILABLE', 'This item cannot be delivered');
    }
    if (have < amount) return err('INSUFFICIENT_ITEMS', id);
    switch (source.kind) {
      case 'produce': state.inventory.produce[source.id as CropId] -= amount; break;
      case 'dish': state.inventory.dishes[source.id as DishId] = have - amount; break;
      case 'material':
        if (source.id === 'wood') state.journey!.wood -= amount;
        else state.journey!.materials![source.id as Exclude<JourneyMaterial, 'wood'>] = have - amount;
        break;
      case 'prop': state.journey!.workshop!.stock[source.id] = have - amount; usedProps = true; break;
    }
  }
  if (usedProps) state.journey!.workshop!.sequence += 1;
  return ok(state);
}

export function applyOpportunities(state: FarmState, cmd: Command, ctx: Ctx): Result<FarmState> | null {
  if (!isOpportunityCommand(cmd)) return null;
  if (!state.journey || typeof cmd.slot !== 'string' || !Object.hasOwn(state.journey.opportunities, cmd.slot)
    || !Object.hasOwn(ctx.content.journey.opportunities, cmd.slot)) return err('NOT_AVAILABLE', 'Unknown request');
  const current = state.journey.opportunities[cmd.slot];
  if (!Number.isSafeInteger(cmd.sequence) || cmd.sequence !== current.sequence) return err('REQUEST_DONE');
  if (!opportunityAvailable(state, cmd.slot, ctx.content)) return err('NOT_AVAILABLE', 'Discover this request first');
  const next = structuredClone(state);
  const journey = next.journey!;
  journey.materials ??= { stone: 0, fiber: 0 };
  journey.facility_uses ??= {};
  const slot = journey.opportunities[cmd.slot];
  const offer = ctx.content.journey.opportunities[cmd.slot][slot.variant];
  const tracked = journey.tracked_opportunity;
  let timberIndex: number | undefined;
  if (cmd.type === 'decline_opportunity') {
    if (cmd.timber_only !== undefined && typeof cmd.timber_only !== 'boolean') return err('NOT_AVAILABLE', 'Unknown request action');
    if (cmd.timber_only) {
      if (cmd.slot !== 'restorer') return err('NOT_AVAILABLE', 'Timber work belongs to the restorer');
      if (offer.id === 'timber_for_repairs') return err('ALREADY_CLAIMED', 'Timber work is already available');
      timberIndex = ctx.content.journey.opportunities.restorer.findIndex(candidate => candidate.id === 'timber_for_repairs');
      if (timberIndex < 0) return err('NOT_AVAILABLE', 'Timber work is not available');
    }
  }
  if (cmd.type === 'accept_opportunity') {
    if (slot.accepted) return err('ALREADY_CLAIMED', 'This request is already accepted');
    slot.accepted = true;
    setTracked(journey, cmd.slot, cmd.sequence);
    return ok(next, [{ type: 'opportunity_accepted', slot: cmd.slot, sequence: cmd.sequence, offer_id: offer.id, resident_id: offer.resident_id }]);
  }
  if (cmd.type === 'track_journey_opportunity') {
    if (typeof cmd.tracking !== 'boolean') return err('NOT_AVAILABLE', 'Unknown request action');
    if (cmd.tracking) {
      if (tracked?.slot === cmd.slot && tracked.sequence === cmd.sequence) return err('ALREADY_CLAIMED');
      slot.accepted = true;
      setTracked(journey, cmd.slot, cmd.sequence);
    } else {
      if (tracked?.slot !== cmd.slot || tracked.sequence !== cmd.sequence) return err('REQUEST_DONE');
      clearTracked(journey, cmd.slot, cmd.sequence);
    }
    return ok(next);
  }
  if (slot.sequence === Number.MAX_SAFE_INTEGER) return err('NOT_AVAILABLE', 'This request sequence is exhausted');
  if (cmd.type === 'abandon_opportunity') {
    if (!slot.accepted) return err('REQUEST_DONE', 'This request is not accepted');
    slot.accepted = false;
    slot.sequence += 1;
    clearTracked(journey, cmd.slot, cmd.sequence);
    return ok(next, [{ type: 'opportunity_abandoned', slot: cmd.slot, sequence: cmd.sequence, offer_id: offer.id, resident_id: offer.resident_id }]);
  }
  let completion: NonNullable<typeof slot.last_completed> | undefined;
  if (cmd.type === 'fulfill_opportunity') {
    if (!slot.accepted) return err('REQUEST_DONE', 'Accept this request first');
    const consumed = opportunityNeeds(offer);
    const paid = payOpportunity(next, consumed, ctx.content);
    if (!paid.ok) return paid;
    next.wallet += offer.coins;
    journey.contributions ??= {};
    const contribution = Math.min(ctx.content.journey.contribution_steps, (journey.contributions[offer.effect] ?? 0) + 1);
    journey.contributions[offer.effect] = contribution;
    completion = { offer_id: offer.id, resident_id: offer.resident_id, sequence: cmd.sequence,
      consumed, coins: offer.coins, effect: offer.effect, contribution };
    slot.last_completed = completion;
  }
  slot.accepted = false;
  slot.sequence += 1;
  clearTracked(journey, cmd.slot, cmd.sequence);
  const variants = ctx.content.journey.opportunities[cmd.slot];
  // Existing indices stay stable; new definitions are appended and the next eligible offer is frozen.
  if (timberIndex !== undefined) slot.variant = timberIndex;
  else {
    for (let offset = 1; offset <= variants.length; offset++) {
      const index = (slot.variant + offset) % variants.length;
      if (!variants[index].requires || journey.unlocks.includes(variants[index].requires!)) {
        slot.variant = index;
        break;
      }
    }
  }
  return ok(next, [completion ? { type: 'opportunity_completed', slot: cmd.slot, ...completion }
    : { type: 'opportunity_declined', slot: cmd.slot, sequence: cmd.sequence, offer_id: offer.id, resident_id: offer.resident_id, coins: 0 }]);
}

import type { Content } from './content.js';
import type { FarmState } from './state.js';

export function beginFieldGrowth(state: FarmState, beds: string[], content: Content): FarmState {
  if (state.field_progress) return state;
  if (beds.length !== 9 || new Set(beds).size !== 9 || beds.some(id => !state.cells[id] || state.cells[id].state !== 'wild'))
    throw new Error('Field onboarding requires nine untouched blueprint beds');
  return { ...state, field_progress: {
    order: content.journey.field_growth.order.map(index => beds[index]), planted: 0, harvested: 0, plots: 4,
  } };
}

export function fieldCellUnlocked(state: FarmState, id: string): boolean {
  const progress = state.field_progress;
  return !progress || progress.order.slice(0, progress.plots).includes(id);
}

export function advanceFieldGrowth(state: FarmState, action: 'planted' | 'harvested', count: number, content: Content): void {
  const progress = state.field_progress;
  if (!progress) return;
  progress[action] += count;
  if (progress.planted >= content.journey.field_growth.plant_target) progress.plots = Math.max(progress.plots, 6) as 6 | 9;
  if (progress.planted >= content.journey.field_growth.plant_target && progress.harvested >= content.journey.field_growth.harvest_target)
    progress.plots = 9;
}

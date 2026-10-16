/**
 * The avatar actions every client animates: a P0 frame sends one by its index here (online/frame.ts adds `sit`), so the
 * order is wire format — append, never reorder. The Journey realtime rooms read the same list (realtime/model.ts
 * re-exports it) until the Journey server is retired (SGODOT-304); P0 owns it so that retirement leaves P0 whole.
 */
export const ACTIONS = ['idle', 'run', 'walk', 'labour_sow', 'labour_water', 'labour_harvest',
  'labour_drain', 'labour_shelter', 'emote_wave', 'attack', 'mine', 'labour_till', 'labour_clear', 'fishing_wait', 'fishing_reel'] as const;

import { describe, expect, it } from 'vitest';
import { upgradeFreeFarmState } from '../../src/domain/free_farm_migration.js';
import { freshFarm, plot } from './helpers.js';

describe('free-farm save conversion', () => {
  it('preserves crop ownership, IDs, old ripening deadlines and non-farm progress', () => {
    const state = freshFarm();
    const legacy: any = structuredClone(state);
    legacy.cells = {
      '4,2': { state:'wild', crop:null, ready_at:null },
      '6,2': { state:'cleared', crop:null, ready_at:null },
      '8,2': { state:'growing', crop:'R', care_done_at:100, ready_at:999 },
      '4,4': { state:'sown', crop:'L', care_done_at:null, ready_at:null },
      '6,4': { state:'tilled', crop:null, care_done_at:null, ready_at:null },
    };
    delete legacy.inventory.seeds.T; delete legacy.inventory.produce.T;
    const before=structuredClone(legacy);
    const result=upgradeFreeFarmState(legacy);
    expect(result.cells['4,2']).toBeUndefined();expect(result.cells['6,2']).toBeUndefined();
    expect(result.cells['8,2']).toEqual({...before.cells['8,2'],watered_at:100});
    expect(result.cells['4,4']).toEqual({...before.cells['4,4'],watered_at:null});
    expect(result.cells['6,4']).toEqual({...before.cells['6,4'],watered_at:null});
    expect(result.inventory.seeds.T).toEqual({bought:0,bound:0});
    expect(result.inventory.produce.T).toBe(0);
    expect({...result,cells:before.cells,inventory:before.inventory}).toEqual(before);
    expect(legacy).toEqual(before);
    expect(upgradeFreeFarmState(result)).toEqual(result);
  });
  it('leaves an existing free-farm save byte-for-byte equivalent', () => {
    const state=freshFarm();state.cells['28,35']={state:'growing',crop:'R',watered_at:2,ready_at:6};
    expect(upgradeFreeFarmState(state)).toEqual(state);
  });
  it('refuses an ambiguous legacy crop instead of deleting it', () => {
    const state:any=freshFarm();state.cells['4,2']={state:'wild',crop:'R',ready_at:999};
    expect(()=>upgradeFreeFarmState(state)).toThrow('Unexpected planted legacy cell');
  });
});


it('moves only newly blocked plots, preserves their crop data and never overwrites neighbours', () => {
  const state=freshFarm();
  state.cells['27,37']={state:'growing',crop:'R',watered_at:100,ready_at:999};
  state.cells['27,35']={state:'sown',crop:'L',watered_at:null,ready_at:null};
  const before=structuredClone(state);
  const upgraded=upgradeFreeFarmState(state,plot);
  expect(upgraded.cells['27,37']).toBeUndefined();
  expect(upgraded.cells['27,35']).toEqual(before.cells['27,35']);
  expect(Object.values(upgraded.cells)).toHaveLength(2);
  expect(Object.values(upgraded.cells)).toContainEqual(before.cells['27,37']);
  expect(upgraded.inventory).toEqual(before.inventory);
  expect(upgraded.clock).toEqual(before.clock);
  expect(upgradeFreeFarmState(upgraded,plot)).toEqual(upgraded);
  expect(state).toEqual(before);
});


it('retains legacy courtyard items and their local positions in the current grid format', () => {
  const state:any=freshFarm();
  state.decorations=[{prop_id:'planter',anchor_id:'courtyard',offset_q:[-3,5]}, {prop_id:'lantern',anchor_id:'courtyard',offset_q:[5,5]}];
  const upgraded=upgradeFreeFarmState(state,plot,{planter:[1,1],lantern:[1,1]});
  expect(upgraded.decorations).toEqual([{prop_id:'planter',cell:[29,7]},{prop_id:'lantern',cell:[37,7]}]);
  expect(upgraded.inventory).toEqual(state.inventory);
  expect(upgradeFreeFarmState(upgraded,plot,{planter:[1,1],lantern:[1,1]})).toEqual(upgraded);
});

it('keeps relocated crops out of placed furniture and moves blocked furniture without losing it', () => {
  const state=freshFarm();
  state.cells['27,37']={state:'growing',crop:'R',watered_at:100,ready_at:999};
  state.decorations=[{prop_id:'planter',cell:[27,35]},{prop_id:'lantern',cell:[28,38]}];
  const upgraded=upgradeFreeFarmState(state,plot,{planter:[1,1],lantern:[1,1]});
  expect(upgraded.cells['27,35']).toBeUndefined();
  expect(upgraded.decorations?.find(p=>p.prop_id==='planter')?.cell).toEqual([27,35]);
  expect(upgraded.decorations?.find(p=>p.prop_id==='lantern')?.cell).not.toEqual([28,38]);
  expect(upgraded.decorations).toHaveLength(2);
  expect(Object.values(upgraded.cells)).toEqual(Object.values(state.cells));
});

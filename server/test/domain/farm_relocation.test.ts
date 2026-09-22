import { describe, expect, it } from 'vitest';
import { relocateFarmState } from '../../src/domain/farm_relocation.js';
import { loadContent, DEFAULT_CONTENT_DIR } from '../../src/domain/content.js';
import { createInitialState } from '../../src/domain/state.js';
import { rasterize, type PlotLayoutSource } from '../../src/domain/plot.js';
const content = loadContent(DEFAULT_CONTENT_DIR);
const source = (regions: PlotLayoutSource['regions'] = []): PlotLayoutSource => ({ revision: 1, name: 'test', grid: [12,12], cell_mm:750,
  default_kind:'soil', anchors:{spawn:[0,0]}, regions });
const state = () => createInitialState({now:100,player_day_id:'2026-09-21',field_condition:'sunny',wallet:187});
const crop = {state:'growing' as const,crop:'R' as const,watered_at:100,ready_at:1234567};
describe('voluntary relocation keeps ownership and crop records',()=>{
  it('moves only conflicting coordinates, preserving all unrelated state, deadlines and rotations',()=>{
    const original=state();original.cells={'2,2':{...crop},'8,8':{...crop,ready_at:2345678}};
    original.decorations=[{prop_id:'bench',cell:[5,5],rotation_q:1}];
    original.inventory.seeds.R={bought:6,bound:3};original.nursery={stage:'built',appearance:'b'};
    const before=structuredClone(original);
    const plot=rasterize('test',source([{kind:'water',rect:[2,2,1,1]},{kind:'rock',rect:[5,5,2,1]}]));
    const moved=relocateFarmState(original,plot,content);
    expect(original).toEqual(before);expect(moved.moved_cells).toBe(1);expect(moved.moved_decorations).toBe(1);
    expect(moved.state.cells['8,8']).toEqual(original.cells['8,8']);expect(moved.state.cells['2,1']).toEqual(crop);
    expect(Object.values(moved.state.cells)).toEqual(expect.arrayContaining(Object.values(original.cells)));
    expect({...moved.state,cells:before.cells,decorations:before.decorations}).toEqual(before);
    expect(moved.state.decorations![0].rotation_q).toBe(1);
    expect(relocateFarmState(original,plot,content)).toEqual(moved);
  });
  it('does not move crops onto an unreachable island',()=>{
    const original=state();original.cells={'8,8':crop};
    const plot=rasterize('test',source([{kind:'water',rect:[6,0,1,12]}]));
    const moved=relocateFarmState(original,plot,content);expect(moved.state.cells['5,8']).toEqual(crop);
  });
  it('moves a blocking woody crop away from a one-cell bridge without resetting its maturity',()=>{
    const original=state();const woody=Object.entries(content.crops.crops).find(([,c])=>c.woody)![0];
    original.cells={'5,5':{...crop,crop:woody as typeof crop.crop}};
    const plot=rasterize('test',source([{kind:'water',rect:[5,0,1,12]},{kind:'soil',rect:[5,5,1,1]}]));
    const result=relocateFarmState(original,plot,content);expect(result.moved_cells).toBe(1);
    expect(result.state.cells['5,5']).toBeUndefined();expect(Object.values(result.state.cells)[0]).toEqual(original.cells['5,5']);
  });
  it('rejects without losing any item if there is insufficient cultivable land',()=>{
    const original=state();original.cells={'2,2':crop,'8,8':{...crop}};const before=structuredClone(original);
    const plot=rasterize('test',{...source(),default_kind:'lawn',regions:[{kind:'soil',rect:[2,2,1,1]}]});
    expect(()=>relocateFarmState(original,plot,content)).toThrow('RELOCATION_NO_SPACE');expect(original).toEqual(before);
  });
  it('keeps every woody crop accessible even when saved trees formerly surrounded one another',()=>{
    const original=state();const woody=Object.entries(content.crops.crops).find(([,c])=>c.woody)![0];
    for (const id of ['5,5','4,5','6,5','5,4','5,6']) original.cells[id]={...crop,crop:woody as typeof crop.crop};
    const result=relocateFarmState(original,rasterize('test',source()),content);
    expect(result.moved_cells).toBeGreaterThan(0);expect(Object.keys(result.state.cells)).toHaveLength(5);
    for(const id of Object.keys(result.state.cells)) {
      const [x,y]=id.split(',').map(Number);
      expect([[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(cell=>!result.state.cells[cell.join(',')])).toBe(true);
    }
  });
});

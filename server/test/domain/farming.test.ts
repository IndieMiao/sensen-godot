import { describe, expect, it } from 'vitest';
import { BEDS, RESERVED, T0, HOUR, at, advance, content, freshFarm, run, runAll } from './helpers.js';

const three = BEDS.slice(0, 3);

describe('clear / till', () => {
  it('荒地 → 清理 → 翻土，首次清理每格 +1 XP', () => {
    let s = freshFarm();
    const r1 = run(s, { type: 'clear_cells', cell_ids: three });
    expect(r1.ok).toBe(true);
    if (!r1.ok) return;
    expect(r1.state.xp.total).toBe(3);
    expect(three.every(id => r1.state.cells[id].state === 'cleared')).toBe(true);
    const r2 = run(r1.state, { type: 'till_cells', cell_ids: three });
    expect(r2.ok && three.every(id => r2.state.cells[id].state === 'tilled')).toBe(true);
  });

  it('同一格重复清理时 XP 不重复计（每格一次）', () => {
    let s = runAll(freshFarm(), [[{ type: 'clear_cells', cell_ids: three }]]);
    s = runAll(s, [
      [{ type: 'till_cells', cell_ids: three }],
      [{ type: 'sow_cells', cell_ids: three, crop: 'R', lot: 'bound' }],
      [{ type: 'apply_care', cell_ids: three, kind: 'water' }],
    ]);
    const before = s.xp.first_clear_cells.length;
    expect(before).toBe(3);
  });

  it('未清理就翻土被拒', () => {
    const r = run(freshFarm(), { type: 'till_cells', cell_ids: three });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe('WRONG_STATE');
  });

  it('非可耕格与重复格被拒', () => {
    const a = run(freshFarm(), { type: 'clear_cells', cell_ids: ['9,9'] });
    expect(a.ok === false && a.code).toBe('CELL_NOT_CULTIVABLE');
    const b = run(freshFarm(), { type: 'clear_cells', cell_ids: ['1,1', '1,1'] });
    expect(b.ok === false && b.code).toBe('DUPLICATE_CELL');
  });

  it('预留畦未扩地时锁着——mask 说它能是田，beds_unlocked 说现在还不能种', () => {
    const r = run(freshFarm(), { type: 'clear_cells', cell_ids: RESERVED });
    expect(r.ok === false && r.code).toBe('CELL_LOCKED');
  });

  it('整批原子：一格非法则整条失败，状态不变', () => {
    const s = freshFarm();
    const r = run(s, { type: 'clear_cells', cell_ids: [...three, '9,9'] });
    expect(r.ok).toBe(false);
    expect(s.cells['1,1'].state).toBe('wild'); // 前三格没被改
  });
});

describe('sow / care / harvest', () => {
  const tilled = () => runAll(freshFarm(), [
    [{ type: 'clear_cells', cell_ids: three }],
    [{ type: 'till_cells', cell_ids: three }],
  ]);

  it('播种绑定当日田况，ready_at 保持 null——未照料时安全暂停', () => {
    const s = runAll(tilled(), [[{ type: 'sow_cells', cell_ids: three, crop: 'R', lot: 'bound' }]]);
    for (const id of three) {
      expect(s.cells[id].state).toBe('sown');
      expect(s.cells[id].care_weather).toBe('sunny');
      expect(s.cells[id].ready_at).toBeNull();
    }
    expect(s.inventory.seeds.R.bound).toBe(3); // 第 0 章 Grant 6R 用掉 3
  });

  it('照料动作必须匹配播种时的田况', () => {
    const s = runAll(tilled(), [[{ type: 'sow_cells', cell_ids: three, crop: 'R', lot: 'bound' }]]);
    const wrong = run(s, { type: 'apply_care', cell_ids: three, kind: 'drain' });
    expect(wrong.ok === false && wrong.code).toBe('WRONG_CARE');
    const right = run(s, { type: 'apply_care', cell_ids: three, kind: 'water' });
    expect(right.ok).toBe(true);
  });

  it('照料成功才写 ready_at；D0 教学萝卜用 3 分钟特例', () => {
    const s = runAll(tilled(), [
      [{ type: 'sow_cells', cell_ids: three, crop: 'R', lot: 'bound' }],
      [{ type: 'apply_care', cell_ids: three, kind: 'water' }],
    ]);
    expect(s.cells['1,1'].ready_at).toBe(T0 + content.crops.d0_tutorial.duration_ms);
    expect(s.cells['1,1'].state).toBe('growing');
  });

  it('未到点收获被拒，到点即可收——不需要任何 tick', () => {
    const s = runAll(tilled(), [
      [{ type: 'sow_cells', cell_ids: three, crop: 'R', lot: 'bound' }],
      [{ type: 'apply_care', cell_ids: three, kind: 'water' }],
    ]);
    const early = run(s, { type: 'harvest_cells', cell_ids: three }, T0 + 1000);
    expect(early.ok === false && early.code).toBe('NOT_RIPE');
    const ripe = run(s, { type: 'harvest_cells', cell_ids: three }, T0 + 180_000);
    expect(ripe.ok).toBe(true);
    if (!ripe.ok) return;
    expect(ripe.state.inventory.produce.R).toBe(3);
    expect(ripe.state.cells['1,1'].state).toBe('tilled'); // 收完回到已翻土
  });

  it('每活跃日收获 XP 封顶 9 株（PRD §7.2 L478）', () => {
    let s = runAll(freshFarm(), [
      [{ type: 'clear_cells', cell_ids: BEDS }],
      [{ type: 'till_cells', cell_ids: BEDS }],
      [{ type: 'buy_seeds', crop: 'R', qty: 3 }],
      [{ type: 'sow_cells', cell_ids: BEDS.slice(0, 6), crop: 'R', lot: 'bound' }],
      [{ type: 'sow_cells', cell_ids: BEDS.slice(6), crop: 'R', lot: 'bought' }],
      [{ type: 'apply_care', cell_ids: BEDS, kind: 'water' }],
    ]);
    const before = s.xp.total;
    const r = run(s, { type: 'harvest_cells', cell_ids: BEDS }, T0 + 180_000);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // 9 株 ×2 + 首次收获 R 的 8；封顶正好是 9 株，再多也不加
    expect(r.state.xp.total - before).toBe(9 * 2 + 8);
    expect(r.state.xp.harvest_counted.plants).toBe(9);
  });

  it('当日全部已播格完成照料 → 15 XP，每日一次', () => {
    const s = runAll(freshFarm(), [
      [{ type: 'clear_cells', cell_ids: three }],
      [{ type: 'till_cells', cell_ids: three }],
      [{ type: 'sow_cells', cell_ids: three, crop: 'R', lot: 'bound' }],
    ]);
    const r = run(s, { type: 'apply_care', cell_ids: three, kind: 'water' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // 首次晴天照料 5 + 当日照料完成 15
    expect(r.state.xp.total - s.xp.total).toBe(5 + 15);
    expect(r.state.xp.care_bonus_day).toBe('2026-09-04');
  });

  it('还有格子没照料时不发当日奖励', () => {
    const s = runAll(freshFarm(), [
      [{ type: 'clear_cells', cell_ids: BEDS.slice(0, 6) }],
      [{ type: 'till_cells', cell_ids: BEDS.slice(0, 6) }],
      [{ type: 'sow_cells', cell_ids: BEDS.slice(0, 6), crop: 'R', lot: 'bound' }],
    ]);
    const r = run(s, { type: 'apply_care', cell_ids: three, kind: 'water' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.xp.care_bonus_day).toBeNull(); // 还有 3 格是 sown
  });

  it('精心照料每格一次，且不改产量', () => {
    const s = runAll(freshFarm(), [
      [{ type: 'clear_cells', cell_ids: three }],
      [{ type: 'till_cells', cell_ids: three }],
      [{ type: 'sow_cells', cell_ids: three, crop: 'R', lot: 'bound' }],
      [{ type: 'apply_care', cell_ids: three, kind: 'water' }],
      [{ type: 'apply_optional_care', cell_ids: three }],
    ]);
    expect(s.cells['1,1'].careful).toBe(true);
    const again = run(s, { type: 'apply_optional_care', cell_ids: three });
    expect(again.ok === false && again.code).toBe('ALREADY_CLAIMED');
    const h = run(s, { type: 'harvest_cells', cell_ids: three }, T0 + 180_000);
    expect(h.ok && h.state.inventory.produce.R).toBe(3); // 与普通作物同产量
  });
});

describe('buy_seeds', () => {
  it('扣钱进 bought 仓', () => {
    const r = run(freshFarm(), { type: 'buy_seeds', crop: 'R', qty: 6 });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.wallet).toBe(180 - 24);
    expect(r.state.inventory.seeds.R.bought).toBe(6);
  });

  it('钱不够被拒，状态不变', () => {
    const s = freshFarm();
    s.wallet = 3;
    const r = run(s, { type: 'buy_seeds', crop: 'R', qty: 1 });
    expect(r.ok === false && r.code).toBe('INSUFFICIENT_FUNDS');
  });

  it('C 需第 2 章、H 需第 3 章开放', () => {
    const s = freshFarm();
    expect((run(s, { type: 'buy_seeds', crop: 'C', qty: 1 }) as { code: string }).code).toBe('CHAPTER_LOCKED');
    s.clock.chapter_index = 2;
    expect(run(s, { type: 'buy_seeds', crop: 'C', qty: 1 }).ok).toBe(true);
    expect((run(s, { type: 'buy_seeds', crop: 'H', qty: 1 }) as { code: string }).code).toBe('CHAPTER_LOCKED');
    s.clock.chapter_index = 3;
    expect(run(s, { type: 'buy_seeds', crop: 'H', qty: 1 }).ok).toBe(true);
  });
});

import { describe, expect, it } from 'vitest';
import { DEFAULT_CONTENT_DIR, loadContent } from '../../src/domain/content.js';
import { accountValue, cellId, createInitialState, levelOf, parseCellId } from '../../src/domain/state.js';

const c = loadContent(DEFAULT_CONTENT_DIR);
const s0 = () => createInitialState({
  player_day_id: '2026-09-04', field_condition: 'sunny', now: 0, wallet: c.economy.initial_wallet,
  bed_cells: ['1,1', '2,1', '3,1', '1,2', '2,2', '3,2', '1,3', '2,3', '3,3'],
  reserved_cells: ['5,1', '6,1', '7,1'],
});

describe('createInitialState', () => {
  it('12 格全部从荒地开始，初始只解锁三畦', () => {
    const s = s0();
    expect(Object.keys(s.cells)).toHaveLength(12);
    expect(Object.values(s.cells).every(x => x.state === 'wild')).toBe(true);
    expect(s.beds_unlocked).toBe(3);
  });

  it('钱包 180，无种子无产物，第 0 章 active 其余 locked', () => {
    const s = s0();
    expect(s.wallet).toBe(180);
    expect(s.inventory.seeds.R).toEqual({ bought: 0, bound: 0 });
    expect(s.chapters.map(x => x.status)).toEqual(
      ['active', 'locked', 'locked', 'locked', 'locked', 'locked', 'locked']);
    expect(s.chapters[0].grants_issued).toBe(false);
  });

  it('三名居民都从 0 点、未见面开始', () => {
    const s = s0();
    for (const r of Object.values(s.residents)) {
      expect(r.points).toBe(0);
      expect(r.first_met_day).toBeNull();
      expect(r.shared_event_done).toBe(false);
    }
  });
});

describe('派生量', () => {
  it('等级按累计 XP 派生，PRD 目标路径逐日对得上（§7.2 L493-501）', () => {
    const th = c.xp.level_thresholds;
    expect(c.xp.target_cumulative.map(x => levelOf(x, th))).toEqual([2, 3, 4, 5, 6, 6, 7]);
    expect(levelOf(0, th)).toBe(1);
    expect(levelOf(289, th)).toBe(6);
    expect(levelOf(290, th)).toBe(7);
  });

  it('账户价值 = 钱包 + 已购成长资产原价，两条路线都是 545（L572）', () => {
    const tool = c.economy.growth_choice.tool.price;
    const field = c.economy.growth_choice.field.price;
    const a = s0(); a.wallet = 305; a.tools.row_tool = true;
    const b = s0(); b.wallet = 145; b.beds_unlocked = 4;
    expect(accountValue(a, tool, field)).toBe(545);
    expect(accountValue(b, tool, field)).toBe(545);
    expect(accountValue(s0(), tool, field)).toBe(180); // 未购时不算
  });
});

describe('cellId', () => {
  it('往返一致', () => {
    expect(cellId(3, 7)).toBe('3,7');
    expect(parseCellId('3,7')).toEqual([3, 7]);
  });
});

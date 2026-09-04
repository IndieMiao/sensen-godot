import { describe, expect, it } from 'vitest';
import { content, freshFarm, run } from './helpers.js';
import { stageOf } from '../../src/domain/handlers/residents.js';
import { makeCtx } from '../../src/domain/reducer.js';
import { blueprint, SH, T0 } from './helpers.js';
import type { FarmState } from '../../src/domain/state.js';

const ctx = (s: FarmState) => makeCtx(s, T0, SH, content, blueprint);
const atChapter = (n: number): FarmState => {
  const s = freshFarm();
  s.clock.chapter_index = n;
  s.inventory.produce = { R: 5, L: 5, C: 5, H: 5 };
  return s;
};

describe('关系阶段（PRD §8.2）', () => {
  it('赠礼刷满点数也不能独立解锁「熟悉」——必须完成一次共同事件', () => {
    const s = atChapter(3);
    const r = s.residents.bistro_owner;
    r.points = 89;
    r.first_met_day = '2026-09-04';
    expect(stageOf(r, ctx(s))).toBe('acquainted');
    r.shared_event_done = true;
    expect(stageOf(r, ctx(s))).toBe('familiar');
  });

  it('点数够但没见过面时停在初见', () => {
    const s = atChapter(1);
    const r = s.residents.bistro_owner;
    r.points = 20;
    expect(stageOf(r, ctx(s))).toBe('first_sight');
  });
});

describe('对话与赠礼', () => {
  it('每名居民每日首次对话 +2，同日再谈不加分', () => {
    const s = atChapter(1);
    const a = run(s, { type: 'talk_to_resident', resident_id: 'bistro_owner' });
    expect(a.ok && a.state.residents.bistro_owner.points).toBe(2);
    if (!a.ok) return;
    const b = run(a.state, { type: 'talk_to_resident', resident_id: 'bistro_owner' });
    expect(b.ok && b.state.residents.bistro_owner.points).toBe(2);
  });

  it('居民按登场章节开放：修缮师第 5 章才在', () => {
    const s = atChapter(1);
    expect((run(s, { type: 'talk_to_resident', resident_id: 'restorer' }) as { code: string }).code)
      .toBe('NOT_AVAILABLE');
    s.clock.chapter_index = 5;
    expect(run(s, { type: 'talk_to_resident', resident_id: 'restorer' }).ok).toBe(true);
  });

  it('赠礼必须符合该居民的线索，且每人首周两次', () => {
    const s = atChapter(1);
    // 苗圃管理员的线索里只有 R
    expect((run(s, { type: 'give_gift', resident_id: 'nursery_keeper', crop: 'C' }) as { code: string }).code)
      .toBe('NOT_AVAILABLE');
    let cur = s;
    for (let i = 0; i < 2; i++) {
      const r = run(cur, { type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      cur = r.state;
    }
    expect(cur.residents.nursery_keeper.points).toBe(12);
    expect((run(cur, { type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' }) as { code: string }).code)
      .toBe('ALREADY_CLAIMED');
  });
});

describe('请求（PRD §7.6 L588）', () => {
  it('物品不足时整条失败，状态不变', () => {
    const s = atChapter(1);
    s.inventory.produce.L = 2; // 需要 3
    const r = run(s, { type: 'submit_request', request_id: 'd1_bistro_lettuce' });
    expect(r.ok === false && r.code).toBe('INSUFFICIENT_ITEMS');
  });

  it('personal_story 请求给 15 点，同一居民只给一次', () => {
    const s = atChapter(1);
    const r = run(s, { type: 'submit_request', request_id: 'd1_bistro_lettuce' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.residents.bistro_owner.points).toBe(15);
    expect(r.state.wallet).toBe(180 + 45);
    expect(r.state.inventory.produce.L).toBe(2);
  });

  it('教学回购不刷关系（L550）', () => {
    const s = atChapter(0);
    const r = run(s, { type: 'submit_request', request_id: 'd0_tutorial_buyback' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.residents.nursery_keeper.points).toBe(0);
    expect(r.state.wallet).toBe(180 + 30);
  });

  it('同一请求不能重复提交', () => {
    const s = atChapter(1);
    const r = run(s, { type: 'submit_request', request_id: 'd1_bistro_lettuce' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect((run(r.state, { type: 'submit_request', request_id: 'd1_bistro_lettuce' }) as { code: string }).code)
      .toBe('REQUEST_DONE');
  });
});

describe('生活选择槽（Codex 三审 N-I11）', () => {
  it('sold 必须先在摊位真的卖出本章作物——不能凭空写槽', () => {
    const s = atChapter(1);
    expect((run(s, { type: 'resolve_life_choice', chapter: 1, choice: 'sold' }) as { code: string }).code)
      .toBe('REQUEST_MISMATCH');
    const sold = run(s, { type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 1 }] });
    expect(sold.ok).toBe(true);
    if (!sold.ok) return;
    expect(run(sold.state, { type: 'resolve_life_choice', chapter: 1, choice: 'sold' }).ok).toBe(true);
  });

  it('gift 必须先赠出本章作物', () => {
    const s = atChapter(1);
    expect((run(s, { type: 'resolve_life_choice', chapter: 1, choice: 'gift' }) as { code: string }).code)
      .toBe('REQUEST_MISMATCH');
    const gift = run(s, { type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' });
    expect(gift.ok).toBe(true);
    if (!gift.ok) return;
    expect(run(gift.state, { type: 'resolve_life_choice', chapter: 1, choice: 'gift' }).ok).toBe(true);
  });

  it('每章一个槽，占了不能再改', () => {
    const s = atChapter(1);
    const g = run(s, { type: 'give_gift', resident_id: 'nursery_keeper', crop: 'R' });
    if (!g.ok) return;
    const first = run(g.state, { type: 'resolve_life_choice', chapter: 1, choice: 'gift' });
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    expect((run(first.state, { type: 'resolve_life_choice', chapter: 1, choice: 'keep' }) as { code: string }).code)
      .toBe('SLOT_TAKEN');
  });
});

describe('工程篮与成长选择', () => {
  it('预留 → 提交，交齐 2C+4H 即竣工', () => {
    let s = atChapter(3);
    s.inventory.produce = { R: 0, L: 0, C: 5, H: 5 };
    const a = run(s, { type: 'reserve_engineering', items: { C: 2, H: 4 } });
    expect(a.ok).toBe(true);
    if (!a.ok) return;
    const b = run(a.state, { type: 'submit_engineering', items: { C: 2, H: 4 } });
    expect(b.ok).toBe(true);
    if (!b.ok) return;
    expect(b.state.nursery.stage).toBe('built');
    expect(b.state.engineering.submitted).toEqual({ C: 2, H: 4 });
  });

  it('可主动取回预留物（L574）', () => {
    let s = atChapter(3);
    const a = run(s, { type: 'reserve_engineering', items: { C: 2 } });
    if (!a.ok) return;
    const b = run(a.state, { type: 'withdraw_engineering', items: { C: 2 } });
    expect(b.ok && b.state.engineering.reserved.C).toBe(0);
  });

  it('工具与扩地首周永久二选一', () => {
    const s = atChapter(5);
    s.wallet = 1000;
    const a = run(s, { type: 'purchase_growth_choice', choice: 'tool', transaction_id: 't1' });
    expect(a.ok).toBe(true);
    if (!a.ok) return;
    expect((run(a.state, { type: 'purchase_growth_choice', choice: 'field', transaction_id: 't2' }) as { code: string }).code)
      .toBe('LOCKED_CHOICE');
  });

  it('扩地是原子事务：400 + 固定篮 84，第四畦到手即已翻土', () => {
    const s = atChapter(5);
    s.wallet = 484;
    const r = run(s, { type: 'purchase_growth_choice', choice: 'field', transaction_id: 'tx' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.wallet).toBe(0);
    expect(r.state.beds_unlocked).toBe(4);
    expect(r.state.inventory.seeds.R.bought).toBe(3);
    expect(r.state.cells['5,1'].state).toBe('tilled'); // 不用再清理翻土
  });

  it('钱不够 400+84 时整条失败，intent 保留（L561）', () => {
    const s = atChapter(5);
    s.wallet = 483;
    const i = run(s, { type: 'set_growth_intent', choice: 'field' });
    if (!i.ok) return;
    const r = run(i.state, { type: 'purchase_growth_choice', choice: 'field', transaction_id: 'tx' });
    expect(r.ok === false && r.code).toBe('INSUFFICIENT_FUNDS');
    expect(i.state.growth_choice.intent).toBe('field');
    expect(i.state.growth_choice.purchase).toBeNull();
  });
});

describe('访问（PRD §8.4 L655）', () => {
  it('只写教学事实，零金币零 XP 零关系', () => {
    const s = atChapter(4);
    const before = { wallet: s.wallet, xp: s.xp.total };
    const r = run(s, { type: 'record_visit_return', visited_farm_id: 'preset_a' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.state.wallet).toBe(before.wallet);
    expect(r.state.xp.total).toBe(before.xp);
    expect(r.state.chapters[4].step_flags.visit_tutorial_completed).toBe(true);
    expect(Object.values(r.state.residents).every(x => x.points === 0)).toBe(true);
  });
});

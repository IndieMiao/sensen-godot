/** Player names (q(313) ① ②; 后裔's account contract 11-13): the server's rule, its four reasons, the rename wait. */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { checkName, nameList, NAME_MAX, normalizeName, renameAt, RENAME_COOLDOWN_MS, skeleton, type NameList } from '../../src/p0/accounts/name.js';

const LIST: NameList = {
  severe: ['fuck', 'nigger', '傻逼'], words: ['ass', 'cunt'], impersonation: ['gm', 'admin', 'support'],
  impersonation_anywhere: ['gensen', '官方'], allow: ['scunthorpe'],
};
const check = (s: unknown) => checkName(s, LIST);
const ok = (s: string) => expect(check(s)).toEqual({ ok: true, name: normalizeName(s) });
const no = (s: unknown, reason: string, rule: string) => expect(check(s)).toEqual({ ok: false, reason, rule });

describe('player names (q(313))', () => {
  it('is kept normalized: NFKC, one space between words, none at either end', () => {
    expect(normalizeName('  Ｍｅｉ　  Lin ')).toBe('Mei Lin');
    expect(normalizeName('Ann Lee')).toBe('Ann Lee');
    ok('Mei Lin');
    expect(check('  Mei   Lin ')).toEqual({ ok: true, name: 'Mei Lin' });
  });

  it('is 2–16 graphemes: a Chinese character or a letter with its tone mark counts one', () => {
    no('', 'empty', 'empty');
    no('   ', 'empty', 'empty');
    no(null, 'empty', 'empty');
    no('A', 'length', 'too_short');
    ok('Li');
    ok('小明');
    ok('Nguyễn Thị Ánh');                                 // tone marks: one grapheme each
    ok('Nguŷ̃n');                           // the same with combining marks
    ok('x'.repeat(NAME_MAX));
    no('x'.repeat(NAME_MAX + 1), 'length', 'too_long');
    ok('张'.repeat(16));
    no('张'.repeat(17), 'length', 'too_long');
  });

  it("takes the drawn scripts, digits, spaces and -_.' only", () => {
    for (const s of ['Ana-Maria', "O'Neil", 'mei_lin', 'J.R.', 'Player 42', 'Ζωή', 'Анна', 'さくら', 'カタカナー', '김민지', '佐々木'])
      ok(s);
    for (const s of ['Mei😀', 'a@b', '#tag', 'http://x', 'a:b', 'a/b', 'محمد', 'שלום', 'สมชาย', 'नमस्ते', 'Ann\tLee', 'A​B', 'Ab‮'])
      no(s, 'chars', 'bad_char');
    no('Zá̂̃̄lgo', 'chars', 'bad_char');   // a stack of marks, not a letter's accents
  });

  it("refuses what draws as nothing, and marks of scripts the fonts don't draw (哪吒 11-13)", () => {
    // variation selectors, the grapheme joiner, Mongolian and Khmer ones (marks); the Hangul fillers (letters)
    for (const c of ['\uFE0F', '\uFE00', '\u{E0100}', '\u034F', '\u180B', '\u17B4', '\u3164', '\u1160', '\u115F', '\uFFA0'])
      no(`Tom${c}`, 'chars', 'bad_char');
    no('Tom\u0E31', 'chars', 'bad_char');   // a Thai mark on a Latin letter
    no('Tom\u093F', 'chars', 'bad_char');   // a Devanagari one
    for (const s of ['Rene\u0301', 'Nguyễn Thị', 'Nguye\u0302\u0303n', 'ガギ', 'ミア\u309A', '한글'])
      ok(s);   // accents written apart, Vietnamese's two, a kana voicing mark with no composed form
  });

  it('does not mix Latin with Cyrillic or Greek, but Latin goes with CJK; a mix reads blocked (spec v1.1 §1.5)', () => {
    no('Pаul', 'blocked', 'mixed_script');   // Cyrillic а
    no('Pαul', 'blocked', 'mixed_script');   // Greek α
    no('Farmer Јoe', 'blocked', 'mixed_script');   // Cyrillic Ј, every character fine alone
    ok('小明Tom');
    ok('Ana 김');
  });

  it('meets a severe word anywhere, repeated letters and look-alike digits too, not a near word', () => {
    no('fuck', 'blocked', 'blocked');
    no('BigFuckTom', 'blocked', 'blocked');
    no('fuuuck', 'blocked', 'blocked');
    no('f.u.c.k', 'blocked', 'blocked');
    no('Fück', 'blocked', 'blocked');
    no('n1gger', 'blocked', 'blocked');
    no('我是傻逼', 'blocked', 'blocked');
    ok('Niger');                            // a letter dropped is another word
  });

  it('takes an allowed word out before the severe ones are looked for', () => {
    const severe = { ...LIST, severe: [...LIST.severe, 'cunt'] };
    expect(checkName('Scunthorpe', severe)).toEqual({ ok: true, name: 'Scunthorpe' });
    expect(checkName('Scunthorpe', { ...severe, allow: [] })).toEqual({ ok: false, reason: 'blocked', rule: 'blocked' });
    expect(checkName('ScunthorpeCunt', severe)).toEqual({ ok: false, reason: 'blocked', rule: 'blocked' });
  });

  it('meets a plain word only as the whole name or one of its words', () => {
    no('Ass', 'blocked', 'blocked');
    no('Big Ass', 'blocked', 'blocked');
    no('BigAss', 'blocked', 'blocked');      // a capital starts a word
    ok('Cassandra');
    ok('Bass Player');
    no('cunt', 'blocked', 'blocked');
  });

  it('refuses staff-looking names, in Cyrillic and with digits too; the brand anywhere', () => {
    no('Admin', 'blocked', 'impersonation');
    no('GM Tom', 'blocked', 'impersonation');
    no('AdminBob', 'blocked', 'impersonation');
    no('Admin1', 'blocked', 'impersonation');
    no('4dm1n', 'blocked', 'impersonation');
    no('аԁміп', 'blocked', 'impersonation');   // all Cyrillic, read as Latin
    no('GensenTeam', 'blocked', 'impersonation');
    no('gensen_official', 'blocked', 'impersonation');
    no('官方小助手', 'blocked', 'impersonation');
    ok('Ogma');                             // gm inside a word
    ok('Supporter');                        // not the word itself
    ok('Gemma');
  });

  it("takes a whole word's English plural, not a longer word (不知火舞's probe 11-12)", () => {
    no('Asses', 'blocked', 'blocked');
    no('Cunts', 'blocked', 'blocked');
    no('Admins', 'blocked', 'impersonation');
    for (const s of ['Bass', 'Glass', 'Pass', 'Assess', 'Classes']) ok(s);
  });

  it("reads `1` as `i` and as `l`", () => {
    expect(skeleton('4dm1n')).toBe('admin');
    expect(skeleton('a1l', 'l')).toBe('all');
    const list: NameList = { ...LIST, words: ['lol'] };
    expect(checkName('1o1', list)).toEqual({ ok: false, reason: 'blocked', rule: 'blocked' });
  });

  it("the shipped list loads and holds the q(313) staff words", () => {
    const l = nameList();
    for (const w of ['gensen', 'gm', 'admin', 'moderator', 'staff', 'official', 'support', 'system'])
      expect([...l.impersonation, ...l.impersonation_anywhere]).toContain(w);
    expect(checkName('Moderator').ok).toBe(false);
    expect(checkName('Traveller 8c3f')).toEqual({ ok: true, name: 'Traveller 8c3f' });   // the default name
    for (const s of ['Bitches', 'Whores', 'GMs', 'f4gs']) expect(checkName(s).ok).toBe(false);
    // names that hold a listed word's letters (李白 and 不知火舞's probe 11-12)
    for (const s of ['Farm Owner', 'Smooth Operator', 'Scunthorpe', 'Penistone', 'Shiitake', 'Matsushita', 'Pornthip',
      'Assess', 'Cassandra', 'Dickens', 'Hancock', 'Cockburn', 'Sussex', 'Essex', 'Therapist', 'Grape', 'Peacock', 'Niger'])
      expect(checkName(s)).toEqual({ ok: true, name: s });
  });

  it("the game's own names and place words all pass the shipped list", () => {
    const w = JSON.parse(readFileSync(new URL('../../../assets/p0/content/world_gen.json', import.meta.url), 'utf8')).world;
    const pools = [w.keeper_names, w.tea_words, w.wild.words, w.ponds.words] as Record<string, string[]>[];
    const all = pools.flatMap(p => Object.values(p).flatMap(v => (Array.isArray(v) ? v : [])));
    expect(all.length).toBeGreaterThan(300);
    expect(all.filter(n => !checkName(n).ok)).toEqual([]);
  });
});

describe('the rename wait (q(313) ②)', () => {
  const T = Date.parse('2026-11-13T00:00:00Z');
  it('is 7 days from the last name; a first launch Skip waits for nothing', () => {
    expect(renameAt(undefined)).toBe(0);
    expect(renameAt({ name: 'Traveller 8c3f', name_set_at: null })).toBe(0);
    expect(renameAt({ name: 'Mei', name_set_at: T })).toBe(T + RENAME_COOLDOWN_MS);
  });
  it("a moderator's lock wins when it ends later", () => {
    expect(renameAt({ name_set_at: T, name_locked_until: T + 10 * 86_400_000 })).toBe(T + 10 * 86_400_000);
    expect(renameAt({ name_set_at: T, name_locked_until: T + 86_400_000 })).toBe(T + RENAME_COOLDOWN_MS);
    expect(renameAt({ name_set_at: null, name_locked_until: T + RENAME_COOLDOWN_MS })).toBe(T + RENAME_COOLDOWN_MS);
  });
});

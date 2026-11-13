/**
 * Player names (q(313) ① ②, the user's bot 715; tech-plan-yase §2.1; 后裔's account contract 11-13): the server's word on
 * a name — name/check before NAME's Save, session/guest with its name, account/name for a rename. The client checks
 * only the length and the characters first; this is the rule.
 *
 * A name, once normalized (NFKC; runs of spaces made one, none at either end), is 2–16 graphemes — a Chinese character
 * or a letter with its tone mark counts 1 — of the scripts the build's fonts draw (Latin with its extensions, Greek,
 * Cyrillic, Han, kana, Hangul; Arabic, Hebrew, Thai, Devanagari … draw as boxes today, so not yet), the digits 0–9,
 * single spaces and `-` `_` `.` `'`: no emoji, no `@` `#` `/` `:` (no addresses, no social handles), nothing invisible.
 * Latin is not mixed with Cyrillic or Greek in one name (no `а` for `a`). Then its skeleton — case folded, accents
 * dropped, the Cyrillic and Greek look-alikes of Latin letters made Latin (UTS #39's idea, for those three scripts only:
 * mixing them is refused already), `0 1 3 4 5 @` read as `o i e a s a` — is held to the word list and the impersonation
 * words (server/data/name_blocklist.json; a new word needs a deploy, not a client release). Names are not unique.
 *
 * To the client a refusal is `{ok: false, code: "name_rejected", reason}`, reason one of empty / length / chars /
 * blocked (后裔 and 哪吒's contract): never which word it met. The finer rule stays on the server, for its log and tests.
 * Mixed scripts read `blocked`, not `chars` (account spec v1.1 §1.5, 不知火舞 11-13): each character is fine on its
 * own, so `That character can't be used` would send the player looking for one; and a mix is mostly a disguise.
 */
import { readFileSync } from 'node:fs';

export const NAME_MIN = 2;
export const NAME_MAX = 16;
/** q(313) ②: a name can be changed once in 7 days; a moderator's reset locks it for 7 (q(315)). */
export const RENAME_COOLDOWN_MS = 7 * 86_400_000;

export type NameReason = 'empty' | 'length' | 'chars' | 'blocked';
export type NameRule = 'empty' | 'too_short' | 'too_long' | 'bad_char' | 'mixed_script' | 'blocked' | 'impersonation';
export type NameCheck = { ok: true; name: string } | { ok: false; reason: NameReason; rule: NameRule };

const REASON: Record<NameRule, NameReason> = {
  empty: 'empty', too_short: 'length', too_long: 'length', bad_char: 'chars', mixed_script: 'blocked',
  blocked: 'blocked', impersonation: 'blocked',
};

/**
 * The word list (its words written plainly: the skeleton below reads the rest). `severe`: met anywhere in the name,
 * inside another word too (q(313) ①); `words`: the whole name or one of its words (`ass` refuses `Ass` and `Big Ass`,
 * not `Cassandra`); `impersonation`: the same, for the names a player could pass as staff by (`Admin`, `GM`);
 * `impersonation_anywhere`: the brand, anywhere (`GensenTeam`); `allow`: names or words that only look like a severe
 * one (`Scunthorpe`), taken out before the severe words are looked for. Each letter may be repeated (`fuuuck`), never
 * dropped (`niger` is not `nigger`); a whole word may take a plural's `s` / `es`. Words in Chinese, Japanese or Korean are met anywhere: those names have no spaces
 * between their words; traditional and simplified are separate entries.
 */
export interface NameList {
  severe: string[]; words: string[]; impersonation: string[]; impersonation_anywhere: string[]; allow: string[];
}

let cached: NameList | null = null;
/** server/data/name_blocklist.json, read once. */
export function nameList(): NameList {
  if (!cached) {
    const raw = JSON.parse(readFileSync(new URL('../../../data/name_blocklist.json', import.meta.url), 'utf8')) as Partial<NameList>;
    cached = { severe: raw.severe ?? [], words: raw.words ?? [], impersonation: raw.impersonation ?? [],
      impersonation_anywhere: raw.impersonation_anywhere ?? [], allow: raw.allow ?? [] };
  }
  return cached;
}

/** NFKC, then each run of spaces made one and none left at either end. Other spacing (tabs, line breaks) stays, to be
 *  refused as a character: the full-width and no-break spaces are U+0020 after NFKC. */
export function normalizeName(raw: string): string {
  return raw.normalize('NFKC').replace(/ {2,}/g, ' ').trim();
}

const segmenter = new Intl.Segmenter('und', { granularity: 'grapheme' });
export const graphemes = (s: string): string[] => [...segmenter.segment(s)].map(g => g.segment);

const LETTER = /^[\p{Script_Extensions=Latin}\p{Script_Extensions=Greek}\p{Script_Extensions=Cyrillic}\p{Script_Extensions=Han}\p{Script_Extensions=Hiragana}\p{Script_Extensions=Katakana}\p{Script_Extensions=Hangul}]$/u;
const MARK = /^\p{M}$/u;
const OTHER = /^[0-9 \-_.']$/;
const MARKS_MAX = 2;   // a letter's own accents (Vietnamese needs two), never a stack of them

/** Every grapheme starts with a letter of the drawn scripts, a digit, a space or `-_.'`, and carries at most two marks. */
function charsOk(name: string): boolean {
  for (const g of graphemes(name)) {
    const cps = [...g];
    const base = cps[0];
    if (!(/^\p{L}$/u.test(base) && LETTER.test(base)) && !OTHER.test(base)) return false;
    const marks = cps.slice(1);
    if (marks.length > MARKS_MAX || !marks.every(m => MARK.test(m))) return false;
  }
  return true;
}

const mixesScripts = (name: string): boolean =>
  /\p{Script=Latin}/u.test(name) && /[\p{Script=Cyrillic}\p{Script=Greek}]/u.test(name);

/** Cyrillic and Greek letters that read as Latin ones (lower case, UTS #39 confusables for those two scripts), and the
 *  Latin ones without a decomposition that read as plain letters. */
const FOLD: Record<string, string> = {
  а: 'a', в: 'b', е: 'e', ё: 'e', з: 'e', і: 'i', ї: 'i', ј: 'j', к: 'k', м: 'm', н: 'h', о: 'o', п: 'n', р: 'p', с: 'c',
  т: 't', у: 'y', х: 'x', ѕ: 's', ԁ: 'd', ԛ: 'q', ԝ: 'w', ӏ: 'l', ь: 'b', г: 'r',
  α: 'a', β: 'b', γ: 'y', ε: 'e', η: 'n', ι: 'i', κ: 'k', μ: 'u', ν: 'v', ο: 'o', ρ: 'p', σ: 'o', ς: 'c', τ: 't', υ: 'u',
  χ: 'x', ω: 'w', ϲ: 'c', ϳ: 'j',
  ı: 'i', ł: 'l', ø: 'o', đ: 'd', ħ: 'h', ŧ: 't', ß: 'ss', æ: 'ae', œ: 'oe',
};
/** q(313) ①: the digits and sign read as letters; `1` as `i` and, read again, as `l`. */
const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '@': 'a', $: 's' };

/** The letters a name reads as: case folded, accents dropped, look-alikes made Latin, digits read as letters. */
export function skeleton(s: string, one = 'i'): string {
  const bare = s.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
  return [...bare].map(ch => FOLD[ch] ?? ch).map(ch => (ch === '1' ? one : LEET[ch] ?? ch)).join('');
}

const SEP = /[ \-_.']+/;
/** The name's words: split at spaces and `-_.'`, and where a lower-case letter meets a capital (`AdminBob`). */
function words(name: string): string[] {
  return name.split(SEP).flatMap(w => w.split(/(?<=\p{Ll})(?=\p{Lu})/u)).filter(Boolean);
}

const CJK = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** An entry as a pattern on skeletons: each of its letters once or more (`fuuuck`), its spaces and `-_.'` gone; a whole
 *  word may end in an English plural's `s` / `es` (`Cunts`, `Bitches`, `Admins`; 不知火舞's probe 11-12, 李白). */
const pattern = (entry: string, anchored: boolean): RegExp | null => {
  const k = skeleton(entry.split(SEP).join(''));
  if (k === '') return null;
  const body = graphemes(k).map(g => `(?:${escape(g)})+`).join('');
  return new RegExp(anchored ? `^${body}(?:e?s)?$` : body, 'u');
};

/** Which list rule a name meets, or null. The name is read twice, its `1` as `i` and as `l`. */
function listRule(name: string, list: NameList): 'blocked' | 'impersonation' | null {
  for (const one of ['i', 'l']) {
    let whole = skeleton(name.split(SEP).join(''), one);
    const parts = [whole];
    for (const w of words(name)) parts.push(skeleton(w, one), skeleton(w.replace(/[0-9]+$/, ''), one));   // `Admin1`
    for (const a of list.allow) {
      const p = pattern(a, false);
      if (p) whole = whole.replace(new RegExp(p.source, 'gu'), ' ');
    }
    const meets = (entries: string[], anywhere: boolean) => entries.some(e => {
      if (anywhere || CJK.test(e)) return pattern(e, false)?.test(whole) ?? false;
      const p = pattern(e, true);
      return p !== null && parts.some(part => p.test(part));
    });
    if (meets(list.severe, true) || meets(list.words, false)) return 'blocked';
    if (meets(list.impersonation_anywhere, true) || meets(list.impersonation, false)) return 'impersonation';
  }
  return null;
}

/** The server's verdict on a name the player typed: the name as it will be kept, or why not. */
export function checkName(raw: unknown, list: NameList = nameList()): NameCheck {
  const no = (rule: NameRule): NameCheck => ({ ok: false, reason: REASON[rule], rule });
  if (typeof raw !== 'string') return no('empty');
  const name = normalizeName(raw);
  if (name === '') return no('empty');
  const n = graphemes(name).length;
  if (n < NAME_MIN) return no('too_short');
  if (n > NAME_MAX) return no('too_long');
  if (!charsOk(name)) return no('bad_char');
  if (mixesScripts(name)) return no('mixed_script');
  const rule = listRule(name, list);
  return rule ? no(rule) : { ok: true, name };
}

/** The save's name fields (P0State.profile, 后裔's PR-A). */
export interface NameProfile { name?: string; name_set_at?: number | null; name_locked_until?: number | null }

/**
 * When the name can next be changed (view.account.rename_at; 0 = now): 7 days after it was last set, or the end of a
 * moderator's lock, whichever is later. A first launch's Skip leaves name_set_at empty, so the first rename does not
 * wait (奕星's review, q(313) ②).
 */
export function renameAt(profile: NameProfile | undefined): number {
  const set = profile?.name_set_at ?? 0;
  return Math.max(set ? set + RENAME_COOLDOWN_MS : 0, profile?.name_locked_until ?? 0);
}

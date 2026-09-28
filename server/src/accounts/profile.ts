/**
 * 账号资料（2026-09-28）：昵称、性别、生日。
 *
 * 性别选项按北美市场常见做法：Woman / Man / Non-binary / 自行描述 / 不愿透露，全部选填。
 * 生日选填；填了就必须满 13 岁（COPPA：不收集 13 岁以下儿童的个人信息），不足 13 岁整条拒绝、
 * 不落库。昵称是展示名，不唯一、不作登录凭据；目前只在本人账号页显示，公开展示另行决定。
 */
export const GENDERS = ['woman', 'man', 'nonbinary', 'self_describe', 'prefer_not_to_say'] as const;
export type Gender = (typeof GENDERS)[number];
export const NAME_MIN = 2;
export const NAME_MAX = 24;
export const GENDER_CUSTOM_MAX = 32;
export const MIN_AGE = 13;
export const MAX_AGE = 120;

export interface ProfileInput { display_name: string | null; gender: Gender | null; gender_custom: string | null; birth_date: string | null }
export type ProfileResult = { ok: true; profile: ProfileInput } | { ok: false; code: string };

// Control, format and zero-width characters make names that render blank or spoof others.
const INVISIBLE = /[\p{Cc}\p{Cf}\u200B-\u200F\u2028-\u202F\u2060-\u206F]/u;

export function normalizeName(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const name = v.normalize('NFKC').replace(/\s+/gu, ' ').trim();
  const length = [...name].length;
  if (length < NAME_MIN || length > NAME_MAX || INVISIBLE.test(name) || name.includes('@')) return null;
  return name;
}

/** 周岁：生日当天满岁。 */
export function ageOn(birth: string, now: number): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(birth);
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const date = new Date(Date.UTC(y, mo - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== mo - 1 || date.getUTCDate() !== d) return null;
  const today = new Date(now);
  let age = today.getUTCFullYear() - y;
  if (today.getUTCMonth() + 1 < mo || (today.getUTCMonth() + 1 === mo && today.getUTCDate() < d)) age--;
  return age;
}

/** 校验一次完整的资料提交。缺省字段视为清空（选填项），昵称必须给。 */
export function parseProfile(body: unknown, now: number): ProfileResult {
  const b = (body ?? {}) as Record<string, unknown>;
  const display_name = normalizeName(b.display_name);
  if (!display_name) return { ok: false, code: 'INVALID_NAME' };
  let gender: Gender | null = null;
  if (b.gender !== undefined && b.gender !== null && b.gender !== '') {
    if (!(GENDERS as readonly string[]).includes(String(b.gender))) return { ok: false, code: 'INVALID_GENDER' };
    gender = b.gender as Gender;
  }
  let gender_custom: string | null = null;
  if (gender === 'self_describe') {
    const custom = typeof b.gender_custom === 'string' ? b.gender_custom.normalize('NFKC').trim() : '';
    if (!custom || [...custom].length > GENDER_CUSTOM_MAX || INVISIBLE.test(custom)) return { ok: false, code: 'INVALID_GENDER' };
    gender_custom = custom;
  }
  let birth_date: string | null = null;
  if (b.birth_date !== undefined && b.birth_date !== null && b.birth_date !== '') {
    const age = typeof b.birth_date === 'string' ? ageOn(b.birth_date, now) : null;
    if (age === null || age > MAX_AGE || age < 0) return { ok: false, code: 'INVALID_BIRTH_DATE' };
    if (age < MIN_AGE) return { ok: false, code: 'UNDER_AGE' };
    birth_date = b.birth_date as string;
  }
  return { ok: true, profile: { display_name, gender, gender_custom, birth_date } };
}

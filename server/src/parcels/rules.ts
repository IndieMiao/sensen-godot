/**
 * 动态农场（C-31）的可调数值：社区与数据集、首次进入自家地块的赠品、房屋占地与蓝图、作物成熟时间。
 * 默认值按所有者拍板 Q-39（C-34#14）与 Q-40（C-33#14）。
 * 来源是 assets/farm/data/dynamic_farm.json；它不在 content_version 的指纹里，改它不影响旧农场存档。
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';

export interface CropRule { seed: string; grow_seconds: number; yield: number }
export interface ParcelRules {
  version: 1;
  /** 地块数据集归哪个社区：社区编号由服务端按数据集推出，客户端不能自报。 */
  communities: { id: string; datasets: string[] }[];
  /** 首次进入自己的地块发一次（锄头、种子、首栋住宅蓝图）；重开、重试不重发。 */
  welcome_gift: Record<string, number>;
  till_tool: string;
  /** 放首栋住宅消耗一张 blueprint，放下即建成。 */
  house: { model: string; blueprint: string; width: number; depth: number };
  crops: Record<string, CropRule>;
}

export const RULES_FILE = 'dynamic_farm.json';
const ID_RE = /^[a-z0-9_-]{1,64}$/;
const isId = (v: unknown): v is string => typeof v === 'string' && ID_RE.test(v);
const count = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;

/** 不合法就抛错：启动时发现，而不是在第一次认领时。 */
export function parseParcelRules(raw: unknown): ParcelRules {
  const r = raw as ParcelRules;
  const fail = (what: string): never => { throw new Error(`${RULES_FILE}: ${what}`); };
  if (!r || r.version !== 1) fail('version 必须为 1');
  if (!Array.isArray(r.communities) || !r.communities.length) fail('communities 不能为空');
  const datasets = new Set<string>();
  for (const c of r.communities) {
    if (!isId(c?.id) || !Array.isArray(c.datasets) || !c.datasets.length) fail('社区格式不对');
    for (const d of c.datasets) {
      if (!isId(d) || datasets.has(d)) fail(`数据集 ${d} 格式不对或重复`);
      datasets.add(d);
    }
  }
  if (!r.welcome_gift || typeof r.welcome_gift !== 'object') fail('welcome_gift 缺失');
  for (const [id, n] of Object.entries(r.welcome_gift)) if (!isId(id) || !count(n, 1, 999)) fail(`welcome_gift.${id} 不对`);
  if (!isId(r.till_tool)) fail('till_tool 缺失');
  if (!r.house || !isId(r.house.model) || !isId(r.house.blueprint)
    || !count(r.house.width, 1, 16) || !count(r.house.depth, 1, 16)) fail('house 不对');
  if (!r.crops || !Object.keys(r.crops).length) fail('crops 不能为空');
  for (const [id, c] of Object.entries(r.crops))
    if (!isId(id) || !isId(c?.seed) || !count(c.grow_seconds, 1, 30 * 24 * 3600) || !count(c.yield, 1, 99)) fail(`crops.${id} 不对`);
  return r;
}

export function loadParcelRules(contentDir: string): ParcelRules {
  return parseParcelRules(JSON.parse(readFileSync(path.join(contentDir, RULES_FILE), 'utf8')));
}

/** 数据集所属社区；未登记的数据集返回 null。 */
export function communityOf(rules: ParcelRules, dataset: string): string | null {
  return rules.communities.find(c => c.datasets.includes(dataset))?.id ?? null;
}

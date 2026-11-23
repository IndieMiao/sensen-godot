/**
 * 动态农场（C-31）的可调数值：社区与数据集、开局背包、房屋占地、作物成熟时间。
 * 来源是 assets/farm/data/dynamic_farm.json；它不在 content_version 的指纹里，改它不影响旧农场存档。
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';

export interface CropRule { seed: string; grow_seconds: number; yield: number }
export interface ParcelRules {
  version: 1;
  /** 地块数据集归哪个社区：社区编号由服务端按数据集推出，客户端不能自报。 */
  communities: { id: string; datasets: string[] }[];
  starter_bag: Record<string, number>;
  till_tool: string;
  house: { model: string; width: number; depth: number };
  crops: Record<string, CropRule>;
}

export const RULES_FILE = 'dynamic_farm.json';
const ID_RE = /^[a-z0-9_-]{1,64}$/;
const count = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;

/** 不合法就抛错：启动时发现，而不是在第一次认领时。 */
export function parseParcelRules(raw: unknown): ParcelRules {
  const r = raw as ParcelRules;
  const fail = (what: string): never => { throw new Error(`${RULES_FILE}: ${what}`); };
  if (!r || r.version !== 1) fail('version 必须为 1');
  if (!Array.isArray(r.communities) || !r.communities.length) fail('communities 不能为空');
  const datasets = new Set<string>();
  for (const c of r.communities) {
    if (!ID_RE.test(String(c?.id)) || !Array.isArray(c.datasets) || !c.datasets.length) fail('社区格式不对');
    for (const d of c.datasets) {
      if (!ID_RE.test(String(d)) || datasets.has(d)) fail(`数据集 ${d} 格式不对或重复`);
      datasets.add(d);
    }
  }
  if (!r.starter_bag || typeof r.starter_bag !== 'object') fail('starter_bag 缺失');
  for (const [id, n] of Object.entries(r.starter_bag)) if (!ID_RE.test(id) || !count(n, 1, 999)) fail(`starter_bag.${id} 不对`);
  if (!ID_RE.test(String(r.till_tool))) fail('till_tool 缺失');
  if (!r.house || !ID_RE.test(String(r.house.model)) || !count(r.house.width, 1, 16) || !count(r.house.depth, 1, 16)) fail('house 不对');
  if (!r.crops || !Object.keys(r.crops).length) fail('crops 不能为空');
  for (const [id, c] of Object.entries(r.crops))
    if (!ID_RE.test(id) || !ID_RE.test(String(c?.seed)) || !count(c.grow_seconds, 1, 30 * 24 * 3600) || !count(c.yield, 1, 99)) fail(`crops.${id} 不对`);
  return r;
}

export function loadParcelRules(contentDir: string): ParcelRules {
  return parseParcelRules(JSON.parse(readFileSync(path.join(contentDir, RULES_FILE), 'utf8')));
}

/** 数据集所属社区；未登记的数据集返回 null。 */
export function communityOf(rules: ParcelRules, dataset: string): string | null {
  return rules.communities.find(c => c.datasets.includes(dataset))?.id ?? null;
}

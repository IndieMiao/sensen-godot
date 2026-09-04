/**
 * 幂等身份的哈希。覆盖 `{type, payload, base_version}` 三者——只比 payload 时，同 key
 * 同 payload 的另一条命令会被当成重试（Codex 二审 Important 2）。
 *
 * JSON 键序不定，所以先做 RFC 8785 风格的规范化（递归按键排序）再序列化。
 */
import { createHash } from 'node:crypto';
import type { CommandEnvelope } from '../domain/commands.js';

export function canonicalJson(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v) ?? 'null';
  if (Array.isArray(v)) return `[${v.map(canonicalJson).join(',')}]`;
  const keys = Object.keys(v as Record<string, unknown>).sort();
  return `{${keys.map(k => `${JSON.stringify(k)}:${canonicalJson((v as Record<string, unknown>)[k])}`).join(',')}}`;
}

export const payloadHash = (env: CommandEnvelope): string =>
  createHash('sha256')
    .update(canonicalJson({ type: env.type, payload: env.payload, base_version: env.base_version }), 'utf8')
    .digest('hex');

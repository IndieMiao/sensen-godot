/**
 * 危险操作：删农场。三重条件同时成立才执行（Codex 三审 N-I7：`CONFIRM=yes` 不是环境隔离，
 * 「测试农场」的筛选依据也必须写死）。
 *
 *   ① DSN 主机在 192.168.124.0/24 或 localhost —— 生产 DSN 直接拒绝
 *   ② 环境变量 ALLOW_RESET=1
 *   ③ 只删 qa=true，或三个版本字段任一与当前进程不符的农场
 *
 * 执行前打印数据库指纹与将删数量，要求二次确认。
 */
import pg from 'pg';
import { DOMAIN_VERSION, STATE_SCHEMA_VERSION } from '../domain/version.js';

export class ResetRefused extends Error {}

const LAN = /^192\.168\.124\.\d+$/;
export function assertResettable(dsn: string): void {
  const host = new URL(dsn).hostname;
  if (!(LAN.test(host) || host === 'localhost' || host === '127.0.0.1'))
    throw new ResetRefused(`拒绝在非开发主机上 reset: ${host}`);
  if (process.env.ALLOW_RESET !== '1')
    throw new ResetRefused('需要 ALLOW_RESET=1');
}

export interface ResetPlan { fingerprint: string; total: number; doomed: number }

export async function planReset(pool: pg.Pool, contentVersion: string): Promise<ResetPlan> {
  const fp = await pool.query(
    'SELECT current_database() AS db, inet_server_addr()::text AS addr, (SELECT count(*) FROM farms) AS n');
  const doomed = await pool.query(
    `SELECT count(*) AS n FROM farms
       WHERE qa = true OR content_version <> $1 OR domain_version <> $2 OR state_schema_version <> $3`,
    [contentVersion, DOMAIN_VERSION, STATE_SCHEMA_VERSION]);
  return {
    fingerprint: `${fp.rows[0].db}@${fp.rows[0].addr ?? 'local'}`,
    total: Number(fp.rows[0].n),
    doomed: Number(doomed.rows[0].n),
  };
}

export async function performReset(pool: pg.Pool, dsn: string, contentVersion: string): Promise<number> {
  assertResettable(dsn);
  const r = await pool.query(
    `DELETE FROM farms
       WHERE qa = true OR content_version <> $1 OR domain_version <> $2 OR state_schema_version <> $3`,
    [contentVersion, DOMAIN_VERSION, STATE_SCHEMA_VERSION]);
  return r.rowCount ?? 0;
}

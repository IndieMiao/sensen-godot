/** 迁移入口：容器启动时先跑它再 listen。schema.sql 全部是 IF NOT EXISTS，可重复执行。 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import pg from 'pg';

export const SCHEMA_FILE = path.join(path.dirname(new URL(import.meta.url).pathname), 'schema.sql');

export async function migrate(pool: pg.Pool): Promise<void> {
  await pool.query(readFileSync(SCHEMA_FILE, 'utf8'));
}

/** 测试用：清空所有表但保留结构。只允许在非生产 DSN 上调用。 */
export async function truncateAll(pool: pg.Pool): Promise<void> {
  // Fastify's post-response token lookup can still be completing during test
  // teardown. A deadlocked TRUNCATE rolls back completely and is safe to retry.
  for (let attempt = 0; ; attempt++) {
    try {
      await pool.query('TRUNCATE tokens, players, farms, farm_creations, commands, farm_snapshots CASCADE');
      return;
    } catch (error) {
      if ((error as { code?: string }).code !== '40P01' || attempt >= 2) throw error;
    }
  }
}

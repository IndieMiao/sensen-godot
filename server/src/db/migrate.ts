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
  await pool.query('TRUNCATE players, tokens, farms, farm_creations, commands, farm_snapshots, users, user_identities, account_deletions, profiles, follows, posts, post_likes, post_comments, reports, blocks, account_bans, conversations, conversation_members, dm_pairs, messages, user_events, user_event_seq, user_locations, device_tokens, voice_rooms, voice_room_members CASCADE');
}

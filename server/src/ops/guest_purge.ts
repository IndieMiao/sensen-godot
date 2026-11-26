/**
 * 删除游客号（C-146，所有者在 Q-265 选了 delete）：游客号和它们的地块、进度先完整备份到文件，核对条数，才删除；
 * 有只看不删的预演，备份能恢复。入口 tools/guest_purge.ts，正式服由 server/deploy/dynamicfarm/ops.sh guests 调用。
 *
 * 游客号 = players 里 user_id 为空、install_key_hmac 是 64 位十六进制（安装密钥的 HMAC）的行。邮箱账号（含邀请账号）
 * 的玩家 user_id 非空；预置农场的系统玩家 install_key_hmac 是 `preset:…`，都不会被选中。
 * 一并备份和删除的是会随这些玩家级联删除的全部行：tokens、farms（及 farm_creations、commands、farm_snapshots）、
 * online_players、parcel_claims（地块和地块存档）、parcel_reclaims。库里出现别的表引用这些表时工具拒绝运行，
 * 免得新表的数据没备份就被级联删掉。online_rooms / online_parties 的状态里不存游客（游客进不了联机）。
 *
 * 备份文件（UTF-8 文本）：第一行是 JSON 头（格式、库名、规则、各表条数、正文的 SHA-256），之后每张表一行
 * `表名<TAB>行的 JSON 数组`，数组就是 PostgreSQL `jsonb_agg(to_jsonb(行))` 的原样输出，按主键排序。
 * 删除时在锁住这些表的同一个事务里重新取一遍游客数据，必须和备份正文逐字节相同才删：备份之后有任何变化
 * （新登录、新存档）都不删，要重新备份。删完核对每张表删掉的条数等于备份条数、别的行一条没少，才提交。
 * 恢复把备份原样插回，再取一遍核对和备份逐字节相同，才提交。
 */
import { createHash } from 'node:crypto';
import { closeSync, existsSync, openSync, readFileSync, realpathSync, unlinkSync, writeSync } from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import type pg from 'pg';
import { insideGitWorkTree } from '../accounts/invite_cli.js';

export const BACKUP_FORMAT = 'sensen-guest-backup/1';
/** 游客号的判定，写进备份头；改它要同时改格式版本。 */
export const GUEST_RULE = "user_id IS NULL AND install_key_hmac ~ '^[0-9a-f]{64}$'";

interface GuestTable { name: string; where: string; order: string }
/** 恢复按这个顺序插入（被引用的在前），删除倒过来。:players 是游客玩家 id，:farms 是他们的农场 id（见 guestWhere）。 */
export const GUEST_TABLES: readonly GuestTable[] = [
  { name: 'players', where: 'id = ANY(:players)', order: 'id' },
  { name: 'farms', where: 'owner_id = ANY(:players)', order: 'id' },
  { name: 'farm_creations', where: 'player_id = ANY(:players) OR farm_id = ANY(:farms)', order: 'player_id' },
  { name: 'commands', where: 'farm_id = ANY(:farms)', order: 'id' },
  { name: 'farm_snapshots', where: 'farm_id = ANY(:farms)', order: 'farm_id' },
  { name: 'tokens', where: 'player_id = ANY(:players)', order: 'id' },
  { name: 'online_players', where: 'player_id = ANY(:players)', order: 'player_id' },
  { name: 'parcel_claims', where: 'player_id = ANY(:players)', order: 'community_id, layer, parcel_id' },
  { name: 'parcel_reclaims', where: 'player_id = ANY(:players)', order: 'id' },
];
const TABLE_NAMES = GUEST_TABLES.map(t => t.name);

/** 一张表的条件换成带编号参数的 SQL：每个 :players / :farms 换成 $n::uuid[]，参数只带用到的。 */
export function guestWhere(where: string, players: string[], farms: string[]): { sql: string; params: string[][] } {
  const params: string[][] = [];
  const sql = where.replace(/:(players|farms)\b/g, (_m, key: string) => {
    params.push(key === 'players' ? players : farms);
    return `$${params.length}::uuid[]`;
  });
  return { sql, params };
}
/** 指向这些表的外键只能是这几条（子表.列>父表）；多出来的说明有新表会被级联删掉，工具拒绝运行。 */
export const KNOWN_REFERENCES: readonly string[] = [
  'tokens.player_id>players', 'farms.owner_id>players', 'farm_creations.player_id>players', 'farm_creations.farm_id>farms',
  'commands.farm_id>farms', 'farm_snapshots.farm_id>farms', 'online_players.player_id>players',
  'parcel_claims.player_id>players', 'parcel_reclaims.player_id>players',
];

export type Counts = Record<string, number>;
export interface BackupHeader { format: string; database: string; created_at: number; rule: string; counts: Counts; sha256: string }
export interface ParsedBackup { header: BackupHeader; body: string; rows: Map<string, string> }
export interface PlanResult {
  database: string;
  /** 会删掉的条数（每张表）。 */
  counts: Counts;
  /** 各表现有的总条数。 */
  totals: Counts;
  /** 不受影响的玩家：有账号的（邮箱、邀请账号）和系统玩家（预置农场），以及 user_id 为空但不像安装密钥的其它行。 */
  kept: { account_players: number; other_players: number };
}

export class GuestPurgeError extends Error {}

const sha256 = (text: string) => createHash('sha256').update(text, 'utf8').digest('hex');

async function inTransaction<T>(pool: pg.Pool, begin: string, run: (c: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query(begin);
    const out = await run(client);
    await client.query('COMMIT');
    return out;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

/** 写的时候锁住全部相关表：别人可以读，不能写（新登录、存档会等这个事务结束）。最多等 15 秒拿锁。 */
async function lockTables(c: pg.PoolClient) {
  await c.query("SET LOCAL lock_timeout = '15s'");
  await c.query(`LOCK TABLE ${TABLE_NAMES.join(', ')} IN SHARE ROW EXCLUSIVE MODE`);
}

async function checkReferences(c: pg.PoolClient) {
  const r = await c.query(
    `SELECT cl.relname AS child, a.attname AS col, pl.relname AS parent
       FROM pg_constraint k
       JOIN pg_class cl ON cl.oid = k.conrelid
       JOIN pg_class pl ON pl.oid = k.confrelid
       JOIN pg_namespace n ON n.oid = pl.relnamespace
       JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY(k.conkey)
      WHERE k.contype = 'f' AND n.nspname = current_schema() AND pl.relname = ANY($1::text[])`, [TABLE_NAMES]);
  const unknown = r.rows.map(row => `${row.child}.${row.col}>${row.parent}`).filter(ref => !KNOWN_REFERENCES.includes(ref));
  if (unknown.length) throw new GuestPurgeError(`库里有工具不认识的引用（${[...new Set(unknown)].sort().join('、')}），删游客会把它们级联删掉而不备份；先更新工具`);
}

async function guestIds(c: pg.PoolClient): Promise<[string[], string[]]> {
  const players = (await c.query(`SELECT id::text FROM players WHERE ${GUEST_RULE} ORDER BY id`)).rows.map(r => r.id as string);
  const farms = (await c.query('SELECT id::text FROM farms WHERE owner_id = ANY($1::uuid[]) ORDER BY id', [players])).rows.map(r => r.id as string);
  return [players, farms];
}

/** 这些玩家和农场在每张表里的行：PostgreSQL 输出的 JSON 原文和条数。 */
async function snapshot(c: pg.PoolClient, players: string[], farms: string[]): Promise<{ body: string; counts: Counts }> {
  let body = '';
  const counts: Counts = {};
  for (const t of GUEST_TABLES) {
    const w = guestWhere(t.where, players, farms);
    const r = await c.query(
      `SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY ${t.order}), '[]'::jsonb)::text AS rows, count(*)::int AS n
         FROM ${t.name} t WHERE ${w.sql}`, w.params);
    body += `${t.name}\t${r.rows[0].rows as string}\n`;
    counts[t.name] = r.rows[0].n as number;
  }
  return { body, counts };
}

async function totals(c: pg.PoolClient): Promise<Counts> {
  const out: Counts = {};
  for (const name of TABLE_NAMES) out[name] = (await c.query(`SELECT count(*)::int AS n FROM ${name}`)).rows[0].n as number;
  return out;
}

async function keptPlayers(c: pg.PoolClient): Promise<PlanResult['kept']> {
  const r = await c.query(`SELECT count(*) FILTER (WHERE user_id IS NOT NULL)::int AS accounts,
      count(*) FILTER (WHERE user_id IS NULL AND NOT (${GUEST_RULE}))::int AS others FROM players`);
  return { account_players: r.rows[0].accounts as number, other_players: r.rows[0].others as number };
}

const currentDatabase = async (c: pg.PoolClient) => (await c.query('SELECT current_database() AS db')).rows[0].db as string;

/** 预演：只读，列出会删的条数，什么都不改。 */
export async function planGuestPurge(pool: pg.Pool): Promise<PlanResult> {
  return inTransaction(pool, 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY', async c => {
    await checkReferences(c);
    const [players, farms] = await guestIds(c);
    const { counts } = await snapshot(c, players, farms);
    return { database: await currentDatabase(c), counts, totals: await totals(c), kept: await keptPlayers(c) };
  });
}

/** 备份全部游客数据（只读快照），返回备份文件的全文。 */
export async function backupGuests(pool: pg.Pool, now: number): Promise<string> {
  return inTransaction(pool, 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY', async c => {
    await checkReferences(c);
    const [players, farms] = await guestIds(c);
    const { body, counts } = await snapshot(c, players, farms);
    const header: BackupHeader = { format: BACKUP_FORMAT, database: await currentDatabase(c), created_at: now, rule: GUEST_RULE, counts, sha256: sha256(body) };
    return JSON.stringify(header) + '\n' + body;
  });
}

/** 读回并核对备份：格式、规则、正文哈希、表的顺序和每张表的条数。任何一处不对就抛错。 */
export function parseGuestBackup(text: string): ParsedBackup {
  const cut = text.indexOf('\n');
  if (cut < 0) throw new GuestPurgeError('备份文件不完整：没有头');
  let header: BackupHeader;
  try { header = JSON.parse(text.slice(0, cut)) as BackupHeader; } catch { throw new GuestPurgeError('备份头不是 JSON'); }
  if (header?.format !== BACKUP_FORMAT) throw new GuestPurgeError(`不是 ${BACKUP_FORMAT} 格式的备份`);
  if (header.rule !== GUEST_RULE) throw new GuestPurgeError('备份用的游客判定和当前工具不同');
  if (typeof header.database !== 'string' || !header.database) throw new GuestPurgeError('备份头缺库名');
  const body = text.slice(cut + 1);
  if (sha256(body) !== header.sha256) throw new GuestPurgeError('备份正文的 SHA-256 和头里记的不一致（文件被截断或改过）');
  const lines = body.split('\n');
  if (lines.pop() !== '' || lines.length !== GUEST_TABLES.length) throw new GuestPurgeError('备份正文的表数不对');
  const rows = new Map<string, string>();
  lines.forEach((line, i) => {
    const tab = line.indexOf('\t');
    const name = line.slice(0, tab);
    if (tab < 0 || name !== GUEST_TABLES[i]!.name) throw new GuestPurgeError(`备份第 ${i + 2} 行应是 ${GUEST_TABLES[i]!.name}`);
    let parsed: unknown;
    try { parsed = JSON.parse(line.slice(tab + 1)); } catch { throw new GuestPurgeError(`备份里 ${name} 的行不是 JSON`); }
    if (!Array.isArray(parsed) || parsed.length !== header.counts?.[name])
      throw new GuestPurgeError(`备份里 ${name} 有 ${Array.isArray(parsed) ? parsed.length : '?'} 行，头里记的是 ${header.counts?.[name]}`);
    rows.set(name, line.slice(tab + 1));
  });
  return { header, body, rows };
}

function sameDatabase(backup: ParsedBackup, actual: string, confirm: string) {
  if (confirm !== actual) throw new GuestPurgeError(`--confirm-database 写的是 ${confirm || '（空）'}，连接的库是 ${actual}`);
  if (backup.header.database !== actual) throw new GuestPurgeError(`备份来自库 ${backup.header.database}，连接的库是 ${actual}`);
}

/**
 * 删除：锁表后重新取游客数据，和备份正文逐字节相同才删；删完核对条数，不对就整体回滚。
 * 返回删掉的条数。备份之后游客数据有变化时抛错，什么都不删。
 */
export async function purgeGuests(pool: pg.Pool, backupText: string, confirmDatabase: string): Promise<Counts> {
  const backup = parseGuestBackup(backupText);
  return inTransaction(pool, 'BEGIN ISOLATION LEVEL READ COMMITTED', async c => {
    sameDatabase(backup, await currentDatabase(c), confirmDatabase);
    await lockTables(c);
    await checkReferences(c);
    const [players, farms] = await guestIds(c);
    const now = await snapshot(c, players, farms);
    if (now.body !== backup.body)
      throw new GuestPurgeError('备份之后游客数据有变化（或备份不是这批游客的），什么都没删；请重新备份再删');
    const before = await totals(c);
    const kept = await keptPlayers(c);
    for (const t of [...GUEST_TABLES].reverse()) {
      const w = guestWhere(t.where, players, farms);
      const r = await c.query(`DELETE FROM ${t.name} t WHERE ${w.sql}`, w.params);
      if (r.rowCount !== backup.header.counts[t.name])
        throw new GuestPurgeError(`${t.name} 删掉 ${r.rowCount} 行，备份里是 ${backup.header.counts[t.name]} 行；已回滚`);
    }
    const after = await totals(c);
    for (const name of TABLE_NAMES)
      if (after[name] !== before[name]! - backup.header.counts[name]!)
        throw new GuestPurgeError(`${name} 删除前 ${before[name]} 行、删除后 ${after[name]} 行，和备份的 ${backup.header.counts[name]} 行对不上；已回滚`);
    const left = await keptPlayers(c);
    if (left.account_players !== kept.account_players || left.other_players !== kept.other_players)
      throw new GuestPurgeError('有账号的玩家或系统玩家的条数变了；已回滚');
    if ((await guestIds(c))[0].length) throw new GuestPurgeError('删除后还有游客号；已回滚');
    return { ...backup.header.counts };
  });
}

/** 恢复：把备份原样插回，再取一遍和备份逐字节相同才提交。已有冲突的行（同一玩家、同一块地已被认领）时整体回滚。 */
export async function restoreGuests(pool: pg.Pool, backupText: string, confirmDatabase: string): Promise<Counts> {
  const backup = parseGuestBackup(backupText);
  const ids = (name: string, key: string) => (JSON.parse(backup.rows.get(name)!) as Record<string, string>[]).map(r => r[key]!);
  return inTransaction(pool, 'BEGIN ISOLATION LEVEL READ COMMITTED', async c => {
    sameDatabase(backup, await currentDatabase(c), confirmDatabase);
    await lockTables(c);
    await checkReferences(c);
    const before = await totals(c);
    for (const t of GUEST_TABLES) {
      const r = await c.query(`INSERT INTO ${t.name} SELECT * FROM jsonb_populate_recordset(NULL::${t.name}, $1::jsonb)`, [backup.rows.get(t.name)]);
      if (r.rowCount !== backup.header.counts[t.name])
        throw new GuestPurgeError(`${t.name} 插回 ${r.rowCount} 行，备份里是 ${backup.header.counts[t.name]} 行；已回滚`);
    }
    const back = await snapshot(c, ids('players', 'id'), ids('farms', 'id'));
    if (back.body !== backup.body) throw new GuestPurgeError('恢复后的数据和备份不一致；已回滚');
    const after = await totals(c);
    for (const name of TABLE_NAMES)
      if (after[name] !== before[name]! + backup.header.counts[name]!) throw new GuestPurgeError(`${name} 恢复后的总条数不对；已回滚`);
    return { ...backup.header.counts };
  });
}

export const GUEST_PURGE_USAGE = `用法（只连 DATABASE_URL）：
  guest_purge.ts plan                                                   预演：列出会删的条数，不改任何数据
  guest_purge.ts backup --out <新文件|->                                 备份全部游客数据
  guest_purge.ts verify --backup <文件|->                                核对备份文件并列出条数
  guest_purge.ts purge --backup <文件|-> --confirm-database <库名>       按备份删除（数据和备份逐字节相同才删）
  guest_purge.ts restore --backup <文件|-> --confirm-database <库名>     把备份插回
--out - 只在标准输出被重定向时可用；--backup - 从标准输入读。`;

export interface GuestPurgeIo {
  pool: pg.Pool;
  cwd: string;
  stdoutIsTTY: boolean;
  stdout: (text: string) => void;
  stderr: (text: string) => void;
  readStdin: () => string;
  now: () => number;
}

/** 备份里有安装密钥的 HMAC 和登录令牌的哈希：只写新文件（0600）、不进 Git 工作区，`-` 只写到重定向的标准输出。 */
export function backupOutRefusal(out: string | undefined, cwd: string, stdoutIsTTY: boolean): string | null {
  if (!out) return '必须给 --out：新文件，或重定向的标准输出（-）';
  if (out === '-') return stdoutIsTTY ? '标准输出是终端，不把备份打在屏幕上；请重定向到文件，或用 --out <新文件>' : null;
  const file = path.resolve(cwd, out);
  const dir = path.dirname(file);
  if (!existsSync(dir)) return `目录不存在：${dir}`;
  if (existsSync(file)) return `文件已存在，不覆盖：${file}`;
  if (insideGitWorkTree(realpathSync(dir))) return `不能写进 Git 工作区：${dir}`;
  return null;
}

const line = (counts: Counts) => GUEST_TABLES.map(t => `${t.name}=${counts[t.name] ?? 0}`).join(' ');

/** 命令行。返回退出码：0 成功，1 核对失败（什么都没改），2 用法错误。 */
export async function runGuestPurgeCli(argv: string[], io: GuestPurgeIo): Promise<number> {
  let values: { out?: string; backup?: string; 'confirm-database'?: string };
  let positionals: string[];
  try {
    ({ values, positionals } = parseArgs({ args: argv, allowPositionals: true, strict: true,
      options: { out: { type: 'string' }, backup: { type: 'string' }, 'confirm-database': { type: 'string' } } }));
  } catch (error) { io.stderr(`${(error as Error).message}\n${GUEST_PURGE_USAGE}\n`); return 2; }
  const [cmd, ...rest] = positionals;
  if (!cmd || rest.length) { io.stderr(GUEST_PURGE_USAGE + '\n'); return 2; }
  const readBackup = () => values.backup === '-' ? io.readStdin() : readFileSync(path.resolve(io.cwd, values.backup!), 'utf8');
  const needs = (...keys: (keyof typeof values)[]) => {
    const missing = keys.filter(k => !values[k]);
    if (missing.length) { io.stderr(`${cmd} 需要 ${missing.map(k => '--' + k).join('、')}\n${GUEST_PURGE_USAGE}\n`); return false; }
    return true;
  };
  try {
    switch (cmd) {
      case 'plan': {
        const plan = await planGuestPurge(io.pool);
        io.stdout(`预演（库 ${plan.database}，未改任何数据）：会删 ${line(plan.counts)}\n`);
        io.stdout(`各表现有 ${line(plan.totals)}；保留有账号的玩家 ${plan.kept.account_players} 个、其它玩家（系统等）${plan.kept.other_players} 个\n`);
        return 0;
      }
      case 'backup': {
        const refusal = backupOutRefusal(values.out, io.cwd, io.stdoutIsTTY);
        if (refusal) { io.stderr(refusal + '\n'); return 2; }
        const text = await backupGuests(io.pool, io.now());
        const { header } = parseGuestBackup(text);
        if (values.out === '-') io.stdout(text);
        else {
          const file = path.resolve(io.cwd, values.out!);
          const fd = openSync(file, 'wx', 0o600);
          try { writeSync(fd, text); } catch (error) { closeSync(fd); unlinkSync(file); throw error; }
          closeSync(fd);
          // 读回核对：写进磁盘的就是这份备份。
          if (readFileSync(file, 'utf8') !== text) { unlinkSync(file); throw new GuestPurgeError('备份写入后读回不一致'); }
        }
        io.stderr(`备份完成（库 ${header.database}，sha256 ${header.sha256}）：${line(header.counts)}\n`);
        return 0;
      }
      case 'verify': {
        if (!needs('backup')) return 2;
        const { header } = parseGuestBackup(readBackup());
        io.stdout(`备份核对通过（库 ${header.database}，${new Date(header.created_at).toISOString()}，sha256 ${header.sha256}）：${line(header.counts)}\n`);
        return 0;
      }
      case 'purge': {
        if (!needs('backup', 'confirm-database')) return 2;
        const deleted = await purgeGuests(io.pool, readBackup(), values['confirm-database']!);
        io.stdout(`已删除并核对：${line(deleted)}\n`);
        return 0;
      }
      case 'restore': {
        if (!needs('backup', 'confirm-database')) return 2;
        const restored = await restoreGuests(io.pool, readBackup(), values['confirm-database']!);
        io.stdout(`已恢复并核对：${line(restored)}\n`);
        return 0;
      }
      default:
        io.stderr(GUEST_PURGE_USAGE + '\n'); return 2;
    }
  } catch (error) {
    io.stderr(`✗ ${(error as Error).message}\n`);
    return 1;
  }
}

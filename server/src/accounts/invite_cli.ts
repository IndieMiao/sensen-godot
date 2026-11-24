/**
 * 邀请账号命令行（C-96），入口 tools/invite_accounts.ts。密码只写到 --out 指定的地方：
 * 文件必须是新文件（0600），且不能在 Git 工作区里；`--out -` 只在标准输出被重定向时可用，不往终端打。
 * 运行日志（标准错误）只有数量、批次和去向，没有密码。
 */
import { closeSync, existsSync, openSync, realpathSync, unlinkSync, writeSync } from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import type pg from 'pg';
import { createInvites, disableInvite, listInvites, resetInvite, type InviteCredential } from './invites.js';

export interface InviteCliIo {
  pool: pg.Pool;
  env: Record<string, string | undefined>;
  cwd: string;
  stdoutIsTTY: boolean;
  stdout: (text: string) => void;
  stderr: (text: string) => void;
  now: () => number;
}

export const INVITE_USAGE = `用法（DATABASE_URL 指向动态农场正式库）：
  invite_accounts.ts create --count <n> --batch <批次> --out <新文件|-> [--domain <域名>] [--prefix <前缀>]
  invite_accounts.ts list [--batch <批次>]
  invite_accounts.ts reset --email <邮箱> --out <新文件|->
  invite_accounts.ts disable --email <邮箱>
域名默认取 INVITE_EMAIL_DOMAIN。--out - 只在标准输出被重定向（管道或文件）时可用。`;

/** 从 dir 往上找 .git（目录或 worktree 的文件），找到就说明在 Git 工作区里。 */
export function insideGitWorkTree(dir: string): boolean {
  for (let d = dir; ; d = path.dirname(d)) {
    if (existsSync(path.join(d, '.git'))) return true;
    if (path.dirname(d) === d) return false;
  }
}

/** 拒绝的原因，或 null（可以写）。 */
export function outRefusal(out: string | undefined, cwd: string, stdoutIsTTY: boolean): string | null {
  if (!out) return '必须给 --out：密码只写到新文件或重定向的标准输出';
  if (out === '-') return stdoutIsTTY ? '标准输出是终端，不把密码打在屏幕上；请重定向到受控存储，或用 --out <新文件>' : null;
  const file = path.resolve(cwd, out);
  const dir = path.dirname(file);
  if (!existsSync(dir)) return `目录不存在：${dir}`;
  if (existsSync(file)) return `文件已存在，不覆盖：${file}`;
  if (insideGitWorkTree(realpathSync(dir))) return `不能写进 Git 工作区：${dir}`;
  return null;
}

const csv = (rows: InviteCredential[]) => 'email,password,batch\n' + rows.map(r => `${r.email},${r.password},${r.batch}\n`).join('');

/** 先占住输出文件（新建、0600）再写库：文件建不出来就一个账号也不建；写库失败时删掉这个空文件。 */
function openOut(io: InviteCliIo, out: string): { where: string; write: (text: string) => void; discard: () => void } {
  if (out === '-') return { where: '标准输出', write: io.stdout, discard: () => {} };
  const file = path.resolve(io.cwd, out);
  const fd = openSync(file, 'wx', 0o600);
  let open = true;
  const close = () => { if (open) { open = false; closeSync(fd); } };
  return {
    where: file,
    write: text => { try { writeSync(fd, text); } finally { close(); } },
    discard: () => { close(); unlinkSync(file); },
  };
}

/** 返回进程退出码：0 成功，1 执行失败，2 参数或输出位置不对。 */
export async function runInviteCli(argv: string[], io: InviteCliIo): Promise<number> {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, allowPositionals: true, strict: true, options: {
      count: { type: 'string' }, batch: { type: 'string' }, out: { type: 'string' }, domain: { type: 'string' },
      prefix: { type: 'string' }, email: { type: 'string' }, help: { type: 'boolean', default: false },
    } });
  } catch (error) {
    io.stderr(`${(error as Error).message}\n${INVITE_USAGE}\n`);
    return 2;
  }
  const { values, positionals } = parsed;
  const command = positionals[0];
  if (values.help || !command || positionals.length > 1) { io.stderr(INVITE_USAGE + '\n'); return values.help ? 0 : 2; }

  if (command === 'create' || command === 'reset') {
    const refusal = outRefusal(values.out, io.cwd, io.stdoutIsTTY);
    if (refusal) { io.stderr(refusal + '\n'); return 2; }
  }
  let sink: ReturnType<typeof openOut> | undefined;
  try {
    switch (command) {
      case 'create': {
        const domain = values.domain ?? io.env.INVITE_EMAIL_DOMAIN;
        if (!domain || !values.batch || !values.count) { io.stderr('create 需要 --count、--batch，以及 --domain 或 INVITE_EMAIL_DOMAIN\n'); return 2; }
        sink = openOut(io, values.out!);
        const rows = await createInvites(io.pool, { count: Number(values.count), domain, batch: values.batch, prefix: values.prefix }, io.now());
        const done = sink; sink = undefined; // 写库已提交：之后出错也不删这个文件
        done.write(csv(rows));
        io.stderr(`已建 ${rows.length} 个邀请账号（批次 ${values.batch}），账号和密码写到 ${done.where}\n`);
        return 0;
      }
      case 'reset': {
        if (!values.email) { io.stderr('reset 需要 --email\n'); return 2; }
        sink = openOut(io, values.out!);
        const row = await resetInvite(io.pool, values.email);
        if (!row) { sink.discard(); io.stderr('没有这个邀请账号\n'); return 1; }
        const done = sink; sink = undefined;
        done.write(csv([row]));
        io.stderr(`已重置 ${row.email} 的密码并撤销它的全部会话，新密码写到 ${done.where}\n`);
        return 0;
      }
      case 'disable': {
        if (!values.email) { io.stderr('disable 需要 --email\n'); return 2; }
        if (!await disableInvite(io.pool, values.email)) { io.stderr('没有这个邀请账号\n'); return 1; }
        io.stderr(`已停用 ${values.email.trim().toLowerCase()}：不能再登录，会话已撤销，地块和存档保留\n`);
        return 0;
      }
      case 'list': {
        const rows = await listInvites(io.pool, values.batch);
        io.stdout('email\tbatch\tcreated_at\tlast_seen_at\tdisabled\thas_parcel\n');
        for (const r of rows) io.stdout(`${r.email}\t${r.batch}\t${new Date(r.created_at).toISOString()}\t${new Date(r.last_seen_at).toISOString()}\t${r.disabled}\t${r.has_parcel}\n`);
        io.stderr(`共 ${rows.length} 个邀请账号\n`);
        return 0;
      }
      default:
        io.stderr(`未知命令 ${command}\n${INVITE_USAGE}\n`);
        return 2;
    }
  } catch (error) {
    sink?.discard();
    io.stderr(`失败：${(error as Error).message}\n`);
    return 1;
  }
}

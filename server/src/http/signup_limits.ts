/**
 * 匿名建号（新安装第一次 /v1/auth/anonymous）每小时的三层上限（C-95#2、C-100、C-120）。已有玩家再次登录都不占，
 * 只受每个安装每小时 10 次的登录限制。新玩家要三层都还有额度才建出来，从细到粗依次扣：
 * - 每个网络（network.ts：IPv4 按地址，IPv6 按 /64），默认 10；
 * - 每个地址段（IPv6 按 /48，IPv4 仍按地址），默认 50：手里有大段 IPv6 的来源换 /64 也绕不过；
 * - 整个进程合计，默认 1000：不管来源怎么分散，一小时新建的匿名玩家总数有上限。
 * 额度记在进程内存里，和其它限流一样；正式服只跑一个 app 进程。
 */
export interface AnonymousSignupLimits {
  perNetwork: number;
  perBlock: number;
  total: number;
}

export const DEFAULT_ANONYMOUS_SIGNUP_LIMITS: AnonymousSignupLimits = { perNetwork: 10, perBlock: 50, total: 1000 };

const ENV: Record<keyof AnonymousSignupLimits, string> = {
  perNetwork: 'ANONYMOUS_SIGNUPS_PER_NETWORK_HOUR',
  perBlock: 'ANONYMOUS_SIGNUPS_PER_BLOCK_HOUR',
  total: 'ANONYMOUS_SIGNUPS_PER_HOUR',
};

/** 不设或空为默认值；1–1000000 的整数。其它值返回出错的变量名，进程拒绝启动。 */
export function anonymousSignupLimitsFromEnv(env: Record<string, string | undefined>): AnonymousSignupLimits | { invalid: string } {
  const limits = { ...DEFAULT_ANONYMOUS_SIGNUP_LIMITS };
  for (const key of Object.keys(ENV) as (keyof AnonymousSignupLimits)[]) {
    const raw = env[ENV[key]] ?? '';
    if (raw === '') continue;
    if (!/^\d{1,7}$/.test(raw) || Number(raw) < 1 || Number(raw) > 1_000_000) return { invalid: ENV[key] };
    limits[key] = Number(raw);
  }
  return limits;
}

/**
 * C-146：游客入口开关 GUEST_ACCOUNTS（所有者 11-25：“移除游客模式, 必须要注册/有账号才能玩”）。不设、空或 open 为开
 * （Journey 和开发服照旧）；closed 时 /v1/auth/anonymous 一律回 403 GUEST_CLOSED（新安装和已有游客都不再签发 token），
 * 已经发出去的游客 token 也不再算登录。其它值返回 null，进程拒绝启动，免得拼错后悄悄开着。动态农场正式服在 compose.yml 写死 closed。
 */
export function guestAccountsClosedFromEnv(env: Record<string, string | undefined>): boolean | null {
  const v = env.GUEST_ACCOUNTS;
  if (v === undefined || v === '' || v === 'open') return false;
  return v === 'closed' ? true : null;
}

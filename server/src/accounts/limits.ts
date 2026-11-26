/**
 * 账号登录与发信的可配置上限（C-132）。额度和其它限流一样记在进程内存里（正式服只跑一个 app 进程）；
 * “账号登录过的网络”与用过的 Google nonce 落库，重启后仍有效。
 *
 * 登录（邮箱 + 密码，以及站外删号）按两层计：
 * - 每个邮箱在每个网络（network.ts：IPv4 按地址，IPv6 按 /64）15 分钟 loginPerNetwork 次，谁都受它约束；
 * - 每个邮箱 15 分钟 loginPerAccount 次，只算来自“该账号 trustedNetworkDays 天内成功登录过的网络”以外的尝试。
 *   旁人在自己的网络上反复试错，只会把陌生网络挡在外面，账号本人从登录过的网络照常能登；
 *   陌生网络合起来的额度与改前按邮箱计的一样，爆破不因按网络拆分而放宽。
 *
 * 验证信（注册、发码、站外删号码）每封都按收件邮箱和全局计：每个收件邮箱每小时 / 每天、全服每小时 / 每天。
 * 发码接口在查邮箱是否注册**之前**扣额度，未注册的邮箱同样计数，超限的回包不因注册与否而不同。
 */
export interface AccountLimits {
  loginPerNetwork: number;
  loginPerAccount: number;
  trustedNetworkDays: number;
  mailPerRecipientHour: number;
  mailPerRecipientDay: number;
  mailPerHour: number;
  mailPerDay: number;
}

export const DEFAULT_ACCOUNT_LIMITS: AccountLimits = {
  loginPerNetwork: 10, loginPerAccount: 10, trustedNetworkDays: 90,
  mailPerRecipientHour: 5, mailPerRecipientDay: 10, mailPerHour: 200, mailPerDay: 1000,
};

export const ACCOUNT_LIMIT_ENV: Record<keyof AccountLimits, string> = {
  loginPerNetwork: 'LOGIN_ATTEMPTS_PER_NETWORK_15MIN',
  loginPerAccount: 'LOGIN_ATTEMPTS_PER_ACCOUNT_15MIN',
  trustedNetworkDays: 'LOGIN_TRUSTED_NETWORK_DAYS',
  mailPerRecipientHour: 'MAIL_PER_RECIPIENT_HOUR',
  mailPerRecipientDay: 'MAIL_PER_RECIPIENT_DAY',
  mailPerHour: 'MAIL_PER_HOUR',
  mailPerDay: 'MAIL_PER_DAY',
};

/** 不设或空为默认值；1–1000000 的整数。其它值返回出错的变量名，进程拒绝启动。 */
export function accountLimitsFromEnv(env: Record<string, string | undefined>): AccountLimits | { invalid: string } {
  const limits = { ...DEFAULT_ACCOUNT_LIMITS };
  for (const key of Object.keys(ACCOUNT_LIMIT_ENV) as (keyof AccountLimits)[]) {
    const raw = env[ACCOUNT_LIMIT_ENV[key]] ?? '';
    if (raw === '') continue;
    if (!/^\d{1,7}$/.test(raw) || Number(raw) < 1 || Number(raw) > 1_000_000) return { invalid: ACCOUNT_LIMIT_ENV[key] };
    limits[key] = Number(raw);
  }
  return limits;
}

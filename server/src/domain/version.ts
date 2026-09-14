/**
 * 领域语义版本。改 reducer 的**行为**（不只是重构）就必须 +1：`farms` 与每条 `commands`
 * 都记住它，进程遇到版本不匹配的农场直接 503 fail closed，而不是静默换一套规则去算
 * （Codex 二审 Important 4）。
 *
 * state 结构版本单列：它决定要不要跑启动前迁移脚本。
 */
export const DOMAIN_VERSION = '14';
export const STATE_SCHEMA_VERSION = 1;

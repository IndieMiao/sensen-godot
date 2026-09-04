/** 领域错误码。HTTP 层把它们映射成 422（spec §7.4）。 */
export const DOMAIN_ERRORS = [
  'CELL_NOT_CULTIVABLE', 'CELL_LOCKED', 'WRONG_STATE', 'WRONG_CARE', 'NOT_RIPE',
  'INSUFFICIENT_FUNDS', 'INSUFFICIENT_ITEMS', 'CHAPTER_LOCKED', 'STALL_BUDGET',
  'BOUND_SEED', 'ALREADY_CLAIMED', 'LOCKED_CHOICE', 'REQUEST_MISMATCH', 'REQUEST_DONE',
  'SLOT_TAKEN', 'NOT_AVAILABLE', 'BUYBACK_LIMIT', 'PACK_LIMIT', 'CLOCK_REGRESSION',
  'BAD_QA_PARAM', 'BLUEPRINT_MISMATCH', 'DUPLICATE_CELL',
] as const;
export type DomainErrorCode = (typeof DOMAIN_ERRORS)[number];

export interface Ok<S> { ok: true; state: S; events: DomainEvent[] }
export interface Err { ok: false; code: DomainErrorCode; detail?: string }
export type Result<S> = Ok<S> | Err;

/** 事件只用于客户端表现与测试断言，不参与状态计算。 */
export interface DomainEvent { type: string; [k: string]: unknown }

export const err = (code: DomainErrorCode, detail?: string): Err => ({ ok: false, code, detail });
export const ok = <S>(state: S, events: DomainEvent[] = []): Ok<S> => ({ ok: true, state, events });

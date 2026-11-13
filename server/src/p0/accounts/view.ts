/**
 * view.account (SGODOT-488; contract-accounts.md §1): the account page's and the name page's facts, the server's word —
 * the name, which sign-ins are linked, when the name may change next (0: now) and the terms agreed to.
 * rename_at until 周瑜's accountNameView (accounts/name.ts) takes its place: a name given waits RENAME_WAIT_MS from when
 * it was given, a skipped one does not (q(313) ②), and a reset by a sanction waits until name_locked_until.
 */
import type { P0State } from '../state.js';
import type { Provider } from './store.js';

export const RENAME_WAIT_MS = 7 * 86_400_000;

export interface AccountView { name: string | null; linked: Provider[]; rename_at: number; consent: { terms: string; privacy: string } | null }

export function accountView(s: P0State, linked: Provider[], now: number): AccountView {
  const p = s.profile ?? {};
  const next = Math.max(p.name_set_at !== undefined ? p.name_set_at + RENAME_WAIT_MS : 0, p.name_locked_until ?? 0);
  return { name: p.name ?? null, linked, rename_at: next > now ? next : 0,
    consent: s.consent ? { terms: s.consent.terms, privacy: s.consent.privacy } : null };
}

/**
 * view.account (SGODOT-488; contract-accounts.md §1): the account page's and the name page's facts, the server's word —
 * the name (null when skipped or reset), which sign-ins are linked, when the name may change next (0: now; 周瑜's
 * accountNameView, on the save's clock as account/name judges it) and the terms agreed to.
 */
import type { P0State } from '../state.js';
import { accountNameView } from './name.js';
import type { Provider } from './store.js';

export interface AccountView { name: string | null; linked: Provider[]; rename_at: number; consent: { terms: string; privacy: string } | null }

export function accountView(s: P0State, linked: Provider[], now: number): AccountView {
  const n = accountNameView(s, now + s.clock_ms);
  return { name: n.name, linked, rename_at: n.rename_at,
    consent: s.consent ? { terms: s.consent.terms, privacy: s.consent.privacy } : null };
}

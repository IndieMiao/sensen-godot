/** SGODOT-484, contract-accounts §4. Shared by authenticated App, admin, web and Apple-notification entry points.
 * No route is enabled here. Never use a support code as proof of identity. */
import type { P0Store } from '../store.js';
import type { P0Voice } from '../online/voice.js';
import { supportCode } from '../support.js';
import { PROVIDERS, type P0Accounts } from './store.js';

export interface DeleteDeps {
  store: P0Store; accounts: P0Accounts; voice: P0Voice;
  hub: { kick(player: string): void }; now: () => number;
  revokeApple?: (aud: string, refresh: string) => Promise<void>;
}

/** No create/find-with-settlement, no writes, no credentials or name snapshot in the preview. */
export function previewAccountDeletion(deps: Pick<DeleteDeps, 'store' | 'accounts'>, player: string) {
  const save = deps.store.peek(player), account = deps.accounts.find(player);
  return { support_code: supportCode(player), found: !!(save || account), deleted: deps.accounts.isDeleted(player),
    linked: PROVIDERS.filter(provider => !!account?.[provider]),
    save: save ? { home: save.travel.home, level: save.homestead.level,
      created_at: save.created_at, last_at: save.presence.last_at } : null };
}

const pending = new WeakMap<P0Accounts, Map<string, Promise<void>>>();
/** In-process duplicates share the same operation. Retrying a persisted tombstone resumes cleanup without extending it. */
export async function deleteAccount(deps: DeleteDeps, player: string): Promise<void> {
  let jobs = pending.get(deps.accounts);
  if (!jobs) { jobs = new Map(); pending.set(deps.accounts, jobs); }
  const running = jobs.get(player);
  if (running) return running;
  const job = removeAccount(deps, player).finally(() => jobs!.delete(player));
  jobs.set(player, job);
  return job;
}

async function removeAccount(deps: DeleteDeps, player: string): Promise<void> {
  const { accounts, store, voice, hub } = deps;
  const row = accounts.find(player), deleted = accounts.isDeleted(player);
  if (!row && !store.peek(player) && !deleted) return;
  // A1 find() returns the decrypted refresh. Keep it only in this call, before removing the account row.
  const apple = row?.apple;
  accounts.revokeAll(player);
  if (!deleted) accounts.markDeleted(player, deps.now());
  accounts.remove(player); // Also removes admin tokens and identity indexes; finish this synchronous phase before the save.

  let incomplete = false;
  const failed = (stage: string) => {
    incomplete = true;
    console.warn(JSON.stringify({ account: 'delete_incomplete', support_code: supportCode(player), stage }));
  };
  try { store.remove(player); } catch { failed('save'); }
  // Start releasing voice, then kick before awaiting the provider. Even an I/O failure must not leave a live WS.
  let cleanup: Promise<void> | undefined;
  try { cleanup = voice.removePlayer(player); } catch { failed('voice'); }
  try { hub.kick(player); } catch { failed('hub'); }
  try { await cleanup; } catch { failed('voice'); }

  if (apple) {
    if (apple.refresh && deps.revokeApple) {
      try { await deps.revokeApple(apple.aud, apple.refresh); }
      catch { console.warn(JSON.stringify({ account: 'apple_revoke_failed', support_code: supportCode(player) })); }
    } else {
      console.warn(JSON.stringify({ account: 'apple_revoke_skipped', support_code: supportCode(player) }));
    }
  }
  if (incomplete) throw new Error('ACCOUNT_DELETE_INCOMPLETE');
}

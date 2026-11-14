/** SGODOT-484, contract-accounts §4. Shared by authenticated App, admin, web and Apple-notification entry points.
 * The App's own route is here (registerAccountDeleteRoute, SGODOT-488); the others register theirs where they live.
 * Never use a support code as proof of identity. */
import type { FastifyInstance } from 'fastify';
import type { P0Store } from '../store.js';
import type { P0Voice } from '../online/voice.js';
import { supportCode } from '../support.js';
import { identify, isRefusal, type IdentifyDeps } from './identify.js';
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

/**
 * DELETE /v1/p0/account (contract §4, v1.6.6; SGODOT-488): the player's own account deleted from the App — its token
 * only (an id alone, an old build's, cannot), and a suspended account too (App Store 5.1.1(v), Play: deletion open to
 * every account). {ok: true} once the account is gone for every request (its tokens revoked, on the deleted list) —
 * also when a later step failed (the save's file, voice): this phone's token is spent, so the App cannot ask again;
 * deleteAccount has logged delete_incomplete with the support code, and the admin's run of it on the tombstone finishes.
 * The first stretch failing to write (nothing deleted) is 500 delete_failed: the App says Didn't go through.
 */
export function registerAccountDeleteRoute(app: FastifyInstance, deps: DeleteDeps & { identify: IdentifyDeps }): void {
  app.delete('/v1/p0/account', async (req, reply) => {
    const w = identify(req.headers, deps.identify, { evenSuspended: true });
    if (isRefusal(w)) return reply.code(w.status).send(w.body);
    if (w.via !== 'token') return reply.code(401).send({ ok: false, code: 'unauthenticated' });
    try { await deleteAccount(deps, w.player); }
    catch (e) {
      // the first, synchronous stretch (tokens, the deleted list, the account row) failed to write: nothing is deleted —
      // the farm is still there and the player must not be told otherwise (周瑜 on #1048)
      if (!(e instanceof Error && e.message === 'ACCOUNT_DELETE_INCOMPLETE')) {
        console.warn(JSON.stringify({ account: 'delete_failed_app', support_code: supportCode(w.player) }));
        return reply.code(500).send({ ok: false, code: 'delete_failed' });
      }
      console.warn(JSON.stringify({ account: 'delete_incomplete_app', support_code: supportCode(w.player) }));
    }
    return { ok: true };
  });
}

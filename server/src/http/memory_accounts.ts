/** 内存 AccountStore：HTTP 层测试用。语义与 PgAccountStore 保持一致（见 accounts_conformance）。 */
import { randomUUID } from 'node:crypto';
import type { AccountStore, DeletionRecord, IdentityRow, UserRow } from './accounts.js';
import type { FirebaseIdentity } from './firebase_token.js';

export class MemoryAccountStore implements AccountStore {
  private users = new Map<string, UserRow>();
  private identities = new Map<string, IdentityRow>(); // key: provider:uid
  private deletions = new Map<string, DeletionRecord>();

  async signIn(identity: FirebaseIdentity, now: number) {
    const key = `firebase:${identity.uid}`;
    const existing = this.identities.get(key);
    if (existing) {
      const u = this.users.get(existing.user_id)!;
      u.last_seen_at = now;
      if (identity.email !== undefined) u.email = identity.email;
      u.email_verified = identity.emailVerified;
      return { user: { ...u }, created: false };
    }
    const user: UserRow = {
      id: randomUUID(), email: identity.email ?? null, email_verified: identity.emailVerified,
      created_at: now, last_seen_at: now,
    };
    this.users.set(user.id, user);
    this.identities.set(key, {
      provider: 'firebase', provider_uid: identity.uid, user_id: user.id,
      sign_in_provider: identity.signInProvider ?? null, created_at: now,
    });
    return { user: { ...user }, created: true };
  }

  async userByFirebaseUid(uid: string) {
    const id = this.identities.get(`firebase:${uid}`);
    return id ? { ...this.users.get(id.user_id)! } : null;
  }
  async userById(id: string) { const u = this.users.get(id); return u ? { ...u } : null; }
  async identitiesOf(userId: string) {
    return [...this.identities.values()].filter(i => i.user_id === userId).map(i => ({ ...i }));
  }
  async deleteUser(userId: string, tombstone: DeletionRecord) {
    if (!this.users.delete(userId)) return false;
    for (const [k, i] of this.identities) if (i.user_id === userId) this.identities.delete(k);
    this.deletions.set(userId, { ...tombstone });
    return true;
  }
  async deletion(userId: string) { const d = this.deletions.get(userId); return d ? { ...d } : null; }
}

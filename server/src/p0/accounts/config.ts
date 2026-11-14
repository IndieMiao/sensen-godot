/**
 * Accounts (SGODOT-488 / 489; contract-accounts.md §2): the sign-in providers' settings, read once from the environment.
 * Apple's private key is a file mounted read-only (mode 400) beside the server, never in the environment or the repo.
 * APPLE_BUNDLE_IDS are the app's (session/apple), APPLE_SERVICES_IDS the web page's (web-delete only): a token made for
 * one is not taken by the other. GOOGLE_CLIENT_IDS: the Web and iOS clients (an Android id token's aud is the Web one).
 */
import { readFileSync } from 'node:fs';

export interface AppleConfig { teamId: string; keyId: string; privateKeyFile: string; bundleIds: string[]; servicesIds: string[] }
export interface AccountsConfig {
  apple: AppleConfig | null;          // null: Apple sign-in off (a key, team or bundle missing)
  google: { audiences: string[] } | null;
  legacyId: boolean;                  // P0_LEGACY_ID=1: any player by x-p0-player alone (devserver, shots, tests; never live)
  guestOk: boolean;                   // P0_GUEST_OK=1: session/guest without a sign-in (devserver, shots; never live — v1.4 ⑪)
  emailLogin: boolean;                // P0_EMAIL_LOGIN=1: sign in with an emailed code (contract v1.5; off by default — one switch, no client release)
  refreshKey: Buffer | null;          // P0_ACCOUNTS_KEY (64 hex): AES-GCM for the stored Apple refresh tokens
}

const list = (v: string | undefined): string[] => (v ?? '').split(',').map(s => s.trim()).filter(Boolean);

export function accountsConfig(env: Record<string, string | undefined> = process.env): AccountsConfig {
  const bundleIds = list(env.APPLE_BUNDLE_IDS);
  const apple = env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY_FILE && bundleIds.length
    ? { teamId: env.APPLE_TEAM_ID, keyId: env.APPLE_KEY_ID, privateKeyFile: env.APPLE_PRIVATE_KEY_FILE, bundleIds,
      servicesIds: list(env.APPLE_SERVICES_IDS) }
    : null;
  const audiences = list(env.GOOGLE_CLIENT_IDS);
  const key = env.P0_ACCOUNTS_KEY ?? '';
  return {
    apple,
    google: audiences.length ? { audiences } : null,
    legacyId: env.P0_LEGACY_ID === '1',
    guestOk: env.P0_GUEST_OK === '1',
    emailLogin: env.P0_EMAIL_LOGIN === '1',
    refreshKey: /^[0-9a-f]{64}$/i.test(key) ? Buffer.from(key, 'hex') : null,
  };
}

/** The private key's text, read when a client secret is made (Apple's code exchange and revoke). */
export function applePrivateKey(c: AppleConfig): string { return readFileSync(c.privateKeyFile, 'utf8'); }

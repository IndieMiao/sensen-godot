# Sign in with Apple server notifications

`POST /v1/apple/notifications` accepts Apple's JSON `{ "payload": "<signed JWS>" }` outside the game-key namespace.
The public URL remains `https://farm.sensenjoy.cn/preview/p0/v1/apple/notifications`; Caddy strips `/preview/p0`.
TLS/external callback delivery must be verified separately before release. No production endpoint was deployed by this change.

## Verification and configuration

- Reuses Apple's cached public JWKS, RS256 verifier and key-rotation refresh. A private `.p8` key is **not** read for notifications.
- The allowed audience set is `APPLE_BUNDLE_IDS` plus `APPLE_SERVICES_IDS`; no configured audiences returns 503.
- Checks exact issuer `https://appleid.apple.com`, audience, integer `iat`, nonempty `jti`, typed `events` and `event_time`.
  `events` may be the documented JSON object or a JSON-encoded string. `exp`, when present, is checked; Apple's official
  examples have no `exp`, so an ID-token verifier is not appropriate here.
- Delivery age is bounded to 30 days; future skew is at most 60 seconds. This is a technical replay/storage window,
  not a player retention or punishment policy. Notifications older than that need operational investigation, not manual
  replay with edited signature fields. The real Apple retry behavior still requires provider-side verification.
- Own per-IP limit is 60 requests per minute, with a bounded address map; request body is at most 8 KiB (JWS verifier
  also retains its existing 4096-character limit). The ordinary `/v1/p0/*` key/auth guards are unchanged.
- Invalid/schema input is 400/401; unavailable keys/config is 503; pending I/O/media cleanup is 503
  `notification_incomplete`, inviting retry. Valid already-processed, unknown-subject, email-preference or unsupported
  events return `{ok:true}` without creating accounts or farms. Error responses/logs do not echo JWTs, email, sub or jti.

## Actions

The contract's **v1.4** section overrides the earlier §3 wording:

| Event | Action |
|---|---|
| `consent-revoked` | Preserve Apple sub/aud and farm. Revoke user tokens, remove the saved refresh token, invalidate older pending Apple grants, kick WS and release voice. Keep admin tokens, age and blocks. Reauthorization can find the same farm. |
| `account-deleted` or legacy spelling `account-delete` | Apple-only: use shared `deleteAccount`, with no outbound Apple revoke. Another Google/email binding: preserve farm/other binding and admin token, remove only Apple, revoke user sessions and clear online access. |
| Other event | Verified but ignored; no automatic moderation/deletion. |

The dual-binding path is a preservation safeguard for existing/internal data; this does not add a new public link route.
Account invalidation writes user-token/Apple changes in one existing accounts-file write, restoring memory on write error.
The existing accounts/state JSON shapes and SAVE_VERSION do not change.

## Duplicate, late event and failure recovery

`apple-notifications.json`, beside `accounts.json`, is a new **private operational journal**, mode 0600. It stores hashed
audience/jti and event identity, a pending action's internal target/creation time, completion state, and hashed-subject
verified authorization times. It stores no raw JWS/jti/Apple sub/email/token/refresh or private signing key. Its directory
must be writable only by the server. Include it in deployment approval and the data inventory.

- A target/action is durably recorded before account mutation. Completed entries suppress duplicate work across restarts;
  same jti with conflicting verified contents is refused. Both account-deletion spellings normalize to one event kind.
- A failure stays pending. A retried signed notification can resume shared deletion even after the account/Apple index
  has disappeared. It does not mark the delivery completed before confirmed cleanup. No claim of distributed transaction
  atomicity: account/save/voice files can be partly changed on failure, and recovery preserves that fact.
- In-process duplicate deliveries share one operation. Lookup happens after async signature validation. Before applying,
  target creation, current binding, alternative sign-ins and verified Apple authorization times are checked again.
- A verified Apple ID-token **issue time** is recorded before it is used by app login/claim; receipt time is not used,
  so replaying an old ID token does not manufacture a new authorization time. Notifications predating a newer verified
  authorization are ignored even after that newer session logs out. A game's newer session token by itself is not proof
  of renewed Apple authorization: it may have been minted from a pre-event Apple token before notification delivery.
- The journal also records a hashed-subject revocation time before applying the notification. A still-unexpired Apple
  ID token issued at or before that event cannot sign in again or create a fresh pending grant; a strictly newer verified
  ID token can reauthorize. This revocation floor also survives restart.
- Apple's timestamps have second precision. A strictly later second protects a newer authorization; same-second ordering
  cannot be established and follows revocation. This limitation is explicit, not claimed as perfect event ordering.
- A farm created after a delayed deletion event is preserved, but without a newer verified Apple authorization its user
  sessions/refresh are still revoked. Pending grants from invalidated authorization are removed even if received after
  the event but before delivery; already renewed authorization keeps only grants newer than the event.
- Completed delivery records expire after their accepted issue-time window plus one day; old authorization timestamps
  are pruned on later authorization writes. Pending actions are not pruned. Cleanup is lazy on journal writes, not a new
  background retention job. Maps cap at 100,000 entries and fail closed when capacity cannot be reclaimed.
- The notification journal is copied with state/accounts into the same hourly snapshot and retained by the existing
  snapshot count. Restoring old account/state or journal independently can revive revoked/deleted identity or replay actions;
  do not do so. Any actual restore requires the approved paired-data recovery procedure.

Media release uses `voice.drop(..., {requireConfirmed:true})`; retry remains possible when the provider has not confirmed
cleanup. No new timers or background notification worker are added. After prolonged delivery failure, an operator must
investigate the journal and fixed-code logs and use the approved recovery path; do not mark pending entries done manually.

## Validation boundary

Tests use generated RSA keys, synthetic identities, local temporary files, actual Fastify route injection and fake media.
They cover signature/issuer/audience/time, missing-exp format, both deletion spellings, consent preservation, alternate
bindings, restart replay, concurrent duplicates, partial deletion, storage failure, renewed-authorization ordering,
pending grants, public route versus game-key guard, rate limiting and paired journal snapshots.

This is not real Apple login, code exchange/revoke, live media or external Apple callback delivery. The Apple A rehearsal
still waits for the user's exact approval `Apple实测A ok` and a controlled test Apple ID. No production data/key was used.

Reference: Apple Developer, [Processing changes for Sign in with Apple accounts](https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts),
official DocC reference read and archived locally on 2026-11-12 (`/tmp/sulie-apple-endpoints/notification.json`).

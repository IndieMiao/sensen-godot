import { describe, expect, it } from 'vitest';
import { ACCOUNT_LIMIT_ENV, DEFAULT_ACCOUNT_LIMITS, accountLimitsFromEnv } from '../../src/accounts/limits.js';

describe('account limits from the environment (C-132)', () => {
  it('uses the defaults when unset or empty', () => {
    expect(accountLimitsFromEnv({})).toEqual(DEFAULT_ACCOUNT_LIMITS);
    expect(accountLimitsFromEnv(Object.fromEntries(Object.values(ACCOUNT_LIMIT_ENV).map(name => [name, ''])))).toEqual(DEFAULT_ACCOUNT_LIMITS);
  });

  it('reads each limit and refuses anything but 1–1000000', () => {
    expect(accountLimitsFromEnv({ LOGIN_ATTEMPTS_PER_NETWORK_15MIN: '20', MAIL_PER_RECIPIENT_HOUR: '3', MAIL_PER_DAY: '1000000' }))
      .toEqual({ ...DEFAULT_ACCOUNT_LIMITS, loginPerNetwork: 20, mailPerRecipientHour: 3, mailPerDay: 1_000_000 });
    for (const name of Object.values(ACCOUNT_LIMIT_ENV))
      for (const bad of ['0', '-1', '1.5', 'ten', '1000001'])
        expect(accountLimitsFromEnv({ [name]: bad })).toEqual({ invalid: name });
  });
});

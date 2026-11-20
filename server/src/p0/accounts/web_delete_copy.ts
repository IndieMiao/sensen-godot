/** SGODOT-484: gensen.app/delete copy, supplied by 李白 on 2026-11-13.
 * Sources: approved q(321)–q(323), store-readiness/forced-signin/libai-testcode-copy-1113.md §4,
 * and pm/legal/store-2026-11/privacy-policy-src.html §7 (2026-11-13).
 * Render signInWithEmail only when the server enables P0_EMAIL_LOGIN; otherwise use signInWithoutEmail
 * and omit the email form. Email flow: enter address → receive/enter six-digit code → confirm deletion,
 * reusing the App's email verification service without creating an account or issuing a game session.
 * Render testCode immediately below the sign-in-and-delete explanation; earlierVersion is a separate paragraph
 * only about players of earlier versions who never signed in to the new version.
 * Link "email us" / "发邮件给我们" to supportEmail. The page and authenticated endpoint ship together on 11-18;
 * this file alone does not register a page, enable deletion or send email. */
export const WEB_DELETE_COPY = {
  supportEmail: 'shaojie@gensen.app',
  en: {
    signInWithEmail: 'Sign in the way you sign in to the game (Apple, Google, or a code sent to your email) and delete your account here.',
    signInWithoutEmail: 'Sign in the way you sign in to the game (Apple or Google) and delete your account here.',
    testCode: 'If you signed in with a test code, delete your account in the app (Settings › Delete account), or email us your support code.',
    earlierVersion: 'If you played an earlier version and never signed in to this one, we cannot tell which save is yours without the app: it is deleted automatically after 12 months without play, or email us your support code (if you still have it) and we delete it within 30 days.',
  },
  zh: {
    signInWithEmail: '用你登录游戏的方式（Apple、Google，或发到你邮箱的验证码）登录后删除账号。',
    signInWithoutEmail: '用你登录游戏的方式（Apple 或 Google）登录后删除账号。',
    testCode: '用测试码登录的账号，请在 App 内删除（设置 › Delete account），或把支持码发邮件给我们。',
    earlierVersion: '如果你玩过之前的版本、却从没登录过这个版本，没有 App 我们分不出哪份存档是你的：连续 12 个月不玩会自动删除；或者把支持码（如果还留着）发邮件给我们，我们在 30 天内删除。',
  },
} as const;

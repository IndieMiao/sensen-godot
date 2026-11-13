/** SGODOT-484: gensen.app/delete copy, supplied by 李白 on 2026-11-13.
 * Source: store-readiness/forced-signin/libai-testcode-copy-1113.md §4.
 * Render the localized testCode paragraph immediately below the Apple / Google sign-in-and-delete explanation.
 * Link "email us" / "发邮件给我们" to supportEmail. The page and authenticated endpoint ship together on 11-18;
 * this file alone does not register a page, enable deletion or send email. */
export const WEB_DELETE_COPY = {
  supportEmail: 'shaojie@gensen.app',
  en: {
    testCode: 'If you signed in with a test code, delete your account in the app (Settings › Delete account), or email us your support code.',
  },
  zh: {
    testCode: '用测试码登录的账号，请在 App 内删除（设置 › Delete account），或把支持码发邮件给我们。',
  },
} as const;

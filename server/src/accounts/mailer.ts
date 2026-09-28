/**
 * 验证码发信（SGODOT-135）。
 *
 * 生产用 SMTP（阿里云邮件推送、SES、企业邮箱都支持，香港服务器可达），SMTP_URL 配了才启用；
 * 没配时退回日志发信：开发与 pitch 阶段在服务端日志里看码。QA 域名的邮箱固定用
 * EMAIL_QA_CODE，自动化测试不依赖收信。
 */
import nodemailer from 'nodemailer';
import type { CodePurpose } from './email.js';

export interface Mailer {
  sendCode(email: string, code: string, purpose: CodePurpose): Promise<void>;
}

const SUBJECT: Record<CodePurpose, string> = { verify: 'Your Sensen verification code', reset: 'Reset your Sensen password' };
const body = (code: string, purpose: CodePurpose) =>
  `${purpose === 'verify' ? 'Use this code to verify your email' : 'Use this code to reset your password'}: ${code}\n\n`
  + 'The code expires in 10 minutes. If you did not request it, you can ignore this email.';

export function createLogMailer(log: (line: string) => void = console.log, showCodes = true): Mailer {
  return { async sendCode(email, code, purpose) { log(`[mail] ${purpose} code for ${email}: ${showCodes ? code : '******'}`); } };
}

export function createSmtpMailer(url: string, from: string): Mailer {
  const transport = nodemailer.createTransport(url);
  return {
    async sendCode(email, code, purpose) {
      await transport.sendMail({ from, to: email, subject: SUBJECT[purpose], text: body(code, purpose) });
    },
  };
}

export function mailerFromEnv(env: NodeJS.ProcessEnv): Mailer {
  if (env.SMTP_URL) return createSmtpMailer(env.SMTP_URL, env.MAIL_FROM ?? 'Sensen <no-reply@sensenjoy.cn>');
  return createLogMailer(console.log, env.EMAIL_LOG_CODES !== '0');
}

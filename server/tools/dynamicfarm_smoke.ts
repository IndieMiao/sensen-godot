/**
 * 动态农场正式服冒烟（C-96）。逻辑在 src/ops/dynamicfarm_smoke.ts；正式服用 server/deploy/dynamicfarm/ops.sh smoke 调它。
 *   --base <入口，如 http://127.0.0.1:3000/v1>  --git-sha <期望的提交号>
 *   --google <env|on|off>   服务端是否开着 Google 登录。默认 env：按本进程的 GOOGLE_CLIENT_IDS 判断，规则和服务端相同
 *                   （没设算开着，置空算关着）。ops.sh 在 app 容器里运行它，读到的就是服务端的配置（C-259）
 *   --invite-stdin   从标准输入读邀请账号（CSV，取第一条 email,password）；输入为空就跳过账号这一段
 *   --write <数据集>,<地块编号>,<经度>,<纬度>   只用于隔离环境：认领并存档，最后把读回的地块 JSON 打到标准输出
 * 账号密码不打印。任何一项不通过，退出码 1。
 */
import { parseArgs } from 'node:util';
import { firstInvite, runSmoke, type SmokeOptions } from '../src/ops/dynamicfarm_smoke.js';
import { googleClientIdsFromEnv } from '../src/accounts/google_token.js';

const { values } = parseArgs({ options: {
  base: { type: 'string' }, 'git-sha': { type: 'string' }, 'invite-stdin': { type: 'boolean', default: false }, write: { type: 'string' },
  google: { type: 'string', default: 'env' },
} });
if (!values.base) { console.error('需要 --base'); process.exit(2); }
const googleMode = values.google;
if (googleMode !== 'on' && googleMode !== 'off' && googleMode !== 'env') { console.error('--google 只能是 on、off 或 env'); process.exit(2); }
const google = googleMode === 'env' ? googleClientIdsFromEnv().length > 0 : googleMode === 'on';
if (googleMode === 'env') console.error(`Google 登录按配置判断：${google ? '开着' : '关着（GOOGLE_CLIENT_IDS 为空）'}`);

let invite: SmokeOptions['invite'];
if (values['invite-stdin']) {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(chunk as Buffer);
  invite = firstInvite(Buffer.concat(chunks).toString('utf8'));
}
let write: SmokeOptions['write'];
if (values.write) {
  const [dataset_version, parcel_id, lng, lat] = values.write.split(',');
  write = { dataset_version, parcel_id, center: [Number(lng), Number(lat)] };
}
if (write && !invite) { console.error('--write 需要邀请账号（--invite-stdin）'); process.exit(2); }

const result = await runSmoke({ base: values.base, gitSha: values['git-sha'], invite, write, google, log: line => console.error(line) });
if (write) console.log(JSON.stringify(result.farm));
console.error(result.ok ? '冒烟通过' : `冒烟失败：${result.failures.join('、')}`);
process.exitCode = result.ok ? 0 : 1;

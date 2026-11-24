/**
 * 动态农场正式服冒烟（C-96）。逻辑在 src/ops/dynamicfarm_smoke.ts；正式服用 server/deploy/dynamicfarm/ops.sh smoke 调它。
 *   --base <入口，如 http://127.0.0.1:3000/v1>  --git-sha <期望的提交号>
 *   --invite-stdin   从标准输入读邀请账号（CSV，取第一条 email,password）；输入为空就跳过账号这一段
 *   --write <数据集>,<地块编号>,<经度>,<纬度>   只用于隔离环境：认领并存档，最后把读回的地块 JSON 打到标准输出
 * 账号密码不打印。任何一项不通过，退出码 1。
 */
import { parseArgs } from 'node:util';
import { firstInvite, runSmoke, type SmokeOptions } from '../src/ops/dynamicfarm_smoke.js';

const { values } = parseArgs({ options: {
  base: { type: 'string' }, 'git-sha': { type: 'string' }, 'invite-stdin': { type: 'boolean', default: false }, write: { type: 'string' },
} });
if (!values.base) { console.error('需要 --base'); process.exit(2); }

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

const result = await runSmoke({ base: values.base, gitSha: values['git-sha'], invite, write, log: line => console.error(line) });
if (write) console.log(JSON.stringify(result.farm));
console.error(result.ok ? '冒烟通过' : `冒烟失败：${result.failures.join('、')}`);
process.exitCode = result.ok ? 0 : 1;

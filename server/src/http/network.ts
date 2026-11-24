/**
 * “同一个网络”的键（C-100：匿名建号每个网络每小时 10 次）。
 * IPv4 按整个地址算；IPv6 一户人家通常分到一整段 /64，段内换地址不费任何成本，所以按前 64 位算。
 * IPv4 映射地址（::ffff:a.b.c.d）按其中的 IPv4 地址算，免得同一个来源换个写法就成了另一个网络。
 */
import { isIPv4, isIPv6 } from 'node:net';

export function networkKey(ip: string): string {
  const bare = ip.replace(/%.*$/, ''); // 区域标识（fe80::1%eth0）不区分网络
  if (isIPv4(bare)) return bare;
  if (!isIPv6(bare)) return 'other:' + ip;
  const groups = expandIPv6(bare);
  if (groups.slice(0, 5).every(g => g === 0) && groups[5] === 0xffff)
    return [groups[6] >> 8, groups[6] & 255, groups[7] >> 8, groups[7] & 255].join('.');
  return groups.slice(0, 4).map(g => g.toString(16)).join(':') + '::/64';
}

/** 八组 16 位数；输入已由 isIPv6 校验过。 */
function expandIPv6(ip: string): number[] {
  let text = ip.toLowerCase();
  const tail = /(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(text);
  if (tail) {
    const [a, b, c, d] = tail.slice(1).map(Number);
    text = text.slice(0, tail.index) + ((a << 8) | b).toString(16) + ':' + ((c << 8) | d).toString(16);
  }
  const [head, rest] = text.split('::');
  const left = head ? head.split(':') : [];
  const right = rest !== undefined && rest ? rest.split(':') : [];
  const fill = rest === undefined ? [] : Array(8 - left.length - right.length).fill('0');
  return [...left, ...fill, ...right].map(g => parseInt(g, 16));
}

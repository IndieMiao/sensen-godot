/** q(281): a locator, never an authentication credential. Matches P0Legal.support_code. */
import { createHash } from 'node:crypto';

const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export function supportCode(player: string): string {
  if (!player) return '';
  const bits = createHash('sha256').update('p0-support/v1/' + player, 'utf8').digest().readBigUInt64BE() >> 14n;
  let code = '';
  for (let shift = 45; shift >= 0; shift -= 5) code += CROCKFORD[Number((bits >> BigInt(shift)) & 31n)];
  return code.slice(0, 5) + '-' + code.slice(5);
}

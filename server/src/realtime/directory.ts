import { randomBytes, randomUUID } from 'node:crypto';
import { CAPACITY, type DirectoryAction, type DirectoryEntry, type DirectoryPlayer, type Party } from './model.js';

/** Mutate only a transaction-owned draft. Membership never changes a mine binding. */
export function changeDirectory(players: Map<string, DirectoryPlayer>, parties: Map<string, Party>,
  player: string, action: DirectoryAction = 'get', value = ''): DirectoryEntry {
  const entry = players.get(player) ?? { instance: '', party: '' };
  players.set(player, entry);
  let party = parties.get(entry.party);
  const fail = (code: string): never => { throw new Error(code); };
  if (action === 'create') {
    if (party) fail('ALREADY_IN_PARTY');
    party = { id: randomUUID(), code: randomBytes(6).toString('hex').toUpperCase(), leader: player, members: [player] };
    parties.set(party.id, party);
    entry.party = party.id;
  } else if (action === 'join') {
    if (party) fail('ALREADY_IN_PARTY');
    party = [...parties.values()].find(p => p.code === value.toUpperCase());
    if (!party) fail('PARTY_NOT_FOUND');
    if (party!.members.length >= CAPACITY) fail('PARTY_FULL');
    party!.members.push(player);
    entry.party = party!.id;
  } else if (action === 'leave' || action === 'kick') {
    if (!party) fail('PARTY_NOT_FOUND');
    const target = action === 'leave' ? player : value;
    if (action === 'kick' && (party!.leader !== player || target === player)) fail('NOT_LEADER');
    if (!party!.members.includes(target)) fail('PARTY_NOT_FOUND');
    party!.members = party!.members.filter(id => id !== target);
    const removed = players.get(target);
    if (removed) { removed.party = ''; removed.farm_access = ''; }
    if (!party!.members.length) parties.delete(party!.id);
    else if (party!.leader === target) party!.leader = party!.members[0];
  } else if (action === 'disband') {
    if (!party || party.leader !== player) fail('NOT_LEADER');
    for (const id of party!.members) {
      const member = players.get(id);
      if (member) { member.party = ''; member.farm_access = ''; }
    }
    parties.delete(party!.id);
  } else if (action === 'leader') {
    if (!party || party.leader !== player) fail('NOT_LEADER');
    if (!party!.members.includes(value)) fail('PARTY_NOT_FOUND');
    party!.leader = value;
  } else if (action === 'farm_access') {
    if (!party) fail('PARTY_NOT_FOUND');
    if (!['allow', 'deny'].includes(value)) fail('SCHEMA');
    entry.farm_access = value === 'allow' ? party!.id : '';
  } else if (action === 'bind') {
    if (!/^[0-9a-f-]{36}$/.test(value)) fail('SCHEMA');
    entry.instance = value;
  }
  const current = parties.get(entry.party) ?? null;
  return structuredClone({ instance: entry.instance, party: current, farm_access: Boolean(current && entry.farm_access === current.id) });
}

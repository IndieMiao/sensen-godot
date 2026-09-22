/** Second real HTTP/WS QA client. Walks through the public navigation and never changes DB state directly. */
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { Client } from '../test/realtime/helpers.js';
import { defaultFishingTarget, validFishingCast, initialFishingSimulation, stepFishing, type FishingPoint } from '../src/domain/fishing.js';
import { segment, walkable, type Navigation } from '../src/realtime/model.js';
import { loadContent, DEFAULT_CONTENT_DIR } from '../src/domain/content.js';
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
export async function fishingPeer(folder: string, near: FishingPoint, site = 'farm_pond') {
  const account = JSON.parse(await readFile(folder + '/peer.json', 'utf8'));
  const host = JSON.parse(await readFile(folder + '/account.json', 'utf8'));
  const content = loadContent(DEFAULT_CONTENT_DIR), spec = content.fishing.sites[site];
  const client = new Client('ws://127.0.0.1:3181/v1/online');
  await client.connect(account.token);
  await client.join(spec.space, spec.space === 'farm' ? { farm_id: host.farm.id } : { region: host.farm.region_id, layout: host.farm.layout_patch_id, revision: 2 });
  const world = await client.next('world'), nav = world.navigation as Navigation;
  let position = client.joined.spawn as FishingPoint, target: FishingPoint = [...position], seq = 0, held = false, fish = .5, fishingSequence = 0, stopped = false;
  client.ws.on('message', (raw, binary) => {
    if (!binary) return;
    const b = Buffer.from(raw as Buffer);
    for (let i = 0; i < b.readUInt16LE(10); i++) { const off = 12 + 26 * i;
      if (b.readUInt16LE(off) === client.joined.self) position = [b.readFloatLE(off + 2), b.readFloatLE(off + 6)];
    }
  });
  const input = setInterval(() => { if (!stopped) client.send({ t: 'input', epoch: client.joined.epoch, seq: ++seq, x: target[0], z: target[1], yaw: 0, fishing: { sequence: fishingSequence, held, fish } }); }, 50);
  const candidates: FishingPoint[] = [];
  for (let y = 0; y < nav.rows.length; y++) for (let x = 0; x < nav.rows[y].length; x++) {
    const p: FishingPoint = [(x + .5) * nav.cell, -(y + .5) * nav.cell], d = Math.hypot(p[0] - near[0], p[1] - near[1]);
    if (d > .7 && d < 3 && validFishingCast(spec, p, defaultFishingTarget(spec, p), content.fishing, q => walkable(nav, q))) candidates.push(p);
  }
  candidates.sort((a,b) => Math.hypot(a[0]-near[0],a[1]-near[1])-Math.hypot(b[0]-near[0],b[1]-near[1]));
  const destination = candidates[0];
  if (!destination) { clearInterval(input); client.close(); throw Error('No adjacent shoreline'); }
  const width = nav.rows[0].length, cell = (p: FishingPoint) => Math.floor(-p[1] / nav.cell) * width + Math.floor(p[0] / nav.cell);
  const start = cell(position), end = cell(destination), queue = [start], prev = new Map<number, number>([[start, -1]]);
  for (let i = 0; i < queue.length; i++) { const n = queue[i]; if (n === end) break;
    for (const [dx,dy] of [[1,0],[-1,0],[0,1],[0,-1]]) { const x=n%width+dx, y=Math.floor(n/width)+dy, id=y*width+x;
      if (x>=0&&x<width&&nav.rows[y]?.[x]==='1'&&!prev.has(id)) {prev.set(id,n);queue.push(id);} }
  }
  if (!prev.has(end)) { clearInterval(input); client.close(); throw Error('Peer cannot reach shore'); }
  const points: FishingPoint[] = [destination]; let n=end;
  while (prev.get(n)!>=0) {n=prev.get(n)!;points.unshift([(n%width+.5)*nav.cell,-(Math.floor(n/width)+.5)*nav.cell]);}
  let index=0;
  const timeout=Date.now()+40000;
  while (index<points.length && Date.now()<timeout) {
    let next=points.length-1;while(next>index&&!segment(nav,position,points[next]))next--;
    target=points[next];
    if(Math.hypot(position[0]-target[0],position[1]-target[1])<.08)index=next+1;
    await delay(60);
  }
  if(index<points.length) {clearInterval(input);client.close();throw Error('Peer walk timeout');}
  let farm: any;
  const refresh=async()=> {const r=await fetch('http://127.0.0.1:3181/v1/farms/me',{headers:{authorization:`Bearer ${account.token}`}});farm=await r.json();};
  const command=async(type:string,payload:object)=> {await refresh();const r=await fetch('http://127.0.0.1:3181/v1/farms/me/commands',{method:'POST',headers:{authorization:`Bearer ${account.token}`,'content-type':'application/json'},body:JSON.stringify({type,payload,idempotency_key:randomUUID(),base_version:farm.version})});const result=await r.json() as any;if(!r.ok)throw Error(type+': '+result.code);farm=result;return result;};
  let result: any, error: unknown;
  const play=async()=> {
    await refresh(); if(farm.state.fishing?.active)await command('cancel_fishing',{sequence:farm.state.fishing.sequence});
    const cast=await command('cast_fishing',{sequence:farm.state.fishing?.sequence??0,site_id:site,target:defaultFishingTarget(spec,position)});
    fishingSequence=cast.state.fishing.sequence;const active=cast.state.fishing.active;
    await delay(Math.max(0,active.bite_at-Date.now())+80);if(stopped)return;
    await command('hook_fishing',{sequence:fishingSequence});const began=Date.now();
    const simulation=initialFishingSimulation(active.seed,content.fishing);let inputs='';
    while(!stopped&&simulation.outcome==='playing') {held=simulation.fish>simulation.bar+simulation.velocity*.15;inputs+=held?'1':'0';stepFishing(simulation,held,content.fishing.tiers[String(content.fishing.fish[active.fish_id].tier)],content.fishing);fish=simulation.fish;await delay(Math.max(1,began+inputs.length*50-Date.now()));}
    held=false;if(!stopped)result=await command('finish_fishing',{sequence:fishingSequence,inputs});
  };
  const playing=play().catch(e=>{error=e;});
  return { position: destination, id: client.joined.self, get result(){return result;}, get error(){return error;}, async close(){stopped=true;clearInterval(input);await playing;client.close();} };
}

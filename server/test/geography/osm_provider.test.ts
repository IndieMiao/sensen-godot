import { afterEach, describe, expect, it, vi } from 'vitest';
import { createOsmProvider, type OsmDiagnostic } from '../../src/geography/osm.js';
import { CENTER, rectangle } from './fixtures.js';
const geometry = rectangle(-100,-100,300,300).map(([lon,lat])=>({lon,lat}));
const body=(id=1)=>JSON.stringify({elements:[{type:'way',id,tags:{landuse:'farmland'},geometry}]});
const primary='https://overpass-api.de/api/interpreter',fallback='https://overpass.kumi.systems/api/interpreter';
const custom='https://configured.invalid/interpreter';
afterEach(()=>{vi.useRealTimers();vi.unstubAllEnvs();});
describe('bounded real OSM response caching',()=>{
 it('coalesces concurrent identical selections, caches successes and isolates every caller clone',async()=>{
  let finish!:(response:Response)=>void,calls=0;
  const provider=createOsmProvider({endpoint:custom,fetcher:async()=>{calls++;return new Promise<Response>(resolve=>finish=resolve);}});
  const first=provider(CENTER,240),second=provider({...CENTER},240);expect(calls).toBe(1);
  finish(new Response(body()));const [a,b]=await Promise.all([first,second]);expect(a).toEqual(b);expect(a).not.toBe(b);
  a.features[0].polygon![0][0]=999;a.features.splice(0,1);
  expect(b.features).toHaveLength(1);expect(b.features[0].polygon![0][0]).not.toBe(999);
  const cached=await provider(CENTER,240);expect(cached).toEqual(b);expect(cached.features).not.toBe(b.features);expect(calls).toBe(1);
 });
 it('expires after five minutes even if read repeatedly, and never serves expired data after a failed refresh',async()=>{
  let time=0,calls=0,fail=false;
  const provider=createOsmProvider({endpoint:custom,now:()=>time,fetcher:async()=>{calls++;return fail?new Response('',{status:503}):new Response(body(calls));}});
  const first=await provider(CENTER,240);time=299999;expect(await provider(CENTER,240)).toEqual(first);expect(calls).toBe(1);
  time=300000;fail=true;await expect(provider(CENTER,240)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');expect(calls).toBe(2);
  fail=false;const refreshed=await provider(CENTER,240);expect(calls).toBe(3);expect(refreshed.source_checksum).not.toBe(first.source_checksum);
 });
 it('retains at most eight successful entries and uses least-recently-used eviction',async()=>{
  const hits=new Map<string,number>();
  const provider=createOsmProvider({endpoint:custom,fetcher:async(_url,init)=>{const key=String(init!.body);hits.set(key,(hits.get(key)??0)+1);return new Response(body());}});
  const places=Array.from({length:9},(_,i)=>({...CENTER,lat:CENTER.lat+i*.01}));
  for(const place of places.slice(0,8))await provider(place,240);
  await provider(places[0],240);await provider(places[8],240);await provider(places[0],240);
  expect([...hits.values()].reduce((a,b)=>a+b,0)).toBe(9);
  await provider(places[1],240);expect([...hits.values()].reduce((a,b)=>a+b,0)).toBe(10);
 });
 it('keys exact coordinates and extent, without rounding nearby points into the same selection',async()=>{
  let calls=0;const provider=createOsmProvider({endpoint:custom,fetcher:async()=>{calls++;return new Response(body());}});
  await provider(CENTER,240);await provider({...CENTER,lat:CENTER.lat+1e-9},240);await provider({...CENTER,lng:CENTER.lng+1e-9},240);await provider(CENTER,241);
  expect(calls).toBe(4);await provider(CENTER,240);expect(calls).toBe(4);
 });
 it('does not cache failed parsing or a failed shared request and clears pending requests for retry',async()=>{
  let finish!:(response:Response)=>void,calls=0;
  const provider=createOsmProvider({endpoint:custom,fetcher:async()=>{calls++;if(calls===1)return new Promise<Response>(resolve=>finish=resolve);return new Response(body());}});
  const first=provider(CENTER,240),second=provider(CENTER,240);
  const outcomes=Promise.allSettled([first,second]);finish(new Response(JSON.stringify({elements:[],remark:'upstream timeout'})));
  expect((await outcomes).map(result=>result.status)).toEqual(['rejected','rejected']);expect(calls).toBe(1);
  expect((await provider(CENTER,240)).features[0].kind).toBe('land');expect(calls).toBe(2);
 });
 it('honors cache TTL/capacity overrides and permits disabling persistent caching while retaining coalescing',async()=>{
  let calls=0,time=0;const provider=createOsmProvider({endpoint:custom,cacheTtlMs:10,maxCacheEntries:1,now:()=>time,fetcher:async()=>{calls++;return new Response(body());}});
  await provider(CENTER,240);time=10;await provider(CENTER,240);await provider({...CENTER,lat:CENTER.lat+.01},240);await provider(CENTER,240);expect(calls).toBe(4);
  const uncached=createOsmProvider({endpoint:custom,cacheTtlMs:0,fetcher:async()=>{calls++;return new Response(body());}});
  await Promise.all([uncached(CENTER,240),uncached(CENTER,240)]);expect(calls).toBe(5);await uncached(CENTER,240);expect(calls).toBe(6);
 });
});

describe('OSM endpoints and bounded deadlines',()=>{
 it('uses the known fallback only for the unconfigured default, and caches successful real fallback data',async()=>{
  vi.stubEnv('GEOGRAPHY_OVERPASS_URL',undefined);const urls:string[]=[],diagnostics:OsmDiagnostic[]=[];
  const provider=createOsmProvider({fetcher:async url=>{urls.push(String(url));return urls.length===1?new Response('',{status:429}):new Response(body());},onDiagnostic:event=>diagnostics.push(event)});
  const result=await provider(CENTER,240);expect(result.provider).toBe('osm');expect(urls).toEqual([primary,fallback]);
  expect(diagnostics).toEqual([{endpoint_index:0,reason:'http',http_status:429}]);await provider(CENTER,240);expect(urls).toHaveLength(2);
 });
 it.each(['option','environment'] as const)('honors an explicit %s endpoint without contacting the fallback',async(kind)=>{
  vi.stubEnv('GEOGRAPHY_OVERPASS_URL',kind==='environment'?custom:'https://ignored.invalid/token-secret');const urls:string[]=[];
  const provider=createOsmProvider({...(kind==='option'?{endpoint:custom}:{}),fetcher:async url=>{urls.push(String(url));return new Response('',{status:503});}});
  await expect(provider(CENTER,240)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');expect(urls).toEqual([custom]);
 });
 it('bounds both stalled endpoints by one overall deadline, even when the fetcher ignores abort',async()=>{
  vi.stubEnv('GEOGRAPHY_OVERPASS_URL',undefined);vi.useFakeTimers();const started=Date.now(),urls:string[]=[],signals:AbortSignal[]=[],diagnostics:OsmDiagnostic[]=[];
  const provider=createOsmProvider({timeoutMs:100,fetcher:async(url,init)=>{urls.push(String(url));signals.push(init!.signal!);return new Promise<Response>(()=>{});},onDiagnostic:event=>diagnostics.push(event)});
  const result=provider(CENTER,240).then(()=> 'success',error=>error.message);
  await vi.advanceTimersByTimeAsync(49);expect(urls).toEqual([primary]);
  await vi.advanceTimersByTimeAsync(1);expect(urls).toEqual([primary,fallback]);expect(signals[0].aborted).toBe(true);
  await vi.advanceTimersByTimeAsync(50);expect(await result).toBe('GEOGRAPHY_UNAVAILABLE');expect(Date.now()-started).toBe(100);expect(signals.every(signal=>signal.aborted)).toBe(true);
  expect(diagnostics).toEqual([{endpoint_index:0,reason:'timeout'},{endpoint_index:1,reason:'timeout'}]);expect(vi.getTimerCount()).toBe(0);
 });
 it('uses only the remaining overall budget after a delayed first failure',async()=>{
  vi.stubEnv('GEOGRAPHY_OVERPASS_URL',undefined);vi.useFakeTimers();let calls=0;
  const provider=createOsmProvider({timeoutMs:100,fetcher:async()=>{calls++;if(calls===1)return new Promise<Response>(resolve=>setTimeout(()=>resolve(new Response('',{status:504})),40));return new Promise<Response>(()=>{});}});
  const outcome=provider(CENTER,240).then(()=> 'success',error=>error.message);await vi.advanceTimersByTimeAsync(40);expect(calls).toBe(2);
  await vi.advanceTimersByTimeAsync(60);expect(await outcome).toBe('GEOGRAPHY_UNAVAILABLE');expect(vi.getTimerCount()).toBe(0);
 });
 it('gives a configured endpoint the full custom deadline and cancels a stalled body',async()=>{
  vi.useFakeTimers();let cancelled=false,calls=0;
  const provider=createOsmProvider({endpoint:custom,timeoutMs:80,fetcher:async()=>{calls++;return new Response(new ReadableStream({start(controller){controller.enqueue(new TextEncoder().encode('{'));},cancel(){cancelled=true;}}));}});
  const result=provider(CENTER,240).then(()=> 'success',error=>error.message);
  await vi.advanceTimersByTimeAsync(79);expect(cancelled).toBe(false);await vi.advanceTimersByTimeAsync(1);
  expect(await result).toBe('GEOGRAPHY_UNAVAILABLE');expect(cancelled).toBe(true);expect(calls).toBe(1);expect(vi.getTimerCount()).toBe(0);
 });
 it.each([['invalid_json','{oops'],['invalid_data',JSON.stringify({elements:[]})],['response_too_large','x'.repeat(40)]] as const)('reports %s internally without leaking query or source credentials',async(reason,text)=>{
  const diagnostics:OsmDiagnostic[]=[];const provider=createOsmProvider({endpoint:custom+'?secret=not-for-logs',maxBytes:32,fetcher:async()=>new Response(text),onDiagnostic:event=>diagnostics.push(event)});
  await expect(provider(CENTER,240)).rejects.toThrow('GEOGRAPHY_UNAVAILABLE');expect(diagnostics).toEqual([{endpoint_index:0,reason}]);
 });
 it('does not let a diagnostic callback failure disable the fallback',async()=>{
  vi.stubEnv('GEOGRAPHY_OVERPASS_URL',undefined);let calls=0;const provider=createOsmProvider({fetcher:async()=>{if(calls++===0)throw new Error('network internal details');return new Response(body());},onDiagnostic:()=>{throw new Error('logging failed');}});
  expect((await provider(CENTER,240)).features[0].kind).toBe('land');expect(calls).toBe(2);
 });
});

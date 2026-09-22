import http from 'node:http';
import {writeFile} from 'node:fs/promises';

const output='output/combat-latency-emulator-2026-09-15/proxy-report.json';
let delayMs=600;
const events=[];
const server=http.createServer(async(req,res)=>{
  try{
    const chunks=[];
    for await(const chunk of req)chunks.push(chunk);
    const body=Buffer.concat(chunks);
    if(req.url==='/latency'){
      if(req.method==='POST'){
        const value=JSON.parse(body.toString()).delay_ms;
        if(!Number.isInteger(value)||value<0||value>5000)throw new Error('Invalid delay');
        delayMs=value;
      }
      res.setHeader('content-type','application/json');
      res.end(JSON.stringify({delay_ms:delayMs,events}));return;
    }
    const started=Date.now();
    let command;
    if(req.method==='POST'&&req.url==='/v1/farms/me/commands')command=JSON.parse(body.toString());
    const response=await fetch('http://127.0.0.1:3155'+req.url,{method:req.method,
      headers:{'content-type':'application/json',...(req.headers.authorization?{authorization:req.headers.authorization}:{})},
      ...(body.length?{body}:{}),signal:AbortSignal.timeout(12000)});
    const bytes=Buffer.from(await response.arrayBuffer());
    if(command?.type==='mine_combat'){
      const upstream=Date.now();
      await new Promise(resolve=>setTimeout(resolve,delayMs));
      const result=JSON.parse(bytes.toString());
      events.push({started,upstream,returned:Date.now(),delay_ms:delayMs,status:response.status,
        outcome:result.outcome,sequence:command.payload.sequence,targets:command.payload.targets,hurt_by:command.payload.hurt_by,
        hp:result.state?.character?.hp,monsters:result.state?.mine?.combat?.monsters,version:result.version});
      if(events.length>200)events.shift();
      await writeFile(output,JSON.stringify({artificial_latency:true,delay_ms:delayMs,events},null,2));
    }
    res.writeHead(response.status,{'content-type':'application/json'});res.end(bytes);
  }catch(error){res.writeHead(502,{'content-type':'application/json'});res.end(JSON.stringify({code:'QA_PROXY',message:error.message}));}
});
server.listen(3156,'127.0.0.1',()=>console.log('COMBAT_LATENCY_PROXY 3156 -> 3155, response delay 600 ms'));
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));

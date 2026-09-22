import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {parseEnv} from 'node:util';
import pg from 'pg';
import {migrate} from '../src/db/migrate.js';
import {migrateDomain} from '../src/db/domain_migration.js';
import {contentVersion,DEFAULT_CONTENT_DIR,loadContent} from '../src/domain/content.js';
import {initialMineState} from '../src/domain/mining.js';
import {ensureMineCombat} from '../src/domain/combat.js';
import {characterStats} from '../src/domain/character.js';

const mode=process.argv[2];
if(!['copy','repair-sequence','monsters','rocks','boss','boss-finish'].includes(mode))throw Error('Use copy, repair-sequence, monsters, rocks, boss or boss-finish');
const database='sensen_farm_journey_mine_routes_emulator_20260915';
const address=new URL(parseEnv(readFileSync(new URL('../.env',import.meta.url),'utf8')).TEST_DATABASE_URL);
const dir=new URL('../../output/mine-routes-emulator-2026-09-15/private/',import.meta.url);
mkdirSync(dir,{recursive:true,mode:0o700});
const content=loadContent(DEFAULT_CONTENT_DIR),cv=contentVersion(DEFAULT_CONTENT_DIR);
if(mode==='copy'){
  const admin=new pg.Pool({connectionString:address.toString(),max:1});
  try{
    if((await admin.query('SELECT 1 FROM pg_database WHERE datname=$1',[database])).rowCount)throw Error('QA copy already exists');
    await admin.query(`CREATE DATABASE "${database}"`);
  }finally{await admin.end();}
  address.pathname='/sensen_farm_journey_combat_emulator_20260915';
  const source=new pg.Pool({connectionString:address.toString(),max:1});
  address.pathname='/'+database;
  const target=new pg.Pool({connectionString:address.toString(),max:1});
  try{
    await migrate(target);
    await source.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    await target.query('BEGIN');
    const counts:Record<string,number>={};
    for(const table of ['players','tokens','farms','farm_creations','commands','farm_snapshots']){
      const columns=(await source.query('SELECT column_name,data_type FROM information_schema.columns WHERE table_schema=$1 AND table_name=$2 ORDER BY ordinal_position',['public',table])).rows;
      const rows=(await source.query(`SELECT * FROM "${table}"`)).rows;
      const names=columns.map(c=>`"${c.column_name}"`).join(',');
      for(const row of rows)await target.query(`INSERT INTO "${table}" (${names}) VALUES (${columns.map((_,i)=>'$'+(i+1)).join(',')})`,
        columns.map(c=>row[c.column_name]!==null&&['json','jsonb'].includes(c.data_type)?JSON.stringify(row[c.column_name]):row[c.column_name]));
      counts[table]=rows.length;
    }
    await target.query("SELECT setval(pg_get_serial_sequence('commands','id'),COALESCE((SELECT max(id) FROM commands),1),EXISTS(SELECT 1 FROM commands))");
    await target.query('COMMIT');await source.query('COMMIT');
    const report=await migrateDomain(target,{contentVersion:cv,previousContentVersion:'357a6d361d4c7ab6',apply:true});
    if(report.status!=='applied')throw Error('QA domain upgrade refused');
    writeFileSync(new URL('copy.json',dir),JSON.stringify({counts,migration:report},null,2),{mode:0o600});
    console.log(JSON.stringify({copied:true,database,counts,domain:report.to_domain_version,content:cv}));
  }finally{await source.end();await target.end();}
}else if(mode==='repair-sequence'){
  address.pathname='/'+database;
  const pool=new pg.Pool({connectionString:address.toString(),max:1});
  try{
    await pool.query("SELECT setval(pg_get_serial_sequence('commands','id'),COALESCE((SELECT max(id) FROM commands),1),EXISTS(SELECT 1 FROM commands))");
    console.log('QA command sequence synchronized');
  }finally{await pool.end();}
}else{
  address.pathname='/'+database;
  const pool=new pg.Pool({connectionString:address.toString(),max:1});
  try{
    await pool.query('BEGIN');
    const rows=(await pool.query("SELECT f.* FROM farms f JOIN players p ON p.id=f.owner_id WHERE p.install_key_hmac NOT LIKE 'preset:%' FOR UPDATE OF f")).rows;
    if(rows.length!==1)throw Error('Expected one ordinary QA farm');
    const row=rows[0],state=structuredClone(row.state);
    if(row.domain_version!=='20'||row.content_version!==cv)throw Error('Wrong QA versions');
    const stamp=new Date().toISOString().replaceAll(':','-');
    writeFileSync(new URL(`${stamp}-${mode}-before.json`,dir),JSON.stringify(row,null,2),{mode:0o600,flag:'wx'});
    const floor=mode==='monsters'?3:mode==='rocks'?4:5;
    state.mine={...initialMineState(),run:state.mine.run+1,floor,deepest_floor:5,elevator_unlocked:row.state.mine.elevator_unlocked};
    ensureMineCombat(state.mine,content);
    if(mode==='rocks')state.mine.broken['4']=content.mining.rocks.slice(0,5).map(r=>r.id);
    if(mode==='boss-finish'){
      state.mine.combat.monsters['5']=[20];
      state.mine.elevator_unlocked=false;
    }
    state.character.hp=characterStats(state,content).max_hp;
    const version=(await pool.query('UPDATE farms SET state=$1,version=version+1 WHERE id=$2 RETURNING version',[state,row.id])).rows[0].version;
    await pool.query('COMMIT');
    console.log(JSON.stringify({artificial_fixture:true,mode,farm_id:row.id,version,hp:state.character.hp,monster_hp:state.mine.combat.monsters[String(floor)]}));
  }catch(error){await pool.query('ROLLBACK');throw error;}finally{await pool.end();}
}

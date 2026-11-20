// No listeners: independently run the reviewed host inventory gate on author output.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {admittedManifestPath} from '../hosting/static_layout.mjs';
import {validateInventory} from '../hosting/validate_inventory.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../generated');
const read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8'));
const manifest=read('manifest.json');
for(const name of Object.keys(manifest.files))if(!admittedManifestPath(name))throw new Error('receiver_path_rejected:'+name);
const result=validateInventory({manifest,catalog:read('parcel-catalog.json'),included:read('included-parcels.json'),excluded:read('excluded-parcels.json'),aliases:read('alias-map.json'),raw:read('raw-record-rejections.json'),input:read('input-parcels.json'),farms:fs.readdirSync(path.join(root,'farms')).map(x=>x.slice(0,-5))});
console.log(JSON.stringify({static_layout_admitted_all:true,node_version:process.version,source_set_verified:result.source_set_verified,included_count:result.ids.size,excluded_count:result.excluded_count,alias_count:result.alias_count,validator:'reviewed hosting/validate_inventory.mjs',scope:'offline exact inventory; host runtime/full farm gate remains deployment evidence'}));

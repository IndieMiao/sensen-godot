/**
 * q(210): the country names a city row and the silhouette card write — Unicode CLDR's English names, by country code,
 * for the codes the city directory has — into the content (assets/p0/content/travel_p2.json, travel.country_names and
 * travel.city_only_countries), once, so neither the server nor the client depends on a CLDR package.
 *   npx tsx tools/build_country_names.ts <cldr-json 48.2.0 cldr-localenames-full/main/en/territories.json>
 * The exceptions are CLDR's own other forms (q(210) ②): Hong Kong and Macao their short names, the two Congos
 * `Congo (DRC)` / `Congo (Republic)`, Myanmar its short name, Cabo Verde the variant. City name only (q(210) ② ③):
 * Hong Kong, Macao, Taiwan, the Palestinian Territories, Kosovo and Western Sahara.
 */
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const VERSION = '48.2.0';
const ALT: Record<string, string> = { HK: 'HK-alt-short', MO: 'MO-alt-short', CD: 'CD-alt-variant', CG: 'CG-alt-variant',
  MM: 'MM-alt-short', CV: 'CV-alt-variant' };
const CITY_ONLY = ['HK', 'MO', 'TW', 'PS', 'XK', 'EH'];

const src = process.argv[2];
if (!src) { console.log('usage: npx tsx tools/build_country_names.ts <territories.json>'); process.exit(2); }
const raw = readFileSync(src);
const cldr = JSON.parse(raw.toString('utf8')).main.en.localeDisplayNames.territories as Record<string, string>;
const clusters = JSON.parse(readFileSync(path.join(ROOT, 'assets/p0/city_clusters.json'), 'utf8')) as { fields: string[]; rows: unknown[][] };
const cc = clusters.fields.indexOf('country_code');
const codes = [...new Set(clusters.rows.map(r => String(r[cc])))].sort();
const names: Record<string, string> = {};
const missing: string[] = [];
for (const code of [...new Set([...codes, ...CITY_ONLY])].sort()) {
  const name = cldr[ALT[code] ?? code];
  if (name) names[code] = name; else missing.push(code);
}
const file = path.join(ROOT, 'assets/p0/content/travel_p2.json');
const content = JSON.parse(readFileSync(file, 'utf8'));
content.travel.country_names = names;
content.travel._country_names = `q(210): the country name a city row and the silhouette card write, by country code: Unicode CLDR ${VERSION} English (cldr-json cldr-localenames-full main/en territories.json, sha256 ${createHash('sha256').update(raw).digest('hex').slice(0, 16)}…; Unicode License v3, credited in Settings › Licenses), the codes the city directory has; CLDR's other forms for Hong Kong, Macao, the two Congos, Myanmar and Cabo Verde (q(210) ②). Written by server/tools/build_country_names.ts.`;
content.travel.city_only_countries = CITY_ONLY;
content.travel._city_only_countries = 'q(210) ② ③: places whose cities read their name alone, no country (Hong Kong, Macao; Taiwan, the Palestinian Territories, Kosovo, Western Sahara — the user chose city name only).';
writeFileSync(file, JSON.stringify(content, null, 2) + '\n');
console.log(`${Object.keys(names).length} names${missing.length ? `; not in CLDR: ${missing.join(', ')}` : ''}`);

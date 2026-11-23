/** Side-by-side SVG of an older farm and the new one, with the source footprints drawn on top. */
import { rotate, toUtm, type Polygon } from './geo.js';

type Farm = Record<string, any>;

const COLORS: Record<string, string> = { core0: '#D8BF8D', ext1: '#8FAD69', ext2: '#BBA882', core2: '#BBA882' };

function panel(farm: Farm, x0: number, y0: number, size: number, footprints: Polygon[] | null, title: string): string {
  const w = farm.grid.width as number;
  const h = farm.grid.height as number;
  const px = Math.min(size / w, size / h);
  const prot = new Set<string>();
  for (const [y, x, n] of farm.walk_reserve.no_solid_decor_runs as number[][]) for (let i = 0; i < n; i++) prot.add(`${x + i},${y}`);
  const parts: string[] = [];
  // Grid +y is north: draw it upward.
  const sx = (gx: number) => (x0 + gx * px).toFixed(2);
  const sy = (gy: number) => (y0 + size - gy * px).toFixed(2);
  for (const zone of ['core', 'extension']) {
    for (const [y, x, n, s] of farm.zones[zone].runs as number[][]) {
      for (let i = 0; i < n; i++) {
        const key = `${zone === 'core' ? 'core' : 'ext'}${s}`;
        const fill = COLORS[key] ?? '#999';
        const dim = zone === 'extension' && prot.has(`${x + i},${y}`) ? ' fill-opacity="0.75"' : '';
        parts.push(`<rect x="${sx(x + i)}" y="${sy(y + 1)}" width="${px.toFixed(2)}" height="${px.toFixed(2)}" fill="${fill}"${dim}/>`);
      }
    }
  }
  for (const poly of farm.boundaries.core as { outer: number[][]; holes: number[][][] }[]) {
    for (const ring of [poly.outer, ...poly.holes]) {
      parts.push(`<polyline points="${ring.map(([x, y]) => `${sx(x)},${sy(y)}`).join(' ')}" fill="none" stroke="#6B4F2A" stroke-width="1.2"/>`);
    }
  }
  if (footprints) {
    const t = farm.source_transform;
    const cell = farm.source_cell_m as number;
    for (const poly of footprints) for (const ring of poly) {
      const pts = ring.map(([lon, lat]) => {
        const [e, n] = toUtm(lon, lat);
        const [u, v] = rotate([e - t.origin_m[0], n - t.origin_m[1]], t.rotation_deg);
        return `${sx(u / cell)},${sy(v / cell)}`;
      });
      parts.push(`<polyline points="${pts.join(' ')}" fill="none" stroke="#C0392B" stroke-width="1.6" stroke-dasharray="4 2"/>`);
    }
  }
  const [spx, spy] = farm.walk_reserve.spawn_cell as number[];
  const [enx, eny] = farm.walk_reserve.entry_cell as number[];
  parts.push(`<circle cx="${sx(spx + 0.5)}" cy="${sy(spy + 0.5)}" r="${Math.max(px * 0.6, 3).toFixed(2)}" fill="#2E86C1"/>`);
  parts.push(`<rect x="${sx(enx)}" y="${sy(eny + 1)}" width="${px.toFixed(2)}" height="${px.toFixed(2)}" fill="#8E44AD"/>`);
  const c = farm.counts;
  const lines = [
    title,
    `core ${c.core_cell_count} · extension ${c.extension_cell_count} · total ${c.total_cell_count}`,
    `cell ${Number(farm.source_cell_m).toFixed(3)} m (${(farm.source_cell_m * farm.source_cell_m).toFixed(3)} m²) · area ${Number(farm.source_area_m2).toFixed(1)} m²`,
  ];
  lines.forEach((line, i) => parts.push(`<text x="${x0}" y="${y0 - 34 + i * 14}" font-family="Helvetica, Arial, sans-serif" font-size="12" fill="#222">${escape(line)}</text>`));
  return parts.join('\n');
}

const escape = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function compareSvg(after: Farm, before: Farm | null, footprints: Polygon[], size = 420): string {
  const gap = 40;
  const top = 70;
  const panels = before ? 2 : 1;
  const width = panels * size + (panels + 1) * gap;
  // Square canvas: Quick Look thumbnails (qlmanage -t) crop anything wider than tall.
  const height = Math.max(size + top + 50, width);
  const body: string[] = [];
  let x = gap;
  if (before) {
    body.push(panel(before, x, top, size, null, `before: ${before.dataset_version} (${before.generator_version})`));
    x += size + gap;
  }
  body.push(panel(after, x, top, size, footprints, `after: ${after.dataset_version} (${after.generator_version})`));
  const legend = 'soil = farmable core · green = extension (lighter = walking reserve) · brown = path · blue dot = spawn · purple = entry · red dashes = DataSF footprint';
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
    `<rect width="100%" height="100%" fill="#FBFAF6"/>`,
    `<text x="${gap}" y="20" font-family="Helvetica, Arial, sans-serif" font-size="14" font-weight="bold" fill="#111">${escape(`${after.block_id} ${after.name}`)}</text>`,
    ...body,
    `<text x="${gap}" y="${height - 16}" font-family="Helvetica, Arial, sans-serif" font-size="11" fill="#555">${escape(legend)}</text>`,
    '</svg>',
    '',
  ].join('\n');
}

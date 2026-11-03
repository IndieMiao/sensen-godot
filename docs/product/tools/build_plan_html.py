"""Build docs/product/gameplay-plan-v2-2026-10-02.html from the Markdown plan.

Usage (from the repo root; needs the `markdown` package):

    python3 docs/product/tools/build_plan_html.py [plan.md] [out.html] [short name]

The short name goes in the page <title> and the header (default "Gensen 玩法方案 v2").

Heading ids are derived from the section number in the heading text
(`### 4.8.6 …` -> `s4-8-6`, `# 第 4 章 …` -> `ch4`, `# 附录 B …` -> `appB`,
`## B.13 …` -> `sB-13`), so adding a section no longer renumbers every later
heading. Headings without a number fall back to a short hash of their text.
Always rebuild the HTML with this script so diffs stay small.
"""
import hashlib, html, re, sys
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'gameplay-plan-v2-2026-10-02.md'
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / 'gameplay-plan-v2-2026-10-02.html'
NAME = sys.argv[3] if len(sys.argv) > 3 else 'Gensen 玩法方案 v2'

src = SRC.read_text(encoding='utf-8')
title_line = src.split('\n', 1)[0].lstrip('# ').strip()
body_md = src.split('\n', 1)[1]

# Extract mermaid fences before markdown so they survive untouched
mermaids = []
def stash(m):
    mermaids.append(m.group(1).strip())
    return f'\n\nMERMAIDBLOCK{len(mermaids)-1}\n\n'
body_md = re.sub(r'```mermaid\s*\n(.*?)```', stash, body_md, flags=re.S)

md = markdown.Markdown(extensions=['tables', 'fenced_code', 'sane_lists'])
body = md.convert(body_md)

for i, code in enumerate(mermaids):
    body = body.replace(f'<p>MERMAIDBLOCK{i}</p>', f'<div class="diagram"><pre class="mermaid">{html.escape(code)}</pre></div>')

# Stable heading ids from section numbers, and the TOC (h1 = chapters, h2 = sections)
toc = []
used = set()
chapter = ['top']
def base_id(text):
    m = re.match(r'第\s*(\d+)\s*章', text)
    if m:
        return f'ch{m.group(1)}', True
    m = re.match(r'附录\s*([A-Z])', text)
    if m:
        return f'app{m.group(1)}', True
    m = re.match(r'(\d+(?:\.\d+)*)\s', text) or re.match(r'([A-Z](?:\.[0-9A-Z]+)+)\s', text)
    if m:
        return 's' + m.group(1).replace('.', '-'), False
    m = re.match(r'([A-Z])\.\s', text)
    if m:
        return f'{chapter[0]}-{m.group(1)}', False
    return 'h-' + hashlib.sha1(text.encode('utf-8')).hexdigest()[:8], False
def head(m):
    level, inner = m.group(1), m.group(2)
    text = html.unescape(re.sub(r'<[^>]+>', '', inner)).strip()
    hid, is_chapter = base_id(text)
    if is_chapter:
        chapter[0] = hid
    if hid in used:
        hid = f'{chapter[0]}-{hid}' if not hid.startswith(chapter[0]) else hid
        n, cand = 2, hid
        while cand in used:
            cand = f'{hid}-{n}'; n += 1
        hid = cand
    used.add(hid)
    if level in ('1', '2'):
        toc.append((level, hid, text))
    return f'<h{level} id="{hid}">{inner}</h{level}>'
body = re.sub(r'<h([1-6])>(.*?)</h\1>', head, body, flags=re.S)

# Wrap tables for horizontal scrolling
body = body.replace('<table>', '<div class="tbl"><table>').replace('</table>', '</table></div>')

# Build nested TOC html
toc_html = []
open_ul = False
for level, hid, text in toc:
    if level == '1':
        if open_ul:
            toc_html.append('</ul></li>')
            open_ul = False
        toc_html.append(f'<li class="c1"><a href="#{hid}">{html.escape(text)}</a><ul>')
        open_ul = True
    else:
        toc_html.append(f'<li class="c2"><a href="#{hid}">{html.escape(text)}</a></li>')
if open_ul:
    toc_html.append('</ul></li>')
toc_html = '\n'.join(toc_html)

n_tables = body.count('<table>')
n_chapters = sum(1 for l, _, _ in toc if l == '1')

page = f'''<meta charset="utf-8">
<title>{html.escape(NAME)}</title>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@600;700&family=Noto+Sans+SC:wght@400;500;700&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root {{
  --bg: #F7F8F3; --surface: #FFFFFF; --surface-2: #EEF2EA; --ink: #24302A; --ink-2: #55635C; --ink-3: #7E8B84;
  --line: #CFD8CC; --line-2: #E2E8DF; --accent: #2E7D77; --accent-ink: #1F5F5A; --accent-soft: #DCEEEB;
  --warm: #D9823B; --warm-soft: #FBEADB; --code-bg: #EEF2EA; --thead: #E9EFE6; --row: #F8FAF6; --shadow: 0 1px 2px rgba(36,48,42,.08);
  --serif: "Noto Serif SC", "Songti SC", "STSong", "SimSun", Georgia, serif;
  --sans: "Noto Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", system-ui, sans-serif;
  --mono: "IBM Plex Mono", "SF Mono", Menlo, Consolas, monospace;
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
    color-scheme: dark;
    --bg: #141A17; --surface: #1C2420; --surface-2: #222C27; --ink: #E6EBE4; --ink-2: #AEBBB3; --ink-3: #7F8D86;
    --line: #2C3731; --line-2: #26302B; --accent: #6FC2BA; --accent-ink: #8FD6CF; --accent-soft: #1E3733;
    --warm: #E9A35F; --warm-soft: #3A2A1B; --code-bg: #222C27; --thead: #243029; --row: #1F2924; --shadow: 0 1px 2px rgba(0,0,0,.4);
  }}
}}
:root[data-theme="dark"] {{
  color-scheme: dark;
  --bg: #141A17; --surface: #1C2420; --surface-2: #222C27; --ink: #E6EBE4; --ink-2: #AEBBB3; --ink-3: #7F8D86;
  --line: #2C3731; --line-2: #26302B; --accent: #6FC2BA; --accent-ink: #8FD6CF; --accent-soft: #1E3733;
  --warm: #E9A35F; --warm-soft: #3A2A1B; --code-bg: #222C27; --thead: #243029; --row: #1F2924; --shadow: 0 1px 2px rgba(0,0,0,.4);
}}
html {{ scroll-behavior: smooth; }}
@media (prefers-reduced-motion: reduce) {{ html {{ scroll-behavior: auto; }} }}
body {{ margin: 0; background: var(--bg); color: var(--ink); font-family: var(--sans); font-size: 15px; line-height: 1.75; -webkit-text-size-adjust: 100%; }}
a {{ color: var(--accent-ink); text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
a:focus-visible, button:focus-visible, summary:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}

.topbar {{ position: sticky; top: env(safe-area-inset-top, 0px); z-index: 20; background: var(--surface); border-bottom: 1px solid var(--line); box-shadow: var(--shadow); }}
.topbar-in {{ max-width: 1360px; margin: 0 auto; padding: 10px 20px; display: flex; align-items: baseline; gap: 14px; flex-wrap: wrap; }}
.topbar .name {{ font-family: var(--serif); font-weight: 700; font-size: 17px; letter-spacing: .01em; }}
.topbar .meta {{ font-family: var(--mono); font-size: 12px; color: var(--ink-3); letter-spacing: .02em; }}
.topbar .meta span + span::before {{ content: "·"; margin: 0 8px; color: var(--line); }}

.shell {{ max-width: 1360px; margin: 0 auto; padding: 24px 20px 80px; display: grid; grid-template-columns: 280px minmax(0, 1fr); gap: 36px; }}
.toc {{ position: sticky; top: calc(env(safe-area-inset-top, 0px) + 58px); align-self: start; max-height: calc(100vh - 90px); overflow-y: auto; padding-right: 8px; font-size: 13px; line-height: 1.5; }}
.toc .label {{ font-family: var(--mono); font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: var(--ink-3); margin: 0 0 10px 2px; }}
.toc ul {{ list-style: none; margin: 0; padding: 0; }}
.toc li.c1 {{ margin: 0 0 6px; }}
.toc li.c1 > a {{ display: block; font-weight: 700; color: var(--ink); padding: 4px 8px; border-radius: 6px; }}
.toc li.c1 > ul {{ display: none; margin: 2px 0 6px 10px; border-left: 2px solid var(--line-2); }}
.toc li.c1.open > ul {{ display: block; }}
.toc li.c2 > a {{ display: block; color: var(--ink-2); padding: 3px 10px; border-left: 2px solid transparent; margin-left: -2px; }}
.toc a.active {{ color: var(--accent-ink); }}
.toc li.c2 > a.active {{ border-left-color: var(--accent); }}
.toc li.c1 > a.active {{ background: var(--accent-soft); }}
.toc-mobile {{ display: none; }}

article {{ min-width: 0; }}
.hero {{ padding: 8px 0 28px; border-bottom: 1px solid var(--line); margin-bottom: 28px; }}
.hero .eyebrow {{ font-family: var(--mono); font-size: 12px; letter-spacing: .14em; text-transform: uppercase; color: var(--accent-ink); margin: 0 0 10px; }}
.hero h1.title {{ font-family: var(--serif); font-size: clamp(26px, 3.4vw, 40px); line-height: 1.25; margin: 0 0 14px; text-wrap: balance; font-weight: 700; }}
.hero .facts {{ display: flex; flex-wrap: wrap; gap: 8px 22px; font-family: var(--mono); font-size: 12.5px; color: var(--ink-2); }}
.hero .facts b {{ color: var(--ink); font-weight: 500; }}

article h1 {{ font-family: var(--serif); font-size: 28px; line-height: 1.3; margin: 64px 0 18px; padding-top: 18px; border-top: 3px solid var(--accent); text-wrap: balance; scroll-margin-top: 80px; }}
article h2 {{ font-family: var(--serif); font-size: 21px; line-height: 1.35; margin: 40px 0 12px; text-wrap: balance; scroll-margin-top: 80px; }}
article h3 {{ font-size: 16.5px; font-weight: 700; margin: 28px 0 8px; scroll-margin-top: 80px; }}
article h4 {{ font-size: 15px; font-weight: 700; margin: 20px 0 6px; color: var(--ink-2); scroll-margin-top: 80px; }}
article p, article li {{ max-width: 76ch; }}
article p {{ margin: 0 0 12px; }}
article ul, article ol {{ padding-left: 1.4em; margin: 0 0 14px; }}
article li {{ margin: 0 0 4px; }}
article hr {{ border: 0; border-top: 1px solid var(--line-2); margin: 28px 0; }}
article strong {{ font-weight: 700; }}
article blockquote {{ margin: 16px 0; padding: 10px 16px; border-left: 3px solid var(--warm); background: var(--warm-soft); border-radius: 0 6px 6px 0; color: var(--ink); }}
article blockquote p {{ margin: 0; }}
article code {{ font-family: var(--mono); font-size: .88em; background: var(--code-bg); padding: 1px 5px; border-radius: 4px; color: var(--accent-ink); }}
article pre {{ background: var(--code-bg); border: 1px solid var(--line-2); border-radius: 8px; padding: 12px 14px; overflow-x: auto; font-family: var(--mono); font-size: 13px; line-height: 1.55; }}
article pre code {{ background: none; padding: 0; color: inherit; }}

.tbl {{ overflow-x: auto; margin: 12px 0 20px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); }}
table {{ border-collapse: collapse; width: 100%; font-size: 13.5px; line-height: 1.5; }}
thead th {{ background: var(--thead); color: var(--ink); text-align: left; font-weight: 700; padding: 8px 10px; border-bottom: 1px solid var(--line); position: sticky; top: 0; white-space: nowrap; }}
tbody td {{ padding: 7px 10px; border-top: 1px solid var(--line-2); vertical-align: top; min-width: 60px; }}
tbody tr:nth-child(even) td {{ background: var(--row); }}
td code, th code {{ white-space: nowrap; }}
td {{ font-variant-numeric: tabular-nums; }}

.diagram {{ margin: 16px 0 22px; padding: 14px; background: var(--surface); border: 1px solid var(--line); border-radius: 8px; overflow-x: auto; }}
.diagram pre.mermaid {{ background: none; border: 0; padding: 0; margin: 0; font-family: var(--mono); font-size: 12px; white-space: pre; }}
.diagram svg {{ max-width: 100%; height: auto; }}

.totop {{ position: fixed; right: 18px; bottom: calc(env(safe-area-inset-bottom, 0px) + 18px); z-index: 20; background: var(--surface); color: var(--ink); border: 1px solid var(--line); border-radius: 999px; padding: 8px 14px; font: 500 12px var(--sans); box-shadow: var(--shadow); cursor: pointer; opacity: 0; pointer-events: none; transition: opacity .2s; }}
.totop.show {{ opacity: 1; pointer-events: auto; }}

@media (max-width: 1023px) {{
  .shell {{ grid-template-columns: minmax(0, 1fr); gap: 0; padding: 16px 16px 72px; }}
  .toc {{ display: none; }}
  .toc-mobile {{ display: block; margin: 0 0 20px; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); }}
  .toc-mobile summary {{ cursor: pointer; padding: 10px 14px; font-weight: 700; list-style: none; }}
  .toc-mobile summary::-webkit-details-marker {{ display: none; }}
  .toc-mobile summary::after {{ content: "目录"; float: right; font-family: var(--mono); font-weight: 400; font-size: 12px; color: var(--ink-3); }}
  .toc-mobile .toc {{ display: block; position: static; max-height: 60vh; padding: 0 12px 12px; }}
  .toc-mobile .toc li.c1 > ul {{ display: block; }}
  article h1 {{ font-size: 24px; margin-top: 48px; }}
  article h2 {{ font-size: 19px; }}
}}
</style>

<header class="topbar"><div class="topbar-in">
  <span class="name">{html.escape(NAME)}</span>
  <span class="meta"><span>2026-10-02</span><span>{n_chapters} 章</span><span>{n_tables} 张表</span><span>独立完整版</span></span>
</div></header>

<div class="shell">
  <nav class="toc" id="toc" aria-label="目录">
    <p class="label">Contents</p>
    <ul>{toc_html}</ul>
  </nav>
  <article>
    <details class="toc-mobile"><summary>{html.escape(NAME)}</summary><nav class="toc" aria-label="目录"><ul>{toc_html}</ul></nav></details>
    <div class="hero">
      <p class="eyebrow">Game Design Document · Prototype Stage</p>
      <h1 class="title">{html.escape(title_line)}</h1>
      <div class="facts"><span><b>Energy</b> 200 · +1/4 min</span><span><b>Skills</b> Farming / Fishing ×10 Lv</span><span><b>Trips</b> 1–7</span><span><b>Crops</b> 20 · <b>Fish</b> 20 · <b>Dishes</b> 29</span></div>
    </div>
{body}
  </article>
</div>
<button class="totop" id="totop" type="button" aria-label="回到顶部">↑ Top</button>

<script>
(function () {{
  var links = Array.prototype.slice.call(document.querySelectorAll('#toc a'));
  var targets = links.map(function (a) {{ return document.getElementById(a.getAttribute('href').slice(1)); }}).filter(Boolean);
  function setActive(id) {{
    links.forEach(function (a) {{ a.classList.toggle('active', a.getAttribute('href') === '#' + id); }});
    var cur = document.querySelector('#toc a[href="#' + id + '"]');
    document.querySelectorAll('#toc li.c1').forEach(function (li) {{ li.classList.remove('open'); }});
    if (cur) {{ var c1 = cur.closest('li.c1'); if (c1) c1.classList.add('open'); }}
  }}
  if ('IntersectionObserver' in window) {{
    var visible = new Map();
    var io = new IntersectionObserver(function (entries) {{
      entries.forEach(function (e) {{ if (e.isIntersecting) visible.set(e.target.id, e.boundingClientRect.top); else visible.delete(e.target.id); }});
      var best = null;
      visible.forEach(function (top, id) {{ if (best === null || top < visible.get(best)) best = id; }});
      if (best) setActive(best);
    }}, {{ rootMargin: '-70px 0px -70% 0px' }});
    targets.forEach(function (t) {{ io.observe(t); }});
  }}
  if (targets.length) setActive(targets[0].id);
  var btn = document.getElementById('totop');
  window.addEventListener('scroll', function () {{ btn.classList.toggle('show', window.scrollY > 800); }}, {{ passive: true }});
  btn.addEventListener('click', function () {{ window.scrollTo({{ top: 0 }}); }});
}})();
</script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js"></script>
<script>
(function () {{
  // The artifact viewer renders pre.mermaid natively; this fallback only runs for the local file.
  function pending() {{ return Array.prototype.filter.call(document.querySelectorAll('pre.mermaid'), function (p) {{ return !p.querySelector('svg') && !p.getAttribute('data-processed'); }}); }}
  setTimeout(function () {{
    var left = pending();
    if (!left.length || !window.mermaid) return;
    var dark = document.documentElement.getAttribute('data-theme') === 'dark' || (!document.documentElement.getAttribute('data-theme') && window.matchMedia('(prefers-color-scheme: dark)').matches);
    try {{ window.mermaid.initialize({{ startOnLoad: false, theme: dark ? 'dark' : 'neutral', flowchart: {{ htmlLabels: true }} }}); window.mermaid.run({{ nodes: left }}); }} catch (e) {{}}
  }}, 1200);
}})();
</script>
'''
pass
full = '<!doctype html>\n<html lang="zh-CN">\n<head>\n' + page.split('<header class="topbar">',1)[0] + '</head>\n<body>\n<header class="topbar">' + page.split('<header class="topbar">',1)[1] + '\n</body>\n</html>\n'
OUT.write_text(full, encoding='utf-8')
print('written', OUT, len(page), 'chars; chapters', n_chapters, 'tables', n_tables, 'mermaid', len(mermaids))

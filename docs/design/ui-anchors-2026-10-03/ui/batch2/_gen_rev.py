#!/usr/bin/env python3
"""Batch 2 revision (2026-10-05 pm, user review of section 06):
  1  Homestead Stall has no stallhand — FARM-6 / FARM-6-2 lose the keeper panel, SKILL-2 rebuilt on top; NPC-G1-5 retired.
  2  PROFILE-1 / PROFILE-2: a real profile page (own / someone else's); replaces the avatar drawer and PASS-3 as the hub.
  3  BAG-2: Bag and Tools & Gear merged — the bag drawer gets a Bag | Gear switch; EQUIP-1 retired; Tackle tab = consumables only.
  4  SOC-4: Inbox with the Parcels tab (bell, or the mailbox at home); BAG-5-2: a reward into a full bag goes to Parcels (no Keep which?).
Run: python3 _gen_rev.py [farm6 skill2 profile1 profile2 bag2 soc4 bag5b]"""
import os, re, sys
import _gen as G
from _gen import I, tile, hud, page, bag_drawer, cell, EMPTY, FARM, FARM_QB, qbar, fab, close_head
HERE = G.HERE
B1 = G.B1

# ---------------------------------------------------------------- 1 · stall without a stallhand
def farm6():
    for name in ('FARM-6', 'FARM-6-2'):
        p = os.path.join(B1, name + '.html')
        s = open(p, encoding='utf-8').read()
        s = re.sub(r'\n    <div class="kpanel is-stall">.*?\n    </div>\n    </div>', '', s, flags=re.S) if False else s
        s = re.sub(r'\n    <div class="kpanel is-stall">\n      <div class="portrait"[^\n]*\n      <div class="mid">[^\n]*\n    </div>', '', s)
        s = s.replace("<span>Bao's Stall</span><span class=\"sub\">· Homestead</span>", '<span>Homestead Stall</span>')
        if 'stall without a stallhand' not in s:
            s = s.replace('<body ', '<!-- 2026-10-05 pm revision: stall without a stallhand (user decision 1:A) — no keeper panel, tapping the shed opens this drawer directly. -->\n<body ', 1)
        open(p, 'w', encoding='utf-8').write(s)
        assert 'kpanel' not in s.split('</head>')[1], name

def skill2():
    G.skill2()
    p = os.path.join(HERE, 'SKILL-2.html')
    s = open(p, encoding='utf-8').read()
    s = s.replace("selecting a locked row in Bao\\'s Stall", 'selecting a locked row in the Homestead Stall').replace("selecting a locked row in Bao's Stall", 'selecting a locked row in the Homestead Stall')
    # rows moved up by the removed keeper panel
    s = s.replace('class="b2-lift" style="top:752px"', 'class="b2-lift" style="top:LIFTpx"').replace('class="b2-gate is-below" style="top:900px', 'class="b2-gate is-below" style="top:GATEpx')
    lift = int(os.environ.get('LIFT', '600'))
    s = s.replace('LIFT', str(lift)).replace('GATE', str(lift + 148))
    open(p, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- 2 · profile
PORTRAIT = ('profile-avatar.png', (1.05, 2, 79), ('#BFDCCB', '#F8E2B8'))
FARM_THUMB = "background-image:url('../../scenes/farm.png'); background-size:330px 495px; background-position:-48px -112px;"

def _skills():
    def sk(name, icon, lv, pct, color):
        return (f'<div class="b2-box pf-sk"><div class="lv" style="--tc:{color}; --pct:{pct}"><div class="in">{I(icon)}</div></div>'
                f'<div><div class="nm">{name}</div><div class="l">Lv{lv}</div></div></div>')
    return ('<div class="pf-skills">' + sk('Farming', 'icons.svg#i-hoe', 4, 56, '#7FC66A') + sk('Fishing', 'icons.svg#i-rod', 6, 44, '#6FA8DC')
            + sk('Cooking', 'icons.svg#i-pot', 3, 50, '#E39A5F') + '</div>')

def _collections(new=True):
    def t(icon, have, need, name, cap):
        pct = round(have * 100 / need)
        return (f'<div class="need-tile is-m" style="--pct:{pct}"><div class="ring"><div class="core">{I(icon)}</div></div>'
                f'<div class="lbl">{name} <b>{have}</b><span class="of">/{need}</span><span class="cap">{cap}</span></div></div>')
    return (f'<div class="b2-box need-row pf-col">{"<span class=\"newp\">◆ New</span>" if new else ""}'
            + t('icons.svg#i-fish', 9, 20, 'Fish', 'Fish-dex') + t('icons.svg#i-cookbook', 12, 48, 'Pages', 'Cookbook')
            + t('icons.svg#i-carrot', 7, 20, 'Crops', 'Crop-dex') + t('icons-home.svg#i-passport', 4, 10, 'Cities', 'Passport') + '</div>')

def profile1():
    body = f'''  <div class="pf-top">
    <div class="pf-rb">{I("icons.svg#i-chev-r", "ic back")}</div>
    <div class="ttl">Profile</div>
    <div class="pf-rb" title="Settings">{I("icons-profile.svg#i-cog")}</div>
  </div>
  <div class="pf-look">{I("icons-profile.svg#i-hanger")}Edit look</div>
  <section class="pf-sheet">
    <div class="pf-id">
      <div class="who">
        <div class="pf-name">Lin <span class="pf-title">{I("icons-profile.svg#i-medal")}Home Cook</span></div>
        <div class="pf-line"><span>{I("icons.svg#i-home")}<b>Shanghai</b> · Subtropical</span><span class="sep"></span><span>Since Oct 2</span><span class="sep"></span><span>ID 4821 7730 {I("icons-profile.svg#i-copy")}</span></div>
        <div class="pf-bio">“Radishes before coffee.”</div>
      </div>
      <div class="pf-edit">{I("icons-profile.svg#i-pencil")}Edit</div>
    </div>
    <div class="b2-box pf-soc">
      <div class="s"><div class="n">12</div><div class="k">Following</div></div>
      <div class="s"><div class="n">18</div><div class="k">Followers</div></div>
      <div class="s"><div class="n">9</div><div class="k">Mutual</div></div>
      <div class="s"><div class="n">3<span class="of">/4</span></div><div class="k">Close Friends</div></div>
    </div>
    <div class="pf-sec">Skills<span class="r">All skills{I("icons.svg#i-chev-r")}</span></div>
    {_skills()}
    <div class="pf-sec">My farm</div>
    <div class="b2-box pf-farm">
      <div class="th" style="{FARM_THUMB}"></div>
      <div class="mid">
        <div class="nm">Lin's Homestead <span class="lvp">Lv3</span></div>
        <div class="f">{I("icons-farm.svg#i-clock")}Radishes ready in <b>1h 12m</b></div>
        <div class="f">{I("icons-profile.svg#i-people")}<b>5</b> visitors this week</div>
        <div class="f">{I("icons-profile.svg#i-flag")}Open to <b>Friends only</b></div>
      </div>
      {I("icons.svg#i-chev-r", "chev")}
    </div>
    <div class="pf-sec">Collections<span class="r">Open{I("icons.svg#i-chev-r")}</span></div>
    {_collections()}
    <div class="pf-mini">
      <div class="b2-box m">{I("icons-profile.svg#i-medal")}<div><div class="k">Medals</div><div class="v">2 · 3 titles</div></div></div>
      <div class="b2-box m">{I("icons-npc.svg#i-board")}<div><div class="k">Guestbook</div><div class="v is-new">2 new notes</div></div></div>
      <div class="b2-box m">{I("icons-npc.svg#i-stamp")}<div><div class="k">Second Home</div><div class="v">1/2 · Tokyo</div></div></div>
    </div>
  </section>'''
    page('PROFILE-1', 'Profile', 'own profile (tap the HUD avatar anywhere, or Me on the map): portrait + Edit look (Wardrobe), name, title, home city, since, ID, bio, Edit; Following / Followers / Mutual / Close Friends; three skill rings; My farm card; Collections as four M tiles; Medals · Guestbook · Second Home; Settings is the cog top-right.',
         *PORTRAIT, body, css=('kit.css', 'kit-need.css', 'kit-b2.css', 'kit-profile.css'), cls='scene-cam drawer-open')

def profile2():
    thumb = "background-image:url('../../scenes/farm-lv3.png'); background-size:330px 495px; background-position:-48px -100px;"
    body = f'''  <div class="pf-top">
    <div class="pf-rb">{I("icons.svg#i-chev-r", "ic back")}</div>
    <div class="ttl">Mia</div>
    <div class="pf-rb" title="More"><span style="font-size:40px;font-weight:800;line-height:20px;margin-top:-14px">···</span></div>
  </div>
  <section class="pf-sheet">
    <div class="pf-id">
      <div class="who">
        <div class="pf-name">Mia <span class="pf-title">{I("icons-profile.svg#i-medal")}Line Cook</span></div>
        <div class="pf-line"><span>{I("icons.svg#i-home")}<b>Shanghai</b> · Subtropical</span><span class="sep"></span><span>Since Sep 28</span><span class="sep"></span><span class="pf-rel">{I("icons.svg#i-check")}Mutual</span></div>
        <div class="pf-bio">“Pond at dawn, stove at dusk.”</div>
      </div>
    </div>
    <div class="pf-acts">
      <div class="btn-sm btn-primary">{I("icons.svg#i-home")}Visit farm</div>
      <div class="btn-sm btn-sec">{I("icons.svg#i-gift")}Send a gift</div>
      <div class="btn-sm btn-sec">{I("icons.svg#i-check")}Following</div>
    </div>
    <div class="pf-hint">{I("icons-npc.svg#i-handshake")}Close Friend · 1 more visit this week · 2/3</div>
    <div class="pf-sec">Skills</div>
    {_skills().replace('Lv4', 'Lv5').replace('Lv6', 'Lv3').replace('Lv3</div></div></div></div>', 'Lv6</div></div></div></div>')}
    <div class="pf-sec">Mia's farm</div>
    <div class="b2-box pf-farm">
      <div class="th" style="{thumb}"></div>
      <div class="mid">
        <div class="nm">Mia's Homestead <span class="lvp">Lv5</span></div>
        <div class="f">{I("icons-profile.svg#i-flag")}Open to <b>Friends only</b></div>
        <div class="f">{I("icons-npc.svg#i-board")}Guestbook · <b>14</b> notes</div>
        <div class="f">{I("icons.svg#i-water")}<b>3</b> plots need water</div>
      </div>
    </div>
    <div class="pf-sec">Collections</div>
    {_collections(new=False).replace('<b>9</b><span class="of">/20</span>', '<b>14</b><span class="of">/20</span>').replace('style="--pct:45"', 'style="--pct:70"', 1)}
  </section>'''
    page('PROFILE-2', "Someone's profile", "someone else's profile (tap a friend's avatar on the map, in a room or in the friends list): no Settings / Edit / ID; relationship chip; Visit farm · Send a gift · Following; the Close Friend line says what is missing; skills, farm card and collections read-only; ··· = Unfollow / Block / Report.",
         *(('profile-avatar-mia.png',) + PORTRAIT[1:]), body, css=('kit.css', 'kit-need.css', 'kit-b2.css', 'kit-profile.css'), cls='scene-cam drawer-open')

# ---------------------------------------------------------------- 3 · bag + gear merged
def bag2():
    def slot(act, icon, nm, cls=''):
        return f'<div class="gr-slot {cls}"><span class="act">{act}</span>{I(icon)}<span class="nm">{nm}</span></div>'
    slots = ''.join([slot('Farming', 'icons.svg#i-hoe', 'Starter Hoe'), slot('Fishing', 'icons.svg#i-rod', 'Starter Rod', 'is-sel'),
                     slot('Mining', 'icons.svg#i-pickaxe', 'Starter Pickaxe'), slot('Combat', 'icons.svg#i-sword', 'Wooden Sword'),
                     slot('Ring', 'icons.svg#i-ring', 'Empty', 'is-acc is-empty'), slot('Charm', 'icons.svg#i-charm', 'Lucky Charm', 'is-acc')])
    rows = f'''<div class="gr-row"><div class="th">{I("icons.svg#i-rod")}</div><div class="mid"><div class="nm">Starter Rod <span class="eq">Equipped</span></div><div class="meta">Bite window 2.0 s · lands up to Fine</div></div></div>
      <div class="gr-row"><div class="th">{I("icons.svg#i-rod")}</div><div class="mid"><div class="nm">Reed Rod</div><div class="meta">Bite window 2.6 s · lands up to Rare</div></div><div class="btn-sm btn-primary">Equip</div></div>
      <div class="gr-row is-locked"><div class="th">{I("icons-npc.svg#i-rod-carbon")}</div><div class="mid"><div class="nm">Carbon Rod</div><div class="meta">Lands up to Legendary · 350 coins at Tackle Shop</div></div><div class="btn-sm is-disabled">{I("icons.svg#i-lock")}Fishing Lv6</div></div>'''
    qb = ''.join(f'<div class="slot has-count{" is-selected" if k == 0 else ""}">{I(s[0], "slot-icon")}<span class="name">{s[1]}</span><span class="count">×{s[2]}</span></div>' if s else '<div class="slot is-ghost"></div>' for k, s in enumerate(FARM_QB))
    body = f'''  <div class="scene-dim"></div>
  <section class="drawer is-bag">
    <div class="qb-inline">
      <div class="slots">{qb}</div>
      <div class="close-slot" title="Close">{I("icons.svg#i-close")}</div>
    </div>
    <div class="gr-seg"><div class="sg">{I("icons.svg#i-bag")}Bag <span class="of">19/25</span></div><div class="sg is-on">{I("icons.svg#i-pickaxe")}Gear</div></div>
    <div class="gr-sec">Equipped<span class="sub">Tap a slot to change it</span></div>
    <div class="gr-slots">{slots}</div>
    <div class="gr-sec">Fishing slot<span class="sub">3 rods · 1 locked</span></div>
    <div class="gr-list">{rows}</div>
    <div class="gr-foot">Gear doesn't take Bag space · looks live in Profile › Edit look</div>
  </section>
{hud()}'''
    page('BAG-2', 'Bag · Gear', 'Bag and Tools & Gear merged: the bag drawer has a Bag | Gear switch. Gear = six equipped slots (four tools, Ring, Charm); tapping a slot filters the owned list below to that slot (Equipped tag / Equip / locked row with level and where to buy). No Outfit tab — looks live in Profile › Edit look (Wardrobe). Gear never counts against the bag.',
         *FARM, body, css=('kit.css', 'kit-cook.css', 'kit-b2.css', 'kit-profile.css'), cls='scene-cam drawer-open')

# ---------------------------------------------------------------- 4 · inbox parcels + full-bag reward
def soc4():
    def row(icon, nm, meta, tm, btn, cnt=None, soon=False, gifted=False, dis=False):
        c = f'<span class="cnt">×{cnt}</span>' if cnt else ''
        g = '<span class="gifted">Gifted</span>' if gifted else ''
        b = f'<div class="btn-sm {"is-disabled" if dis else "btn-primary"}">{btn}</div>'
        return (f'<div class="ib-row"><div class="th">{I(icon)}{c}</div><div class="mid"><div class="nm">{nm}</div>'
                f'<div class="meta">{meta}{g}<span>·</span>{I("icons-farm.svg#i-clock")}<span class="tm{" is-soon" if soon else ""}">{tm}</span></div></div>{b}</div>')
    rows = ''.join([
        row('icons.svg#i-carp', 'Perch ×7', 'Request reward · Stall Board', '23h 40m left', 'Claim', 7),
        row('icons.svg#i-dish-stew', 'Herb Fish Stew', 'Gift from Mia', '5h 12m left', 'Claim', 1, gifted=True),
        row('icons.svg#i-carrot-seeds', 'Tokyo seeds ×2', 'First-visit gift · Tokyo', '1h 05m left', 'Claim', 2, soon=True),
    ])
    body = f'''  <div class="scene-dim"></div>
  <section class="drawer is-b2" style="--drawer-h:1300px">
{close_head("Inbox", "icons.svg#i-bell")}
    <div class="tabs is-compact"><div class="tab">To do<span class="n">2</span></div><div class="tab is-on">Parcels<span class="n">3</span></div><div class="tab">Updates</div></div>
    <div class="b2-box ib-bagline">{I("icons.svg#i-bag")}<span>Bag 22<span style="color:var(--ink-2)">/25</span></span><div class="cap-track"><div class="cap-fill" style="--pct:88%"></div></div><span class="r">3 slots free</span></div>
    <div class="gr-sec">Parcels 3/8<span class="sub">Kept 24h · Claim needs a free slot</span></div>
    <div class="b2-box" style="margin-top:12px; padding:0 22px">{rows}</div>
    <div style="margin-top:20px; display:flex; justify-content:flex-end"><div class="btn-sm btn-sec" style="height:84px; padding:0 34px; font-size:26px">Claim all · 3 slots</div></div>
    <div class="ib-rule"><b>Not claimed in 24h:</b> sellable items turn into coins at 80% · gifts go back to the sender · regional seeds are lost</div>
  </section>
{hud(coins=230).replace('<span class="badge">3</span>', '<span class="badge">5</span>')}'''
    page('SOC-4', 'Inbox · Parcels', 'Inbox (the bell, or the mailbox by the farmhouse): To do / Parcels / Updates. Parcels = passive arrivals only (request rewards, gifts, first-visit gifts, collection rewards, crops a helper picked while you were away); 8 parcels × 24 h; Claim needs a free slot (full bag → Make room · 1 slot); expiry rule in one line.',
         *FARM, body, css=('kit.css', 'kit-b2.css', 'kit-profile.css'), cls='scene-cam drawer-open')

def bag5b():
    hud_html = hud().replace('<span class="badge">3</span>', '<span class="badge">4</span>')
    body = f'''  <div class="tag tag-card tag--pointer tag--anchor-bottom" style="--x:370px; --y:1015px; --dx:-40px">{I("icons.svg#i-home")}<span>Homestead Lv2</span></div>
{fab("icons.svg#i-sow", "Sow ×1", "2 Energy", "icons.svg#i-hoe")}
{hud_html}
  <div class="tag tag-card is-small tag--pointer tag--anchor-bottom" style="--x:112px; --y:1165px; --dx:60px">{I("icons-profile.svg#i-parcel")}<span>Parcel</span></div>
  <div class="ib-toast">{I("icons-profile.svg#i-parcel")}<span>Bag full · Perch ×7 sent to Inbox</span><span class="sub">· 24h</span></div>
{qbar(FARM_QB, bag_dot=True)}'''
    page('BAG-5-2', 'Sent to Inbox', 'a reward lands while the bag is 25/25: nothing to choose — it goes to Inbox · Parcels with a toast under the bell (badge +1); Claim within 24 h once a slot is free. Replaces the old Keep which? card.',
         *FARM, body, css=('kit.css', 'kit-farm.css', 'kit-b2.css', 'kit-profile.css'))

# ---------------------------------------------------------------- settings (from the Profile cog)
def settings1():
    chev = I("icons.svg#i-chev-r")
    def row(icon, k, v=None, tg=None, sl=None):
        right = (f'<span class="v">{v}{chev}</span>' if v is not None else '') + (f'<span class="st-tg{"" if tg else " is-off"}"></span>' if tg is not None else '') + (f'<span class="st-sl" style="--v:{sl}%"><i></i><b></b></span>' if sl is not None else '')
        return f'<div class="st-row">{I(icon) if icon else ""}<span>{k}</span>{right}</div>'
    def card(head, rows, sub=''):
        return f'<div class="st-h">{head}{f"<span class=sub>· {sub}</span>" if sub else ""}</div><div class="st-card">{"".join(rows)}</div>'
    body = f'''  <div class="st-page"></div>
  <div class="pf-top">
    <div class="pf-rb">{I("icons.svg#i-chev-r", "ic back")}</div>
    <div class="ttl">Settings</div>
  </div>
  <div class="st-body">
    {card("Account", [row(None, "Signed in with Apple", "lin.z@icloud.com"), row(None, "Password", "Change")])}
    {card("Personal info", [row(None, "Gender", "Prefer not to say"), row(None, "Birthday", "Mar 14")], sub="only you can see this")}
    {card("Privacy", [row(None, "Farm visitors", "Friends only"), row(None, "Who can follow me", "Everyone"), row(None, "Show me on the map", tg=True)])}
    {card("Notifications", [row(None, "Crops ready", tg=True), row(None, "Invites and Guest Passes", tg=True), row(None, "Parcels about to expire", tg=True), row(None, "Helper summaries", tg=False)])}
    {card("Sound", [row(None, "Music", sl=60), row(None, "Sound effects", sl=80)])}
    {card("General", [row(None, "Language", "English"), row(None, "Help and feedback", ""), row(None, "Version", "0.17.9").replace(chev, "")])}
    <div class="st-out">Sign out</div>
    <div class="st-del">Delete account</div>
  </div>'''
    page('SETTINGS-1', 'Settings', 'Settings, opened from the cog on the Profile page: Account (sign-in method + email, password) · Personal info (gender, birthday — only you) · Privacy (farm visitors, who can follow, show me on the map) · Notifications (four toggles) · Sound (two sliders) · General (language, help, version) · Sign out · Delete account. Name and bio are edited on the Profile, not here.',
         *PORTRAIT, body, css=('kit.css', 'kit-profile.css'), cls='scene-cam drawer-open')

if __name__ == '__main__':
    which = sys.argv[1:] or ['farm6', 'skill2', 'profile1', 'profile2', 'bag2', 'soc4', 'bag5b']
    for w in which: globals()[w]()
    print('written', which)

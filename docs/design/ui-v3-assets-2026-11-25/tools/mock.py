"""In-game mockups (360x640 logical, rendered 2x) using C-84 tokens and C-85 layouts, with the new C-86 assets."""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
T = sys.argv[1]  # TMPDIR
OUT = sys.argv[2]
SRC = f'{T}/dl/c85/x/ui-v3-pages-2026-11-24/src/assets'
A = f'{T}/out'
S = 2
NUN = f'{T}/fonts/Nunito.ttf'
def font(sz, w='ExtraBold'):
    f = ImageFont.truetype(NUN, int(sz * S)); f.set_variation_by_name(w); return f
def P(v): return int(round(v * S))
PAPER = (0xF3, 0xF1, 0xEA, 255); HEADER = (0xC4, 0xC6, 0x3C, 255); TAG = (0x7A, 0x72, 0x5E, 255)
SLOT = (0xD6, 0xD7, 0xD2, 255); GLASS = (0x1E, 0x1C, 0x17, 0x9E); GLASS_S = (0x1E, 0x1C, 0x17, 0xC7)
PRIMARY = (0x94, 0xC2, 0x42, 255); TEXT = (0x2B, 0x2A, 0x26, 255); MUTED = (0x70, 0x6E, 0x66, 255)

def icon(path, size):
    return Image.open(path).convert('RGBA').resize((P(size), P(size)), Image.LANCZOS)
def layer(img): return Image.new('RGBA', img.size, (0, 0, 0, 0))
def rr(img, box, r, fill, outline=None, width=0):
    l = layer(img); ImageDraw.Draw(l).rounded_rectangle([P(box[0]), P(box[1]), P(box[2]) - 1, P(box[3]) - 1], radius=P(r), fill=fill, outline=outline, width=P(width) if width else 0); img.alpha_composite(l)
def ell(img, box, fill, outline=None, width=0):
    l = layer(img); ImageDraw.Draw(l).ellipse([P(box[0]), P(box[1]), P(box[2]) - 1, P(box[3]) - 1], fill=fill, outline=outline, width=P(width) if width else 0); img.alpha_composite(l)
def text(img, xy, s, sz, fill=(255, 255, 255, 255), anchor='lm', stroke=0, w='ExtraBold'):
    d = ImageDraw.Draw(img); d.text((P(xy[0]), P(xy[1])), s, font=font(sz, w), fill=fill, anchor=anchor, stroke_width=P(stroke), stroke_fill=(0x2E, 0x3A, 0x12, 255))
def paste(img, ic, x, y): img.alpha_composite(ic, (P(x), P(y)))
def shadow(img, box, r, blur=8, alpha=70):
    l = layer(img); ImageDraw.Draw(l).rounded_rectangle([P(box[0]), P(box[1] + 4), P(box[2]), P(box[3] + 4)], radius=P(r), fill=(0, 0, 0, alpha)); img.alpha_composite(l.filter(ImageFilter.GaussianBlur(P(blur))))

def bg(name):
    b = Image.open(f'{SRC}/{name}').convert('RGBA')
    off = 0 if 'map' in name else 0.16  # concept frames carry their own HUD at the top: skip it
    b = b.crop((0, int(b.size[1] * off), b.size[0], b.size[1]))
    sc = max(P(360) / b.size[0], P(640) / b.size[1]); b = b.resize((int(b.size[0] * sc) + 1, int(b.size[1] * sc) + 1), Image.LANCZOS)
    return b.crop((0, 0, P(360), P(640)))

def hud(img):
    text(img, (20, 12), '9:41', 12, w='Bold')
    # avatar ring
    ell(img, (12, 32, 64, 84), (0x3A, 0x5A, 0x8A, 255)); ell(img, (12, 32, 64, 84), None, (0x7F, 0xD0, 0x4B, 255), 4)
    ell(img, (16, 36, 60, 80), (255, 255, 255, 255))
    pp = Image.open(f'{SRC}/assets/ui/kit_images/player_portrait.png').convert('RGBA').resize((P(40), P(40)), Image.LANCZOS)
    m = Image.new('L', pp.size, 0); ImageDraw.Draw(m).ellipse([0, 0, pp.size[0] - 1, pp.size[1] - 1], fill=255); pp.putalpha(m); paste(img, pp, 18, 38)
    rr(img, (60, 48, 130, 68), 10, GLASS); rr(img, (62, 50, 128, 66), 8, (0x7F, 0xD0, 0x4B, 255))
    text(img, (95, 58), '200/200', 11, anchor='mm', stroke=1.2)
    paste(img, icon(f'{A}/sys/96/icon_sys_tasks.png', 24), 136, 46)
    rr(img, (276, 46, 348, 70), 12, GLASS); text(img, (286, 58), '1,533', 12, stroke=0)
    paste(img, icon(f'{A}/color/128/icon_currency_coin.png', 18), 327, 49)

def side_buttons(img, badge=True):
    for i, (n, y) in enumerate([('map', 464), ('phone', 508), ('bag', 552)]):
        ell(img, (312, y, 348, y + 36), GLASS); paste(img, icon(f'{A}/sys/96/icon_sys_{n}.png', 24), 318, y + 6)
    if badge: ell(img, (338, 506, 352, 520), (0xF2, 0xA9, 0x1F, 255))
    text(img, (330, 596), '9/24', 10, anchor='mm', stroke=1)

def screen_farm():
    img = bg('farm-bg.jpg'); hud(img); side_buttons(img)
    rr(img, (60, 532, 300, 608), 18, GLASS)
    items = [('carrot', 'x22'), ('lettuce', 'x18'), ('radish', 'x6'), (None, '')]
    for i, (n, q) in enumerate(items):
        x = 72 + i * 56
        rr(img, (x, 542, x + 48, 598), 12, (0, 0, 0, 0x2E))
        if n: paste(img, icon(f'{A}/items/128/icon_item_{n}.png', 32), x + 8, 546); text(img, (x + 24, 588), q, 10, anchor='mm', stroke=1)
        if i == 0: rr(img, (x, 542, x + 48, 598), 12, None, (0xF4, 0xE8, 0x8A, 255), 2)
    # harvest float text
    paste(img, icon(f'{A}/items/128/icon_item_carrot.png', 24), 160, 300); text(img, (186, 312), '×1', 14, stroke=2)
    return img

def panel(img, top, rows, hero, label, cells, extra_h=0):
    h = 40 + 28 + rows * 72 + (rows - 1) * 28 + 24 + extra_h
    shadow(img, (36, top, 324, top + h), 20, 10, 90)
    rr(img, (36, top, 324, top + h), 20, PAPER)
    l = layer(img); d = ImageDraw.Draw(l)
    d.rounded_rectangle([P(36), P(top), P(324) - 1, P(top + 40)], radius=P(20), fill=HEADER); d.rectangle([P(36), P(top + 20), P(324) - 1, P(top + 40)], fill=HEADER); img.alpha_composite(l)
    tw = ImageDraw.Draw(img).textlength(label, font=font(13)) / S
    rr(img, (134, top + 6, 134 + tw + 24, top + 34), 14, TAG); text(img, (146, top + 20), label, 13)
    ImageDraw.Draw(img).text((P(306), P(top + 20)), '✕', font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', P(14)), fill=(0x55, 0x55, 0x50, 255), anchor='mm')
    paste(img, icon(f'{A}/hero/256/{hero}.png', 80), 48, top - 40)
    for k, c in enumerate(cells):
        r, cidx = divmod(k, 3); x = 56 + cidx * 88; y = top + 68 + r * 100
        ell(img, (x, y, x + 72, y + 72), SLOT)
        if c == '+':
            text(img, (x + 36, y + 36), '+', 26, fill=(0x55, 0x55, 0x50, 255), anchor='mm')
        elif c:
            n, q = c; paste(img, icon(f'{A}/items/128/icon_item_{n}.png', 48), x + 12, y + 12)
            if q: text(img, (x + 70, y + 70), q, 10, fill=TEXT, anchor='rm')
            if k == 0: ell(img, (x - 1, y - 1, x + 73, y + 73), None, PRIMARY, 3)
    return h

def scrimmed(name):
    img = bg(name); hud(img)
    s = Image.new('RGBA', img.size, (0x17, 0x15, 0x0F, 0x99)); img.alpha_composite(s); return img

def screen_bag():
    img = scrimmed('farm-bg2.jpg')
    cells = [('fish_crucian', 'x20'), ('fish_perch', 'x18'), ('wood', 'x12'), ('stone', 'x8'), ('tea', 'x3'), ('seed_carrot', 'x9'), ('copper_ore', 'x4'), ('copper_pickaxe', ''), '+']
    panel(img, 150, 3, 'hero_bag', 'Bag', cells)
    return img

def screen_market():
    img = scrimmed('farm-bg3.jpg')
    cells = [('carrot', 'x6'), ('wood', 'x12'), ('stone', 'x8'), ('fiber', 'x3'), ('salad', 'x1'), ('crate', 'x1')]
    top = 128; h = panel(img, top, 2, 'hero_market', 'Market', cells, extra_h=128)
    y = top + 68 + 2 * 100 - 6
    rr(img, (56, y, 304, y + 56), 16, (255, 255, 255, 255)); paste(img, icon(f'{A}/items/128/icon_item_carrot.png', 32), 66, y + 12)
    text(img, (108, y + 19), 'Carrot', 14, fill=TEXT); text(img, (108, y + 38), '12 each', 12, fill=MUTED, w='Bold')
    paste(img, icon(f'{A}/color/128/icon_currency_coin.png', 14), 158, y + 31)
    by = y + 68
    rr(img, (56, by, 176, by + 44), 22, (255, 255, 255, 255), (0xCF, 0xCB, 0xBE, 255), 1.5); text(img, (116, by + 22), 'Sell', 14, fill=TEXT, anchor='mm')
    rr(img, (184, by, 304, by + 44), 22, PRIMARY); text(img, (244, by + 22), 'Sell All · 72', 14, anchor='mm', stroke=1)
    return img

def screen_map():
    img = bg('assets/ui/backgrounds/map-social.png')
    text(img, (20, 12), '9:41', 12, fill=TEXT, w='Bold')
    rr(img, (12, 30, 52, 70), 20, (255, 255, 255, 255)); text(img, (32, 50), '‹', 22, fill=TEXT, anchor='mm')
    rr(img, (58, 36, 186, 64), 14, TAG); text(img, (72, 50), 'San Francisco', 12)
    rr(img, (270, 34, 348, 66), 16, (255, 255, 255, 235)); text(img, (316, 50), 'Lin', 12, fill=TEXT, anchor='mm')
    ell(img, (274, 38, 298, 62), (0x7F, 0xD0, 0x4B, 255))
    ell(img, (312, 360, 348, 396), GLASS); paste(img, icon(f'{A}/sys/96/icon_sys_locate.png', 24), 318, 366)
    rr(img, (240, 408, 348, 444), 18, GLASS); paste(img, icon(f'{A}/sys/96/icon_sys_home.png', 22), 250, 415); text(img, (278, 426), 'Home', 13)
    top = 470
    shadow(img, (12, top, 348, 628), 20, 10, 80)
    rr(img, (12, top, 348, 628), 20, PAPER)
    l = layer(img); d = ImageDraw.Draw(l); d.rounded_rectangle([P(12), P(top), P(348) - 1, P(top + 30)], radius=P(20), fill=HEADER); d.rectangle([P(12), P(top + 15), P(348) - 1, P(top + 30)], fill=HEADER); img.alpha_composite(l)
    paste(img, icon(f'{A}/hero/256/hero_parcel.png', 68), 22, top - 34)
    rr(img, (96, top + 2, 160, top + 28), 13, TAG); text(img, (128, top + 15), 'Parcel', 12, anchor='mm')
    text(img, (28, top + 54), '1200 Market St', 17, fill=TEXT)
    text(img, (28, top + 78), '4 core · 9 walk-only extension cells', 11, fill=MUTED, w='Bold')
    ell(img, (28, top + 95, 38, top + 105), (0x9A, 0x98, 0x90, 255)); text(img, (44, top + 100), 'Not claimed', 12, fill=TEXT)
    rr(img, (28, top + 112, 332, top + 152), 20, PRIMARY); text(img, (180, top + 132), 'Make this my first home', 14, anchor='mm', stroke=1)
    return img

def screen_signin():
    img = scrimmed('farm-bg.jpg')
    top = 170; h = 300
    shadow(img, (36, top, 324, top + h), 20, 10, 90); rr(img, (36, top, 324, top + h), 20, PAPER)
    l = layer(img); d = ImageDraw.Draw(l); d.rounded_rectangle([P(36), P(top), P(324) - 1, P(top + 40)], radius=P(20), fill=HEADER); d.rectangle([P(36), P(top + 20), P(324) - 1, P(top + 40)], fill=HEADER); img.alpha_composite(l)
    paste(img, icon(f'{A}/hero/256/hero_signin.png', 80), 48, top - 40)
    rr(img, (134, top + 6, 204, top + 34), 14, TAG); text(img, (146, top + 20), 'Sign in', 13)
    for i, ph in enumerate(['Email', 'Password']):
        y = top + 64 + i * 56
        rr(img, (56, y, 304, y + 46), 14, (255, 255, 255, 255), (0xDD, 0xD9, 0xCD, 255), 1.5); text(img, (70, y + 23), ph, 13, fill=MUTED, w='SemiBold')
    rr(img, (56, top + 186, 304, top + 230), 22, PRIMARY); text(img, (180, top + 208), 'Sign in', 14, anchor='mm', stroke=1)
    text(img, (180, top + 262), 'Create an account', 12, fill=(0x5E, 0x8A, 0x1E, 255), anchor='mm')
    return img

def strip():
    # phone tab bar, dressing chips, skills, reward/titles heroes
    W, H = 720, 300
    img = Image.new('RGBA', (P(W), P(H)), (0xEC, 0xE8, 0xDE, 255))
    # phone tab bar on dark phone screen
    rr(img, (16, 16, 256, 96), 24, (0x26, 0x29, 0x2E, 255)); rr(img, (24, 24, 248, 72), 24, (0x36, 0x3A, 0x40, 255))
    for i, (n, lab, on) in enumerate([('tasks', 'Tasks', True), ('inbox', 'Inbox', False), ('collection', 'Collection', False)]):
        ic = icon(f'{A}/color/128/icon_tab_{n}.png', 22)
        if not on:
            g = ic.convert('LA').convert('RGBA'); g = Image.blend(Image.new('RGBA', g.size, (0, 0, 0, 0)), g, 1.0)
            px = g.load(); a = ic.getchannel('A')
            from PIL import ImageEnhance
            g = ImageEnhance.Brightness(ic.convert('LA').convert('RGB')).enhance(0.5).convert('RGBA'); g.putalpha(a); ic = g
        x = 24 + i * 75 + 26; paste(img, ic, x, 28); text(img, (x + 11, 62), lab, 9, fill=(255, 255, 255, 255) if on else (0x9A, 0x9C, 0xA0, 255), anchor='mm')
    text(img, (136, 84), 'Phone tabs (selected / unselected)', 9, fill=(0xC8, 0xCA, 0xCC, 255), anchor='mm', w='Bold')
    # dressing chips on green bar
    rr(img, (272, 16, 560, 72), 28, (0xC4, 0xC6, 0x3C, 255))
    for i, n in enumerate(['hair', 'cloth', 'shoes', 'bag', 'glasses']):
        x = 282 + i * 56; ell(img, (x, 24, x + 40, 64), (255, 255, 255, 255))
        if i == 0: ell(img, (x - 2, 22, x + 42, 66), None, PRIMARY, 3)
        paste(img, icon(f'{A}/color/128/icon_dress_{n}.png', 24), x + 8, 32)
    text(img, (416, 86), 'Dressing categories', 9, fill=MUTED, anchor='mm', w='Bold')
    # skills
    for i, (n, lab, lv) in enumerate([('farming', 'Farming', 'Lv 4'), ('fishing', 'Fishing', 'Lv 6'), ('cooking', 'Cooking', 'Lv 3')]):
        x = 16 + i * 104; rr(img, (x, 116, x + 96, 164), 14, (255, 255, 255, 255))
        ell(img, (x + 8, 124, x + 40, 156), None, PRIMARY, 3); paste(img, icon(f'{A}/color/128/icon_skill_{n}.png', 20), x + 14, 130)
        text(img, (x + 46, 133), lab, 11, fill=TEXT); text(img, (x + 46, 149), lv, 10, fill=MUTED, w='Bold')
    # settings gear / exit on glass
    for i, n in enumerate(['settings', 'exit']):
        x = 352 + i * 48; ell(img, (x, 120, x + 36, 156), GLASS); paste(img, icon(f'{A}/sys/96/icon_sys_{n}.png', 24), x + 6, 126)
    text(img, (400, 172), 'Gear / leave plot', 9, fill=MUTED, anchor='mm', w='Bold')
    # titles & reward heroes on small panels
    for i, (n, lab) in enumerate([('hero_titles', 'Titles'), ('hero_reward', 'New item!'), ('hero_home', 'Your home'), ('hero_dressing', 'Dressing')]):
        x = 16 + i * 176; y = 224
        rr(img, (x, y, x + 164, y + 60), 16, PAPER)
        l = layer(img); d = ImageDraw.Draw(l); d.rounded_rectangle([P(x), P(y), P(x + 164) - 1, P(y + 32)], radius=P(16), fill=HEADER); d.rectangle([P(x), P(y + 16), P(x + 164) - 1, P(y + 32)], fill=HEADER); img.alpha_composite(l)
        paste(img, icon(f'{A}/hero/256/{n}.png', 64), x + 6, y - 30)
        tw = ImageDraw.Draw(img).textlength(lab, font=font(11)) / S; rr(img, (x + 74, y + 5, x + 74 + tw + 18, y + 27), 11, TAG); text(img, (x + 83, y + 16), lab, 11)
    return img

screens = [('① 农场 HUD、快捷栏、右侧按钮', screen_farm()), ('② 背包面板', screen_bag()), ('③ 商店面板', screen_market()), ('④ 地图地块卡', screen_map()), ('⑤ 登录面板', screen_signin())]
cjk = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 30, index=2)
cjk_s = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', 22, index=2)
sw, sh = P(360), P(640); gap = 40
st = strip()
W = 5 * sw + 6 * gap; H = 140 + sh + 70 + st.size[1] + 110
board = Image.new('RGB', (W, H), (0xF7, 0xF5, 0xEF)); d = ImageDraw.Draw(board)
d.rectangle([0, 0, W, 100], fill=(0x2B, 0x2A, 0x26))
d.text((gap, 50), 'C-86 UI 素材 · 游戏内效果对照（按 C-84 令牌 v3 与 C-85 版式摆放，2 倍）', font=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc', 40, index=2), fill='white', anchor='lm')
for i, (lab, im) in enumerate(screens):
    x = gap + i * (sw + gap); y = 140
    m = Image.new('L', im.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius=36, fill=255)
    board.paste(im.convert('RGB'), (x, y), m)
    d.text((x, y + sh + 16), lab, font=cjk, fill=(0x2B, 0x2A, 0x26))
y2 = 140 + sh + 70
board.paste(st.convert('RGB'), (gap, y2))
d.text((gap + st.size[0] + 40, y2 + 20), '⑥ 0.4.5 页面用到的素材', font=cjk, fill=(0x2B, 0x2A, 0x26))
notes = ['手机页签：选中彩色，未选中由代码去色并把亮度降到 50%（C-I4）',
         '换装分类、技能、齿轮、离开地块，以及称号、大奖励、我的家园、换装四个头图',
         '面板、按钮、胶囊都由代码按令牌绘制（C-I8）；关闭、返回等字形用 SVG（C-I5）',
         '背景是概念稿抽帧和 C-85 用的地图示意图，只用来看效果，不是本卡素材；文字只用英文']
for k, t in enumerate(notes): d.text((gap + st.size[0] + 40, y2 + 80 + k * 40), '· ' + t, font=cjk_s, fill=(0x55, 0x53, 0x4C))
board.save(OUT, optimize=True)
print(board.size)

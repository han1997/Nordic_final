#!/usr/bin/env python3
"""Nordic 的应用图标 —— **一份矢量源,派生所有产物**。

为什么要有这个脚本(而不是直接塞几张 PNG):
  - 图标要出现在三个地方 —— Android 的五档 mipmap、自适应图标的前景/单色层、
    以及原型的设计板与 favicon。手抄三份,迟早有一处对不上;
  - 每个候选的几何都是**几个数**(柱高、环径、符头位置),调一版要一眼看出改了
    哪几个数。这几个数就写在本文件的 VARIANTS 里,候选表同时也是
    「当时为什么选它」的记录。

**方向:音乐元素。** 上一版是一条纯几何的「极光弧」,看下来太像悬在黑方块中间的
一道弧,不像一个图标。这一版把音乐本身的东西摆到画面中央(均衡器 / 唱片 / 声波 /
音符),极光只作为**材质**留在它身上 —— 渐变与辉光那套语言不变,所以图标仍然和
应用里的玻璃与氛围是一家的。

产物:
  prototype/icon.js                     原型用(内联 SVG 片段 + favicon data URI)
  android/app/src/main/res/mipmap-*/   五档旧版图标(满幅,API 24–25 用)
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png   自适应前景(透明)
  android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png   主题图标单色层
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml     自适应图标
  android/app/src/main/res/values/colors.xml                     图标底与启动底共用

用法(Git Bash,仓库根):
  py -3 tool/app_icon.py --emit-prototype        # 只出原型片段(给设计板看)
  py -3 tool/app_icon.py --freeze m03            # 定稿:m03 写进 FINAL 并重出全部产物
  py -3 tool/app_icon.py --verify                # 校验已落盘 PNG 的尺寸与安全区
  py -3 tool/app_icon.py --out <dir> --android   # 落到别处(自检用,不碰 android/)

**画布**:108 单位 = 自适应图标的 108dp。中央 72(即 18..90)是**任何遮罩都保证
显示**的安全区;四边各 18 是出血。每个母题都**直接在安全区里作画** —— 所以自适应
那一版不再需要为「把图形缩进安全区」额外缩小,校验也是照着各母题自己报的墨迹框走。
"""

from __future__ import annotations

import argparse
import glob
import math
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
CANVAS = 108.0
CX = CY = 54.0              # 画布中心。安全区是 18..90,半径 36。

# ---------------------------------------------------------------- 规格

GROUND = '#07070C'          # = NordicTokens.dark.bg / --bg。图标自己的地面不跟主题走。
ACCENT = '#7C8CFF'          # = --accent
CYAN = '#5FE3F2'            # 冷青 —— **只活在图标里**,不往 tokens 里加(见 README)
MID = '#8BD8FF'             # 三停渐变的中间那一档

# 出图模式的缩放(以画布中心为基准)。母题本来就画在安全区里,所以自适应是 1.0;
# 旧版图标(API 24–25 的启动器**不遮罩**)留一圈近黑地面反而显小,放大一档更饱满。
SCALES = {
    'adaptive': 1.00,
    'legacy': 1.14,
}

# 候选表。`motif` 指向下面 MOTIFS 里的画法,其余键是那个画法自己的参数。
VARIANTS = [
    dict(id='m01', name='均衡器 · 四柱', motif='bars', note='28/50/36/60 高 · 全圆头',
         bars=[28, 50, 36, 60], bar_w=13, gap=6, base=79,
         stops=[ACCENT, CYAN], glow=(.42, 6.5)),
    dict(id='m02', name='均衡器 · 五柱', motif='bars', note='五根更细 · 三停渐变',
         bars=[24, 44, 58, 36, 50], bar_w=10, gap=5, base=79,
         stops=[ACCENT, MID, CYAN], glow=(.42, 6.5)),
    dict(id='m03', name='唱片 · 厚环 + 心', motif='disc', note='环外径 34.5 · 环厚 15 · 心 7',
         r=27, t=15, hole=7, stops=[ACCENT, CYAN], glow=(.40, 8)),
    dict(id='m04', name='唱片 · 满盘纹', motif='groove', note='实心盘 r34 · 两道挖空的纹',
         r=34, rings=[(24, 6), (14.5, 6)], hole=6,
         stops=[ACCENT, MID, CYAN], glow=(.40, 8)),
    dict(id='m05', name='声波 · 对称', motif='bars', note='绕中线对称的七根柱',
         bars=[10, 20, 31, 23, 33, 15, 23], bar_w=7.2, gap=3.2, mirror=True,
         stops=[ACCENT, CYAN], glow=(.40, 5)),
    dict(id='m06', name='音符 · 弧尾', motif='note', note='单八分 · 旗就是那道极光弧',
         stops=[ACCENT, CYAN], glow=(.45, 6.5)),
    dict(id='m07', name='音符 + 极光弧', motif='note_arc', note='弧从杆顶甩出去 · 同一笔',
         stops=[ACCENT, MID, CYAN], glow=(.45, 6.5)),
    dict(id='m08', name='双音符 · 联梁', motif='beam', note='最认得出的那个「音乐」',
         stops=[ACCENT, CYAN], glow=(.45, 6.5)),
]

FINAL = 'm05'   # 定稿 —— 由 `--freeze <id>` 改写这一行

# 自适应图标里那四种遮罩(原型的设计板上摆出来看;真机上再走一遍)
MASK_SHAPES_JS = {
    'circle': '<circle cx="54" cy="54" r="54"/>',
    'rounded': '<rect x="0" y="0" width="108" height="108" rx="26" ry="26"/>',
    # 水滴:近似 —— 右下四分之一换成直角。AOSP 的确切路径要在真机上校。
    'teardrop': '<path d="M108 54 A54 54 0 1 0 54 108 L108 108 Z"/>',
}


# ---------------------------------------------------------------- 小工具

def _num(v: float) -> str:
    """SVG 里的数字:短、且不给科学计数法。"""
    s = f'{v:.3f}'.rstrip('0').rstrip('.')
    return s if s else '0'


def _grad(v: dict, x1: float, y1: float, x2: float, y2: float) -> str:
    """横向/斜向的渐变。用 `userSpaceOnUse` 并给出显式端点 —— 窄图形上用
    bbox 单位会让停靠点随形状抖动,同一个渐变换个母题就变色了。"""
    stops = v['stops']
    n = max(len(stops) - 1, 1)
    body = ''.join(f'<stop offset="{_num(i / n * 100)}%" stop-color="{c}"/>'
                   for i, c in enumerate(stops))
    return (f'<linearGradient id="__UID__g" gradientUnits="userSpaceOnUse" '
            f'x1="{_num(x1)}" y1="{_num(y1)}" x2="{_num(x2)}" y2="{_num(y2)}">'
            f'{body}</linearGradient>')


def _pill(x: float, y: float, w: float, h: float, r: float, stroke: str) -> str:
    return (f'<rect x="{_num(x)}" y="{_num(y)}" width="{_num(w)}" height="{_num(h)}" '
            f'rx="{_num(r)}" ry="{_num(r)}" fill="{stroke}"/>')


def _ellipse(cx: float, cy: float, rx: float, ry: float, deg: float,
             stroke: str) -> str:
    return (f'<ellipse cx="{_num(cx)}" cy="{_num(cy)}" rx="{_num(rx)}" '
            f'ry="{_num(ry)}" transform="rotate({_num(deg)} {_num(cx)} {_num(cy)})" '
            f'fill="{stroke}"/>')


def _stroke(d: str, width: float, stroke: str) -> str:
    return (f'<path d="{d}" fill="none" stroke="{stroke}" '
            f'stroke-width="{_num(width)}" stroke-linecap="round" '
            f'stroke-linejoin="round"/>')


def _ellipse_box(cx: float, cy: float, rx: float, ry: float,
                 deg: float) -> tuple:
    """旋转椭圆的**外接框**。校验靠它 —— 不能靠肉眼估。"""
    a = math.radians(deg)
    hw = math.hypot(rx * math.cos(a), ry * math.sin(a))
    hh = math.hypot(rx * math.sin(a), ry * math.cos(a))
    return (cx - hw, cy - hh, cx + hw, cy + hh)


def _cubic_box(p0, c1, c2, p1, steps: int = 64) -> tuple:
    """三次贝塞尔的外接框。控制点会跑出曲线之外,所以**采样**而不是取控制点。"""
    xs: list[float] = []
    ys: list[float] = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        xs.append(u ** 3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0]
                  + t ** 3 * p1[0])
        ys.append(u ** 3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1]
                  + t ** 3 * p1[1])
    return (min(xs), min(ys), max(xs), max(ys))


def _grow(box: tuple, by: float) -> tuple:
    return (box[0] - by, box[1] - by, box[2] + by, box[3] + by)


def _union(*boxes: tuple) -> tuple:
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


# ---------------------------------------------------------------- 图形(母题)

def _bars(v: dict, solid: str | None, stroke: str) -> tuple:
    """一排圆角柱。`mirror` 时绕中线对称(声波),否则都坐在同一条基线上(均衡器)。"""
    hs, w, gap = v['bars'], v['bar_w'], v['gap']
    mirror = v.get('mirror', False)
    base = v.get('base', 79.0)
    total = len(hs) * w + (len(hs) - 1) * gap
    x0 = (CANVAS - total) / 2
    layers: list[str] = []
    tops: list[float] = []
    bots: list[float] = []
    x = x0
    for h in hs:
        y, hh = (CY - h, 2 * h) if mirror else (base - h, h)
        layers.append(_pill(x, y, w, hh, w / 2, stroke))
        tops.append(y)
        bots.append(y + hh)
        x += w + gap
    ink = (x0, min(tops), x0 + total, max(bots))
    defs = [] if solid else [_grad(v, x0, CY, x0 + total, CY)]
    return defs, layers, ink


def _disc(v: dict, solid: str | None, stroke: str) -> tuple:
    """唱片:一圈厚环 + 中心那颗孔。"""
    r, t, hole = v['r'], v['t'], v['hole']
    outer = r + t / 2
    layers = [
        f'<circle cx="{_num(CX)}" cy="{_num(CY)}" r="{_num(r)}" fill="none" '
        f'stroke="{stroke}" stroke-width="{_num(t)}"/>',
        f'<circle cx="{_num(CX)}" cy="{_num(CY)}" r="{_num(hole)}" fill="{stroke}"/>',
    ]
    ink = (CX - outer, CY - outer, CX + outer, CY + outer)
    defs = [] if solid else [_grad(v, ink[0], ink[1], ink[2], ink[3])]
    return defs, layers, ink


def _groove(v: dict, solid: str | None, stroke: str) -> tuple:
    """满盘 + 两道**挖空**的纹。<mask> 挖出来的洞在自适应前景里是透明的 ——
    正好露出系统铺的底色,所以「纹」是真的透光,不是画上去的深色线。"""
    r, ring_list, hole = v['r'], v['rings'], v['hole']
    defs: list[str] = []
    layers: list[str] = []
    if solid:
        # 单色层是「系统自己上色」的:纹路挖不出来(挖了就成断口),画成实心盘。
        layers.append(f'<circle cx="{_num(CX)}" cy="{_num(CY)}" r="{_num(r)}" '
                      f'fill="{stroke}"/>')
    else:
        cuts = ''.join(
            f'<circle cx="{_num(CX)}" cy="{_num(CY)}" r="{_num(rr)}" fill="none" '
            f'stroke="#000" stroke-width="{_num(w)}"/>' for rr, w in ring_list)
        defs.append(f'<mask id="__UID__m">'
                    f'<circle cx="{_num(CX)}" cy="{_num(CY)}" r="{_num(r)}" '
                    f'fill="#FFFFFF"/>{cuts}</mask>')
        defs.append(_grad(v, CX - r, CY - r, CX + r, CY + r))
        layers.append(f'<circle cx="{_num(CX)}" cy="{_num(CY)}" r="{_num(r)}" '
                      f'fill="url(#__UID__g)" mask="url(#__UID__m)"/>')
    layers.append(f'<circle cx="{_num(CX)}" cy="{_num(CY)}" r="{_num(hole)}" '
                  f'fill="{stroke}"/>')
    ink = (CX - r, CY - r, CX + r, CY + r)
    return defs, layers, ink


def _note(v: dict, solid: str | None, stroke: str) -> tuple:
    """单八分音符。旗甩成一道弧 —— 极光只留在这一笔上。

    所有数都写在这儿而不是参数化:符头/杆/旗的相对关系是**一个**造型,
    拆成参数只会让「换个数字」变成「换个形状」,候选之间就不可比了。"""
    hx, hy, rx, ry, rot = 34.0, 76.0, 14.0, 10.5, -18.0
    sx, sw, top = 44.0, 7.0, 24.0          # 杆心 / 杆厚 / 杆顶
    fw = 9.0                               # 旗的厚度
    f0, f1, f2, f3 = ((sx, top + 3), (sx + 22, top + 1), (sx + 34, top + 12),
                      (sx + 32, top + 30))
    layers = [
        _stroke(f'M{_num(sx)} {_num(top)} L{_num(sx)} {_num(hy + ry * .35)}',
                sw, stroke),
        _stroke(f'M{_num(f0[0])} {_num(f0[1])} C{_num(f1[0])} {_num(f1[1])}, '
                f'{_num(f2[0])} {_num(f2[1])}, {_num(f3[0])} {_num(f3[1])}',
                fw, stroke),
        _ellipse(hx, hy, rx, ry, rot, stroke),
    ]
    ink = _union(
        (sx - sw / 2, top, sx + sw / 2, hy + ry * .35),
        _grow(_cubic_box(f0, f1, f2, f3), fw / 2),
        _ellipse_box(hx, hy, rx, ry, rot),
    )
    defs = [] if solid else [_grad(v, ink[0], ink[1], ink[2], ink[3])]
    return defs, layers, ink


def _note_arc(v: dict, solid: str | None, stroke: str) -> tuple:
    """音符 + 极光弧 —— **弧就是这支音符的旗**,不是两个东西摞在一起。

    头还在左下、杆还是那根杆,只是杆顶那一笔拉长成横贯画布的弧:于是「音乐」
    与上一版那套极光语言合成了一笔。"""
    hx, hy, rx, ry, rot = 33.0, 76.0, 13.0, 9.5, -18.0
    sx, sw, top = 43.0, 7.0, 30.0
    tw = 8.5
    t0, t1, t2, t3 = (sx, top + 2), (58.0, 24.0), (72.0, 30.0), (74.0, 47.0)
    layers = [
        _stroke(f'M{_num(sx)} {_num(top)} L{_num(sx)} {_num(hy + ry * .35)}',
                sw, stroke),
        _stroke(f'M{_num(t0[0])} {_num(t0[1])} C{_num(t1[0])} {_num(t1[1])}, '
                f'{_num(t2[0])} {_num(t2[1])}, {_num(t3[0])} {_num(t3[1])}',
                tw, stroke),
        _ellipse(hx, hy, rx, ry, rot, stroke),
    ]
    ink = _union(
        (sx - sw / 2, top, sx + sw / 2, hy + ry * .35),
        _grow(_cubic_box(t0, t1, t2, t3), tw / 2),
        _ellipse_box(hx, hy, rx, ry, rot),
    )
    defs = [] if solid else [_grad(v, ink[0], 4, ink[2], 84)]
    return defs, layers, ink


def _beam(v: dict, solid: str | None, stroke: str) -> tuple:
    """双音符 + 联梁。两个符头、两根杆、一根斜梁 —— 最认得出的「音乐」。"""
    h1, h2 = (34.0, 75.0), (66.0, 69.0)
    rx, ry, rot = 13.0, 10.0, -18.0
    sw = 7.0
    s1, s2 = 44.0, 76.0                    # 两根杆的杆心
    t1, t2 = 32.0, 26.0                    # 两根杆的杆顶
    bw = 11.0                              # 梁厚
    left, right = s1 - sw / 2, s2 + sw / 2
    bar = (f'M{_num(left)} {_num(t1 - bw / 2)} L{_num(right)} {_num(t2 - bw / 2)} '
           f'L{_num(right)} {_num(t2 + bw / 2)} L{_num(left)} {_num(t1 + bw / 2)} Z')
    layers = [
        _stroke(f'M{_num(s1)} {_num(t1)} L{_num(s1)} {_num(h1[1] + ry * .3)}',
                sw, stroke),
        _stroke(f'M{_num(s2)} {_num(t2)} L{_num(s2)} {_num(h2[1] + ry * .3)}',
                sw, stroke),
        f'<path d="{bar}" fill="{stroke}"/>',
        _ellipse(h1[0], h1[1], rx, ry, rot, stroke),
        _ellipse(h2[0], h2[1], rx, ry, rot, stroke),
    ]
    ink = _union(
        (left, t2 - bw / 2, right, t1 + bw / 2),
        (s1 - sw / 2, t1, s1 + sw / 2, h1[1] + ry * .3),
        (s2 - sw / 2, t2, s2 + sw / 2, h2[1] + ry * .3),
        _ellipse_box(h1[0], h1[1], rx, ry, rot),
        _ellipse_box(h2[0], h2[1], rx, ry, rot),
    )
    defs = [] if solid else [_grad(v, ink[0], CY, ink[2], CY)]
    return defs, layers, ink


MOTIFS = {
    'bars': _bars,
    'disc': _disc,
    'groove': _groove,
    'note': _note,
    'note_arc': _note_arc,
    'beam': _beam,
}


def _draw(variant: dict, solid: str | None) -> tuple:
    """画一遍,返回 (defs, layers, 硬墨迹外接框)。**出图与校验走同一次计算** ——
    校验里的「应该在哪」不是手抄一份几何,而是这里刚算出来的那个框。"""
    stroke = solid or 'url(#__UID__g)'
    return MOTIFS[variant['motif']](variant, solid, stroke)


def art_markup(variant: dict, mode: str, solid: str | None = None) -> str:
    """一份图形的里层标记(不含外层 <svg>)。

    `solid` 非空时画成纯色(主题图标的单色层:系统自己上色,自己铺背景)。
    所有 id 带 `__UID__` 占位 —— 原型里一屏会内联好几个 SVG,同名 id 会互相
    抢(`url(#g)` 取到的是文档里第一个),那会让所有候选长成第一个的样子。
    """
    k = variant.get('scale', SCALES[mode])
    defs, layers, _ink = _draw(variant, solid)

    # 辉光:整组图形模糊一份垫在底下。**不裁下缘** —— 上一版那道弧要裁(模糊会把它
    # 自己的上缘糊毛),而这一版是好几块分开的形状,糊一圈反而正是霓虹的意思;
    # 清晰的那层压在上面,边缘不受影响。
    op, sigma = variant.get('glow', (0.0, 0.0))
    if not solid and op > 0:
        defs = defs + [f'<filter id="__UID__f" x="-50%" y="-50%" width="200%" '
                       f'height="200%">'
                       f'<feGaussianBlur stdDeviation="{_num(sigma)}"/></filter>']
        layers = [f'<g filter="url(#__UID__f)" opacity="{_num(op)}">'
                  f'{"".join(layers)}</g>'] + layers

    group = (f'<g transform="translate({_num(CX)} {_num(CY)}) '
             f'scale({_num(k)}) translate({_num(-CX)} {_num(-CY)})">'
             f'{"".join(layers)}</g>')
    return f'<defs>{"".join(defs)}</defs>{group}'


def ground_markup() -> str:
    """满幅深色地面。**只给 legacy** —— 自适应图标的底色来自 Android 的颜色资源
    (辉光要一块干净的底才读得出来,任何渐变都会跟它打架)。"""
    return f'<rect x="0" y="0" width="108" height="108" fill="{GROUND}"/>'


def svg_markup(variant: dict, mode: str, px: float, solid: str | None = None,
               uid: str = '', mask_shape: str | None = None) -> str:
    """一份完整的 <svg>。渲染与原型片段都走这一个函数 —— 不存第二份实现。"""
    art = art_markup(variant, mode, solid=solid).replace('__UID__', uid)
    ground = ground_markup() if (mode == 'legacy' and not solid) else ''
    if mask_shape:
        art = (f'<defs><clipPath id="{uid}m">{mask_shape}</clipPath></defs>'
               f'<g clip-path="url(#{uid}m)">{ground}{art}</g>')
        ground = ''
    return (f'<svg width="{_num(px)}" height="{_num(px)}" viewBox="0 0 108 108" '
            f'xmlns="http://www.w3.org/2000/svg">{ground}{art}</svg>')


def by_id(variant_id: str) -> dict:
    for v in VARIANTS:
        if v['id'] == variant_id:
            return v
    raise SystemExit(f'没有这个候选:{variant_id}(可选 {",".join(v["id"] for v in VARIANTS)})')


# ---------------------------------------------------------------- 出图

DENSITIES = [('mdpi', 1.0), ('hdpi', 1.5), ('xhdpi', 2.0),
             ('xxhdpi', 3.0), ('xxxhdpi', 4.0)]

SCRATCH = ROOT / '.tmp-shots' / 'icon-render'
OVERSAMPLE = 4          # 放大倍数取样 —— 靠 CSS 尺寸,不靠 --force-device-scale-factor


def find_chrome(explicit: str | None = None) -> str:
    """找 chromium。**不把本机路径写死进仓库** —— 换台机器照样能用。"""
    cands: list[str] = []
    if explicit:
        cands.append(explicit)
    env = os.environ.get('NORDIC_CHROME')
    if env:
        cands.append(env)
    local = os.environ.get('LOCALAPPDATA', '')
    if local:
        cands += sorted(glob.glob(str(Path(local) / 'ms-playwright' / 'chromium-*' /
                                       'chrome-win64' / 'chrome.exe')), reverse=True)
        cands.append(str(Path(local) / 'Google' / 'Chrome' / 'Application' / 'chrome.exe'))
    for name in ('google-chrome', 'chromium', 'chromium-browser'):
        cands += glob.glob(f'/usr/bin/{name}')
    for c in cands:
        if c and os.path.isfile(c):
            return c
    raise SystemExit('找不到 chromium:用 --chrome <路径>,或设 NORDIC_CHROME。')


def shoot(chrome: str, svg: str, size: int, out_png: Path) -> None:
    """把一份 SVG 截成 size×size 的 PNG(**真透明底**)。"""
    SCRATCH.mkdir(parents=True, exist_ok=True)
    px = size * OVERSAMPLE
    html = SCRATCH / f'{out_png.stem}.html'
    # 页面本身不放任何底色:靠 body 透明 + chromium 的 --default-background-color
    # 拿到 alpha 通道(在 .tmp-shots 的冒烟测试里验过)。
    scaled = (svg.replace(f'width="{_num(size)}"', f'width="{px}"', 1)
                 .replace(f'height="{_num(size)}"', f'height="{px}"', 1))
    html.write_text('<!doctype html><meta charset="utf-8">'
                    '<style>html,body{margin:0;padding:0;background:transparent}'
                    'svg{display:block}</style>' + scaled, encoding='utf-8')
    out_png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [chrome, '--headless=new', '--disable-gpu', '--hide-scrollbars',
         '--default-background-color=00000000', f'--window-size={px},{px}',
         f'--screenshot={out_png}', html.as_uri()],
        check=True, capture_output=True)


def downscale(src: Path, dst: Path, size: int) -> None:
    """降到目标尺寸。**先 premultiply alpha 再缩放、再 unpremultiply** ——
    直接缩 RGBA 会让透明边缘(以及辉光)出现黑边/彩边。"""
    import numpy as np
    from PIL import Image

    a = np.asarray(Image.open(src).convert('RGBA')).astype(np.float32)
    alpha = a[..., 3:4] / 255.0
    prem = np.concatenate([a[..., :3] * alpha, a[..., 3:4]], axis=-1)
    small = Image.fromarray(prem.astype(np.uint8)).resize((size, size), Image.LANCZOS)

    b = np.asarray(small).astype(np.float32)
    al = b[..., 3:4] / 255.0
    rgb = np.where(al > 0.0, b[..., :3] / np.maximum(al, 1e-6), 0.0)
    out = np.concatenate([np.clip(rgb, 0, 255), b[..., 3:4]], axis=-1)
    Image.fromarray(out.astype(np.uint8)).save(dst, optimize=True)


def render_png(chrome: str, variant: dict, mode: str, size: int, dst: Path,
               solid: str | None = None) -> None:
    uid = f'{variant["id"]}-{mode}-{size}'
    svg = svg_markup(variant, mode, size, solid=solid, uid=uid)
    big = SCRATCH / f'{dst.stem}.png'
    shoot(chrome, svg, size, big)
    downscale(big, dst, size)


# ---------------------------------------------------------------- 原型片段

def js_str(s: str) -> str:
    """JS 单引号字符串。反斜杠与单引号要 escape。"""
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def superellipse_path(points: int = 96) -> str:
    """超椭圆 |x/54|^4 + |y/54|^4 = 1,采样成折线 —— 系统的「方圆」遮罩就是它。"""
    parts = []
    for i in range(points + 1):
        t = i / points * 2 * math.pi
        c, s = math.cos(t), math.sin(t)
        x = 54 + 54 * math.copysign(abs(c) ** 0.5, c)
        y = 54 + 54 * math.copysign(abs(s) ** 0.5, s)
        parts.append(f'{"M" if i == 0 else "L"}{_num(x)} {_num(y)}')
    return '<path d="' + ' '.join(parts) + ' Z"/>'


def emit_prototype() -> Path:
    """写 prototype/icon.js —— 内联 SVG 片段 + favicon(原型仍然零外链)。"""
    art_js = []
    for v in VARIANTS:
        art_js.append(f"  '{v['id']}': {{\n"
                      f"    legacy:   {js_str(art_markup(v, 'legacy'))},\n"
                      f"    adaptive: {js_str(art_markup(v, 'adaptive'))},\n"
                      f"  }},")
    variants_js = ',\n'.join(
        f"  {{ id: {js_str(v['id'])}, name: {js_str(v['name'])}, "
        f"note: {js_str(v['note'])} }}" for v in VARIANTS)

    favicon_svg = svg_markup(by_id(FINAL), 'legacy', 32, uid='fav')
    favicon_uri = 'data:image/svg+xml,' + quote(favicon_svg, safe='')

    # 名字与顺序照着 Android 自己那四种遮罩来,免得设计板上的叫法和真机菜谱对不上。
    masks_js = ',\n'.join(
        f"  {{ id: {js_str(m['id'])}, name: {js_str(m['name'])}, "
        f"shape: {js_str(m['shape'])} }}" for m in [
            {'id': 'circle', 'name': '圆形', 'shape': MASK_SHAPES_JS['circle']},
            {'id': 'squircle', 'name': '方圆', 'shape': superellipse_path()},
            {'id': 'rounded', 'name': '圆角方', 'shape': MASK_SHAPES_JS['rounded']},
            {'id': 'teardrop', 'name': '水滴', 'shape': MASK_SHAPES_JS['teardrop']},
        ])

    body = f"""/* 由 tool/app_icon.py 生成,**不要手改**。
 *
 * 这里的图形与落到 Android 上的 PNG 出自**同一次 `svg_markup()` 调用** ——
 * 手改这边,设计板上看到的就和手机上装的对不上了。要改几何请改 tool/app_icon.py。
 *
 * 每个内联实例换一个唯一后缀(`__UID__` → `i1`、`i2`...):一屏里内联好几个 SVG 时,
 * 同名 id 会互相抢(`url(#g)` 取到的是文档里第一个),那会让所有候选都长成第一个。
 */
const ICON_VARIANTS = [
{variants_js}
];
const ICON_FINAL = {js_str(FINAL)};
const ICON_GROUND = {js_str(GROUND)};

const ICON_ART = {{
{chr(10).join(art_js)}
}};

/* 启动器可能用的四种遮罩(108 空间)。方圆是超椭圆采样,水滴是近似。 */
const ICON_MASKS = [
{masks_js}
];

let _iconUid = 0;

/** 一份图标的完整 <svg>。opts: {{mode:'legacy'|'adaptive', px, mask, ground}}
 *
 * 要不要铺地面(ground)默认跟着 mode 走:legacy 那几张 PNG 是**满幅不透明**的,
 * 所以铺;adaptive 的前景层是**透明底**的(地面由系统拿 <background> 铺),
 * 所以不铺。遮罩预览是例外 —— 那里要复现启动器的**合成结果**(底与前景一起被裁),
 * 所以显式传 ground:true。 */
function ICON_SVG(id, opts) {{
  opts = opts || {{}};
  const mode = opts.mode || 'legacy';
  const px = opts.px || 96;
  const uid = 'i' + (++_iconUid);
  const art = (ICON_ART[id] || ICON_ART[ICON_FINAL])[mode].split('__UID__').join(uid);
  const want = opts.ground === undefined ? (mode === 'legacy' && !opts.mask) : opts.ground;
  const ground = want
    ? `<rect x="0" y="0" width="108" height="108" fill="${{ICON_GROUND}}"/>` : '';
  const clip = opts.mask
    ? `<defs><clipPath id="${{uid}}m">${{opts.mask}}</clipPath></defs>` : '';
  const open = opts.mask ? `<g clip-path="url(#${{uid}}m)">` : '<g>';
  return `<svg class="icon-svg" width="${{px}}" height="${{px}}" viewBox="0 0 108 108" `
    + `xmlns="http://www.w3.org/2000/svg">${{clip}}${{open}}${{ground}}${{art}}</g></svg>`;
}}

/** 原型页签那颗小图标 —— 定稿的 legacy 版,内联成 data URI。 */
const ICON_FAVICON = {js_str(favicon_uri)};
"""
    out = ROOT / 'prototype' / 'icon.js'
    out.write_text(body, encoding='utf-8')
    return out


# ---------------------------------------------------------------- Android 资源

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- 自适应图标(API 26+)。前景是那个图形(含辉光),背景是一块**纯色** ——
     辉光要一块干净的底才读得出来,任何渐变背景都会跟它打架。
     几何全部来自 tool/app_icon.py,这里只是引用产物;改图标别改这个文件。 -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/nordic_bg"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
"""

COLORS_XML = f"""<?xml version="1.0" encoding="utf-8"?>
<!-- 图标自己的地面。**只此一处** —— 自适应图标的背景层与启动背景都引用它,
     两处各写一个十六进制迟早会不一致。值 = NordicTokens.dark.bg 那一项。 -->
<resources>
    <color name="nordic_bg">{GROUND}</color>
</resources>
"""


def emit_android(variant: dict, out_root: Path, chrome: str) -> list[Path]:
    written: list[Path] = []
    for name, scale in DENSITIES:
        d = out_root / f'mipmap-{name}'
        d.mkdir(parents=True, exist_ok=True)
        for fname, mode, px, solid in (
            ('ic_launcher.png', 'legacy', round(48 * scale), None),
            ('ic_launcher_foreground.png', 'adaptive', round(108 * scale), None),
            ('ic_launcher_monochrome.png', 'adaptive', round(108 * scale), '#FFFFFF'),
        ):
            dst = d / fname
            render_png(chrome, variant, mode, px, dst, solid=solid)
            written.append(dst)

    anydpi = out_root / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(ADAPTIVE_XML, encoding='utf-8')
    written.append(anydpi / 'ic_launcher.xml')

    values = out_root / 'values'
    values.mkdir(parents=True, exist_ok=True)
    (values / 'colors.xml').write_text(COLORS_XML, encoding='utf-8')
    written.append(values / 'colors.xml')
    return written


# ---------------------------------------------------------------- 校验

def _hard_bbox(im, mode: str):
    """**硬墨迹**的外接框(左,上,右,下),单位是画布单位(108 空间)。

    为什么不直接拿 `getbbox()`:辉光本来就要洇出图形 —— 那是一团 alpha 十几的
    柔光,遮罩切到它反而好看;而 `getbbox()` 把 alpha=1 的像素也算成墨迹,
    「墨迹该落在哪儿」这条就永远过不了。要校的是**图形本身**:
      - 透明底的(自适应前景 / 单色层):alpha ≥ 180 的像素;
      - 带地面的(旧版图标):与地面色的距离 > 90 的像素。

    90 这个阈值是算出来的,不是拍脑袋:图形与地面色的距离约 300,辉光在图形边缘
    那一圈的不透明度约 .5 × glow_op ≈ .22,落在近黑底上只差 ~62 —— 取 90 就正好
    把辉光关在门外,而图形自己的抗锯齿边缘(覆盖率过半时差 ~180)稳稳算进来。
    """
    import numpy as np

    a = np.asarray(im).astype(int)
    if mode == 'adaptive':
        mask = a[..., 3] >= 180
    else:
        ground = np.array([int(GROUND[i:i + 2], 16) for i in (1, 3, 5)])
        mask = np.sqrt(((a[..., :3] - ground) ** 2).sum(axis=-1)) > 90
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    unit = im.size[0] / CANVAS
    return (xs.min() / unit, ys.min() / unit,
            (xs.max() + 1) / unit, (ys.max() + 1) / unit)


def _expected_box(variant: dict, mode: str) -> tuple:
    """**按规格算出来**的墨迹外接框(画布单位)。

    「量出来的必须落在算出来的位置上」比「不许越界」有力得多:它同时挡住
    「图形缩小了 / 跑偏了 / 压根没画上」这几类错,而且换一个母题不用改校验 ——
    这个框就是刚才 `_draw()` 报出来的那一个,校验跟着图形走。
    """
    k = variant.get('scale', SCALES[mode])
    x0, y0, x1, y1 = _draw(variant, '#FFFFFF')[2]

    def to_canvas(v: float) -> float:      # art → 画布(以中心缩放 k)
        return CANVAS / 2 + (v - CANVAS / 2) * k

    return (to_canvas(x0), to_canvas(y0), to_canvas(x1), to_canvas(y1))


def verify(out_root: Path) -> int:
    """尺寸 / 图形落在规格算出来的位置上 / 四角干净 / 非空白。

    **只认已经落盘的产物** —— 校验与出图分开,「手机上的那几张到底合不合规」
    于是随时能复查一次。"""
    from PIL import Image

    # 量出来的与算出来的差多少算过:抗锯齿、渐变两端、alpha 阈值都会带来半个
    # 到一单位的偏移,再给一点余量。
    tol = 2.0
    variant = by_id(FINAL)
    bad: list[str] = []

    for name, scale in DENSITIES:
        d = out_root / f'mipmap-{name}'
        checks = [
            (d / 'ic_launcher.png', round(48 * scale), 'legacy'),
            (d / 'ic_launcher_foreground.png', round(108 * scale), 'adaptive'),
            (d / 'ic_launcher_monochrome.png', round(108 * scale), 'adaptive'),
        ]
        for path, px, mode in checks:
            if not path.exists():
                bad.append(f'缺文件:{path}')
                continue
            im = Image.open(path).convert('RGBA')
            if im.size != (px, px):
                bad.append(f'{path.name} 尺寸 {im.size},应为 {(px, px)}')
            if im.getbbox() is None:
                bad.append(f'{path.name} 是空白的')
                continue
            if mode == 'adaptive':
                # 四角必须透明 —— 否则自适应图标会露出一块方角
                for corner in ((0, 0), (px - 1, 0), (0, px - 1), (px - 1, px - 1)):
                    if im.getpixel(corner)[3] != 0:
                        bad.append(f'{path.name} 的角不透明:{corner}')
            else:
                # 旧版图标的地面是满幅的:四角必须是地面色(差一点点是辉光洇上去的)
                g = tuple(int(GROUND[i:i + 2], 16) for i in (1, 3, 5))
                for corner in ((0, 0), (px - 1, 0), (0, px - 1), (px - 1, px - 1)):
                    got = im.getpixel(corner)[:3]
                    if max(abs(got[i] - g[i]) for i in range(3)) > 14:
                        bad.append(f'{path.name} 的角不是地面色:{corner} → {got},'
                                   f'地面 {g}')
            box = _hard_bbox(im, mode)
            if box is None:
                bad.append(f'{path.name} 没有硬墨迹(只剩一层柔光?)')
                continue
            want = _expected_box(variant, mode)
            drift = [abs(box[i] - want[i]) for i in range(4)]
            if max(drift) > tol:
                bad.append(
                    f'{path.name} 的图形与规格对不上:量到 '
                    f'({box[0]:.1f}, {box[1]:.1f}, {box[2]:.1f}, {box[3]:.1f}),'
                    f'规格是 ({want[0]:.1f}, {want[1]:.1f}, {want[2]:.1f}, '
                    f'{want[3]:.1f}),最大差 {max(drift):.1f} 画布单位')

    for extra in ('mipmap-anydpi-v26/ic_launcher.xml', 'values/colors.xml'):
        if not (out_root / extra).exists():
            bad.append(f'缺文件:{out_root / extra}')

    # XML 注释里不许出现 `--`,AAPT 直接判死(踩过一次:注释里写了「--bg」这种
    # 记号,一路走到 packageReleaseResources 才炸)。这儿拦下来,别等打包。
    for path in sorted(out_root.rglob('*.xml')):
        for body in re.findall(r'<!--(.*?)-->', path.read_text(encoding='utf-8'),
                               re.S):
            if '--' in body:
                bad.append(f'{path.name} 的注释里有 `--`,AAPT 会拒绝')

    if bad:
        print('校验没过:')
        for line in bad:
            print('  -', line)
        return 1
    print(f'校验通过({FINAL}):{len(DENSITIES)} 档 × 3 张 + 自适应 XML + colors.xml')
    return 0


# ---------------------------------------------------------------- 入口

def freeze(variant_id: str) -> None:
    """把定稿写回本文件的 `FINAL` 那一行 —— 定稿只有一处真值。"""
    by_id(variant_id)
    path = Path(__file__).resolve()
    src = path.read_text(encoding='utf-8')
    new, n = re.subn(r"^FINAL = '\w+'", f"FINAL = '{variant_id}'",
                     src, count=1, flags=re.M)
    if n != 1:
        raise SystemExit('FINAL 那一行没找到,没敢改')
    # 文件改了,进程里的 `FINAL` 也得跟着改 —— 否则同一次调用里
    # `--freeze m05 --emit-prototype` 会拿着旧的 FINAL 出片段。
    globals()['FINAL'] = variant_id
    if new != src:
        path.write_text(new, encoding='utf-8')
        print(f'定稿:{variant_id}(已写回 tool/app_icon.py 的 FINAL)')


def main() -> int:
    ap = argparse.ArgumentParser(description='Nordic 应用图标:生成器')
    ap.add_argument('--emit-prototype', action='store_true', help='只出 prototype/icon.js')
    ap.add_argument('--android', action='store_true', help='出 Android 资源')
    ap.add_argument('--freeze', metavar='ID', help='把某个候选写成定稿')
    ap.add_argument('--verify', action='store_true', help='校验已落盘的产物')
    ap.add_argument('--out', help='Android 资源的落点(自检用,不碰仓库里的 android/)')
    ap.add_argument('--chrome', help='chromium 可执行文件的路径')
    args = ap.parse_args()

    out_root = Path(args.out).resolve() if args.out else \
        ROOT / 'android' / 'app' / 'src' / 'main' / 'res'

    if args.freeze:
        freeze(args.freeze)

    if args.emit_prototype or not (args.android or args.verify):
        out = emit_prototype()
        print(f'原型片段:{out.relative_to(ROOT)}(定稿 {FINAL})')

    if args.android:
        written = emit_android(by_id(FINAL), out_root, find_chrome(args.chrome))
        print(f'Android 资源:{len(written)} 个文件 → {out_root}')

    if args.verify:
        return verify(out_root)
    return 0


if __name__ == '__main__':
    sys.exit(main())
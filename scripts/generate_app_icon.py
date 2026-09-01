# -*- coding: utf-8 -*-
"""NEXUS Agent 品牌图标生成器。

设计语言（对齐 mobile-agent-ui-prototype/DESIGN.md）：
- 深空底（#0B0F1A → #1A2340 对角渐变）+ 青 #38E8FF / 紫 #7C6CFF / 品红 #C86CFF 三色光晕
- 中心四角星（Agent 核心）+ 三个 Provider 节点环绕（多 Provider 聚合语义）

输出（直接写入 android/app/src/main/res/）：
- mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png   传统图标（背景+图形）
- drawable/ic_launcher_background.png            自适应背景（仅渐变）
- mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_foreground.png 自适应前景（透明底+图形）
- mipmap-anydpi-v26/ic_launcher.xml              自适应图标声明
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

BRAND = {
    'cyan': (0x38, 0xE8, 0xFF),
    'violet': (0x7C, 0x6C, 0xFF),
    'magenta': (0xC8, 0x6C, 0xFF),
}
DEEP_BG_TOP = (0x0B, 0x0F, 0x1A)
DEEP_BG_BOTTOM = (0x1A, 0x23, 0x40)

CANVAS = 1024
CENTER = CANVAS / 2
RES_DIR = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')

# 自适应图标安全区：中心 66%（Android 规范），前景图形不得超出
SAFE_RATIO = 0.66


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def radial_glow(size, color, cx, cy, radius, alpha=150):
    """在画布上叠加一处径向光晕。"""
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 40
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(alpha * (steps - i + 1) / steps)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (a,))
    layer = layer.filter(ImageFilter.GaussianBlur(radius / 6))
    return layer


def build_background(size=CANVAS):
    """深空对角渐变 + 三色品牌光晕。"""
    img = Image.new('RGBA', (size, size))
    px = img.load()
    for y in range(size):
        t = y / size
        row = lerp(DEEP_BG_TOP, DEEP_BG_BOTTOM, t)
        for x in range(size):
            px[x, y] = row + (255,)
    img = img.convert('RGBA')
    img.alpha_composite(radial_glow(size, BRAND['cyan'], size * 0.28, size * 0.24, size * 0.55, 110))
    img.alpha_composite(radial_glow(size, BRAND['violet'], size * 0.72, size * 0.26, size * 0.5, 100))
    img.alpha_composite(radial_glow(size, BRAND['magenta'], size * 0.5, size * 0.85, size * 0.6, 95))
    return img


def brand_gradient_mask(size=CANVAS):
    """对角线品牌渐变（青 → 紫 → 品红）作为填充用图层。"""
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            if t < 0.5:
                c = lerp(BRAND['cyan'], BRAND['violet'], t * 2)
            else:
                c = lerp(BRAND['violet'], BRAND['magenta'], (t - 0.5) * 2)
            px[x, y] = c
    return img


def star_points(cx, cy, outer, inner, n=4, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = outer if i % 2 == 0 else inner
        ang = rot + i * math.pi / n
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


def build_foreground(size=CANVAS):
    """透明底 + 中心四角星 + 三个 Provider 节点。图形限制在安全区内。"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    safe = size * SAFE_RATIO
    cx = cy = size / 2

    # 中心四角星（品牌渐变填充 + 白色柔边）
    outer = safe * 0.34
    inner = safe * 0.13
    star = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(star).polygon(star_points(cx, cy, outer, inner), fill=(255, 255, 255, 255))
    star = star.filter(ImageFilter.GaussianBlur(size * 0.006))
    grad = brand_gradient_mask(size).convert('RGBA')
    core = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    core.paste(grad, (0, 0), star)
    img.alpha_composite(core)
    # 白色柔光描边
    glow = star.filter(ImageFilter.GaussianBlur(size * 0.02))
    img.alpha_composite(glow)

    # 三个 Provider 节点（白芯 + 品牌渐变环），分布于中心星周围
    nodes = [
        (cx - safe * 0.30, cy - safe * 0.26),
        (cx + safe * 0.30, cy - safe * 0.26),
        (cx, cy + safe * 0.36),
    ]
    node_r = safe * 0.075
    ring_r = node_r * 1.55
    d = ImageDraw.Draw(img)
    for (nx, ny) in nodes:
        d.ellipse([nx - ring_r, ny - ring_r, nx + ring_r, ny + ring_r], fill=None, outline=BRAND['violet'] + (200,), width=max(2, int(size * 0.008)))
        d.ellipse([nx - node_r, ny - node_r, nx + node_r, ny + node_r], fill=(245, 248, 255, 255))
        d.ellipse([nx - node_r * 0.45, ny - node_r * 0.45, nx + node_r * 0.45, ny + node_r * 0.45], fill=BRAND['cyan'] + (255,))
    # 节点 → 中心星的连接线（半透明白）
    for (nx, ny) in nodes:
        dx, dy = cx - nx, cy - ny
        dist = math.hypot(dx, dy)
        ux, uy = dx / dist, dy / dist
        x0, y0 = nx + ux * ring_r, ny + uy * ring_r
        x1, y1 = cx + ux * inner * 1.6, cy + uy * inner * 1.6
        d.line([x0, y0, x1, y1], fill=(255, 255, 255, 150), width=max(2, int(size * 0.006)))
    return img


def save_resized(img, path, size):
    img = img.resize((size, size), Image.LANCZOS)
    img.convert('RGBA').save(path)
    print(f'  {os.path.relpath(path, os.path.dirname(RES_DIR))}  {size}x{size}')


def main():
    os.makedirs(RES_DIR, exist_ok=True)
    bg = build_background(CANVAS)
    fg = build_foreground(CANVAS)
    # 传统图标 = 背景 + 图形
    legacy = bg.copy()
    legacy.alpha_composite(fg)

    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    base = 48  # mdpi 传统图标尺寸
    fg_base = 108  # mdpi 自适应前景尺寸

    print('[传统图标 ic_launcher.png]')
    for name, mul in densities.items():
        d = os.path.join(RES_DIR, f'mipmap-{name}')
        os.makedirs(d, exist_ok=True)
        save_resized(legacy, os.path.join(d, 'ic_launcher.png'), int(base * mul))

    print('[自适应前景 ic_launcher_foreground.png]')
    for name, mul in densities.items():
        d = os.path.join(RES_DIR, f'mipmap-{name}')
        os.makedirs(d, exist_ok=True)
        save_resized(fg, os.path.join(d, 'ic_launcher_foreground.png'), int(fg_base * mul))

    print('[自适应背景 ic_launcher_background.png]')
    drawable = os.path.join(RES_DIR, 'drawable')
    os.makedirs(drawable, exist_ok=True)
    save_resized(bg, os.path.join(drawable, 'ic_launcher_background.png'), 432)

    print('[adaptive-icon 声明 ic_launcher.xml]')
    anydpi = os.path.join(RES_DIR, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w', encoding='utf-8') as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
    print('  mipmap-anydpi-v26/ic_launcher.xml')
    print('\n完成。')


if __name__ == '__main__':
    main()

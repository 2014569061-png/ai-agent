"""为三个不达 AA 的语义色筛选替代值。

现有值（on 白卡）：danger #E5484D 3.91 / success #2BA471 3.16 / warning #F5A623 2.03
目标：>= 4.5:1（保证作为正文/标签文字色可用）
"""
from __future__ import annotations


def _lin(c: float) -> float:
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = rgb
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def ratio(fg, bg):
    a, b = lum(fg), lum(bg)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def hexc(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


WHITE = hexc("FFFFFF")
L1 = hexc("F7F8FA")
DARK = hexc("0F121C")
SOFT = {"danger": hexc("FDECEE"), "success": hexc("EAF8F1"), "warning": hexc("FEF7EA")}

CANDS = {
    "danger": ["C62828", "B3261E", "B91C1C", "C0392B", "A81E1E", "9E1B1B"],
    "success": ["107C41", "047857", "0F7B4F", "157347", "0E6E4A", "1A7F5A"],
    "warning": ["8A5A00", "9A6700", "A16207", "92400E", "8B5A00", "7A4E00"],
}

print("=" * 76)
print("语义色候选（需 >= 4.5:1；同时给出在各自 soft 底上的表现）")
print("=" * 76)
for tone, cands in CANDS.items():
    print(f"\n[{tone}]  soft 底 = #{''.join(f'{v:02X}' for v in SOFT[tone])}")
    print(f"  {'色值':10} {'on白卡':>8} {'onL1':>7} {'onSoft':>8} {'on深色底':>9}")
    for c in cands:
        rgb = hexc(c)
        r_w, r_l = ratio(rgb, WHITE), ratio(rgb, L1)
        r_s = ratio(rgb, SOFT[tone])
        r_d = ratio(rgb, DARK)
        ok = "OK " if r_w >= 4.5 else "   "
        print(f"  #{c:8} {r_w:7.2f}{ok} {r_l:7.2f} {r_s:8.2f} {r_d:9.2f}")

print()
print("=" * 76)
print("深色模式下的语义色（现有值 on darkCanvas #0F121C）")
print("=" * 76)
for tone, cur in [("danger", "E5484D"), ("success", "2BA471"), ("warning", "F5A623")]:
    r = ratio(hexc(cur), DARK)
    print(f"  {tone:8} #{cur}  on 深色画布 = {r:5.2f}  {'PASS' if r >= 4.5 else 'FAIL'}")

print()
print("=" * 76)
print("浅色画布微渐变候选（收敛极光后，保持中性）")
print("=" * 76)
cands = [
    ("极淡冷灰上", "FAFBFC"),
    ("极淡冷灰下", "F4F6F9"),
    ("稍强冷灰上", "F8FAFC"),
    ("稍强冷灰下", "EFF2F6"),
]
for name, c in cands:
    rgb = hexc(c)
    print(
        f"  {name:12} #{c}  白卡对比 {ratio(WHITE, rgb):5.3f}  "
        f"次要文字#6B7280对比 {ratio(hexc('6B7280'), rgb):5.2f}"
    )

"""一次性对比度审计：把当前 palette / 背景光斑 / 建议新值全部算一遍。

WCAG 2.1 阈值：
  AA  正文文本 4.5:1   |  大字(>=18.66px bold 或 >=24px) 3.0:1
  AA  非文本(UI 边界/图标) 3.0:1
"""
from __future__ import annotations


def _lin(c: float) -> float:
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb) -> float:
    r, g, b = rgb
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def ratio(fg, bg) -> float:
    a, b = lum(fg), lum(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def hexc(s: str):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def over(fg, alpha: float, bg) -> tuple:
    """fg 以 alpha 叠在 bg 上，返回实际渲染色。"""
    return tuple(round(alpha * f + (1 - alpha) * b) for f, b in zip(fg, bg))


def h(label: str, fg, bg, need: float) -> None:
    r = ratio(fg, bg)
    mark = "PASS" if r >= need else "FAIL"
    print(f"{mark:4} {r:5.2f}  (需 {need:.1f})  {label}")


print("=" * 78)
print("一、当前浅色配色：文字 / 卡片 对 白色卡片底")
print("=" * 78)
w = hexc("FFFFFF")
h("正文 #1A1A1A on 白卡", hexc("1A1A1A"), w, 4.5)
h("次要 #6B7280 on 白卡", hexc("6B7280"), w, 4.5)
h("强调 #335CFF on 白卡（文本态）", hexc("335CFF"), w, 4.5)
h("brandOnSoft #2344D0 on brandSoft #EEF2FF", hexc("2344D0"), hexc("EEF2FF"), 4.5)
h("danger #E5484D on 白卡", hexc("E5484D"), w, 4.5)
h("success #2BA471 on 白卡", hexc("2BA471"), w, 4.5)
h("warning #F5A623 on 白卡", hexc("F5A623"), w, 4.5)

print()
print("--- 规范文档 2.5 节遗留值 ---")
h("规范遗留 #4D6BFE on 白卡", hexc("4D6BFE"), w, 4.5)
h("规范文本态 #3A55E5 on 白卡", hexc("3A55E5"), w, 4.5)

print()
print("=" * 78)
print("二、当前分层手段：hairline 描边（非文本 UI 边界，需 3.0:1）")
print("=" * 78)
h("lightHairline #E2E7F1 on 白卡 #FFFFFF", hexc("E2E7F1"), w, 3.0)
h("lightHairline #E2E7F1 on lightSurface #F5F7FB", hexc("E2E7F1"), hexc("F5F7FB"), 3.0)
h("lightSurfaceHover #EEF1F8 on 白卡", hexc("EEF1F8"), w, 3.0)
h("规范 L1 #F7F8FA on 白卡", hexc("F7F8FA"), w, 3.0)
h("规范 L2 #EDEFF4 on 白卡", hexc("EDEFF4"), w, 3.0)

print()
print("=" * 78)
print("三、NexusBackground 极光背景（非 flat 档实际渲染）")
print("=" * 78)
grad = [hexc("DCEBFE"), hexc("F2F6FE"), hexc("E2E9FB")]  # 渐变三点
orbs = [
    ("左上 天蓝 #0284C7", hexc("0284C7"), 0.32),
    ("右中 紫 #A855F7", hexc("A855F7"), 0.28),
    ("左下 冰蓝 #38BDF8", hexc("38BDF8"), 0.28),
    ("顶中 浅蓝 #BAE6FD", hexc("BAE6FD"), 0.35),
]
print("-- 光斑中心实际渲染色（叠在渐变中段上）--")
rendered = []
for name, c, a in orbs:
    r = over(c, a, grad[1])
    rendered.append(r)
    print(f"    {name:24} -> rgb{r}  #{r[0]:02X}{r[1]:02X}{r[2]:02X}")

print()
print("-- 白卡 #FFFFFF 在这些背景上的对比度（卡片边界是否看得见）--")
for name, c, a in orbs:
    r = over(c, a, grad[1])
    val = ratio(w, r)
    print(f"    {val:5.2f}  白卡 on {name}")
print(f"    {ratio(w, grad[1]):5.2f}  白卡 on 渐变中段 #F2F6FE")
print(f"    {ratio(w, grad[0]):5.2f}  白卡 on 渐变顶部 #DCEBFE")

print()
print("-- 正文/次要文字 直接落在极光背景上（不套卡片时）--")
worst = over(hexc("0284C7"), 0.32, grad[0])
print(f"    最暗背景近似 rgb{worst} #{worst[0]:02X}{worst[1]:02X}{worst[2]:02X}")
h("正文 #1A1A1A on 最暗极光", hexc("1A1A1A"), worst, 4.5)
h("次要 #6B7280 on 最暗极光", hexc("6B7280"), worst, 4.5)

print()
print("=" * 78)
print("四、当前深色配色")
print("=" * 78)
dcan, dsur = hexc("0F121C"), hexc("181D2A")
h("正文 #E6E8EF on darkCanvas", hexc("E6E8EF"), dcan, 4.5)
h("次要 #A8B0C4 on darkCanvas", hexc("A8B0C4"), dcan, 4.5)
h("最弱 #8A90A4 on darkCanvas", hexc("8A90A4"), dcan, 4.5)
h("正文 #E6E8EF on darkSurface", hexc("E6E8EF"), dsur, 4.5)
h("次要 #A8B0C4 on darkSurface", hexc("A8B0C4"), dsur, 4.5)
h("最弱 #8A90A4 on darkSurface", hexc("8A90A4"), dsur, 4.5)
dh = over(hexc("FFFFFF"), 0.12, dsur)
print(f"    darkHairline 实际渲染 rgb{dh}")
print(f"    {ratio(dh, dsur):5.2f}  darkHairline on darkSurface（需 3.0）")

print()
print("=" * 78)
print("五、建议方案（把分层从描边改为填充色阶 + 收敛光斑）")
print("=" * 78)
sug = {
    "L0 canvas": hexc("FFFFFF"),
    "L1 subtle": hexc("F7F8FA"),
    "L2 raised": hexc("EDEFF4"),
    "L3 inverse": hexc("16181D"),
}
print("-- 建议色阶之间的块面对比度（目标 1.05~1.3 之间：可辨但不割裂）--")
keys = list(sug)
for i in range(len(keys) - 1):
    a, b = sug[keys[i]], sug[keys[i + 1]]
    print(f"    {ratio(a, b):5.3f}  {keys[i]} vs {keys[i + 1]}")
print()
h("L3 #16181D on 白底（高对比锚点）", sug["L3 inverse"], w, 4.5)
print()
print("-- 建议的文字层级 --")
h("主文字 #16181D on 白卡", hexc("16181D"), w, 4.5)
h("主文字 #16181D on L1 #F7F8FA", hexc("16181D"), sug["L1 subtle"], 4.5)
h("次文字 #5A5F6B on 白卡", hexc("5A5F6B"), w, 4.5)
h("次文字 #5A5F6B on L1 #F7F8FA", hexc("5A5F6B"), sug["L1 subtle"], 4.5)
h("次文字 #6B7280 on L1 #F7F8FA", hexc("6B7280"), sug["L1 subtle"], 4.5)
h("强调 #335CFF on L1 #F7F8FA", hexc("335CFF"), sug["L1 subtle"], 4.5)

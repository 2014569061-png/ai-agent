import sys, os, json

LCOV = r"coverage/lcov.info"

def parse(lcov):
    data = {}
    cur = None
    with open(lcov, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("SF:"):
                cur = line[3:].strip().replace("\\", "/")
                data.setdefault(cur, {"lf": 0, "lh": 0, "brf": 0, "brh": 0, "fnf": 0, "fnh": 0})
            elif line.startswith("LF:") and cur:
                data[cur]["lf"] = int(line[3:])
            elif line.startswith("LH:") and cur:
                data[cur]["lh"] = int(line[3:])
            elif line.startswith("BRF:") and cur:
                data[cur]["brf"] = int(line[4:])
            elif line.startswith("BRH:") and cur:
                data[cur]["brh"] = int(line[4:])
            elif line.startswith("FNF:") and cur:
                data[cur]["fnf"] = int(line[4:])
            elif line.startswith("FNH:") and cur:
                data[cur]["fnh"] = int(line[4:])
    return data

def pct(h, f):
    return 100.0 * h / f if f else 0.0

def main():
    d = parse(LCOV)
    tot_lf = sum(v["lf"] for v in d.values())
    tot_lh = sum(v["lh"] for v in d.values())
    tot_brf = sum(v["brf"] for v in d.values())
    tot_brh = sum(v["brh"] for v in d.values())
    tot_fnf = sum(v["fnf"] for v in d.values())
    tot_fnh = sum(v["fnh"] for v in d.values())
    print("=== GLOBAL (from lcov.info) ===")
    print("files reported: %d" % len(d))
    print("lines: %d/%d = %.2f%%" % (tot_lh, tot_lf, pct(tot_lh, tot_lf)))
    print("branches: %d/%d = %.2f%%" % (tot_brh, tot_brf, pct(tot_brh, tot_brf)))
    print("functions: %d/%d = %.2f%%" % (tot_fnh, tot_fnf, pct(tot_fnh, tot_fnf)))
    print()

    # lib files actually on disk
    libfiles = []
    for root, dirs, files in os.walk("lib"):
        for fn in files:
            if fn.endswith(".dart"):
                libfiles.append(os.path.join(root, fn).replace("\\", "/"))
    libfiles_nogen = [p for p in libfiles if not p.endswith(".g.dart")]
    print("=== lib dart files on disk: %d (excluding .g.dart: %d) ===" % (len(libfiles), len(libfiles_nogen)))
    inl = set(d.keys())
    # lcov SF paths may be absolute; normalize to find lib segment
    def norm(p):
        i = p.find("lib/")
        return p[i:] if i >= 0 else p
    cov_norm = {norm(k): k for k in d}
    missing = [p for p in libfiles_nogen if p not in cov_norm]
    print("lib files with NO lcov entry at all: %d" % len(missing))
    print()
    print("=== TOP 45 LARGEST lib FILES BY LINE COUNT + COVERAGE ===")
    sizes = []
    for p in libfiles_nogen:
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                n = sum(1 for _ in f)
        except Exception:
            n = 0
        key = cov_norm.get(p)
        if key:
            v = d[key]
            sizes.append((n, p, v["lh"], v["lf"], pct(v["lh"], v["lf"]), v["brh"], v["brf"]))
        else:
            sizes.append((n, p, 0, 0, -1.0, 0, 0))
    sizes.sort(reverse=True)
    print("%6s %7s %8s %8s %8s  %s" % ("lines", "cov%", "lh", "lf", "br%", "path"))
    for n, p, lh, lf, pc, brh, brf in sizes[:45]:
        pcs = "NOT-IN-LCOV" if pc < 0 else "%.1f%%" % pc
        brs = "%.1f%%" % pct(brh, brf) if brf else "n/a"
        print("%6d %9s %8d %8d %8s  %s" % (n, pcs, lh, lf, brs, p))
    print()
    print("=== WORST-COVERED LARGE FILES (>=300 lines, coverable, sorted by cov%) ===")
    big = [s for s in sizes if s[0] >= 300 and s[3] > 0]
    big.sort(key=lambda x: x[4])
    for n, p, lh, lf, pc, brh, brf in big[:40]:
        print("%6d lines  %6.1f%%  lf=%5d  %s" % (n, pc, lf, p))
    print()
    print("=== 0%% (lf>0, lh==0) FILES, ALL ===")
    zero = [s for s in sizes if s[3] > 0 and s[2] == 0]
    zero.sort(reverse=True)
    for n, p, lh, lf, pc, brh, brf in zero:
        print("%6d lines  lf=%5d  %s" % (n, lf, p))
    print("count of 0%% files: %d" % len(zero))

    print()
    print("=== SPECIFIC FILES REQUESTED ===")
    want = [
        "lib/application/chat_controller.dart",
        "lib/application/chat_run_execution.dart",
        "lib/presentation/chat/chat_page.dart",
        "lib/infrastructure/tools/android_device_tool.dart",
        "lib/infrastructure/tools/command_tool.dart",
        "lib/presentation/tasks/task_details_page.dart",
    ]
    for w in want:
        key = cov_norm.get(w)
        lines = 0
        if os.path.exists(w):
            with open(w, "r", encoding="utf-8", errors="replace") as f:
                lines = sum(1 for _ in f)
        if key:
            v = d[key]
            print("%s" % w)
            print("   disk_lines=%d  lf=%d lh=%d -> line cov %.2f%%  (branches %.2f%% %d/%d, funcs %d/%d)" % (
                lines, v["lf"], v["lh"], pct(v["lh"], v["lf"]),
                pct(v["brh"], v["brf"]), v["brh"], v["brf"], v["fnh"], v["fnf"]))
        else:
            print("%s -> NO LCOV ENTRY (disk_lines=%d)" % (w, lines))

main()
